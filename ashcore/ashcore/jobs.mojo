"""
AshCore - Job System
Thread pool with work-sharing scheduler and two DAG executors.

  ThreadPool    - fixed worker count, distributes tasks via a single atomic counter
  TaskGraph     - static DAG: seal() computes topological levels via Kahn's; each
                  level runs fully parallel behind an implicit barrier
  ReactiveGraph - reactive DAG: zero-copy event-queue driven, no level barriers;
                  jobs start the moment their last dependency completes (atomic
                  in-degree tracking, MPMC ready queue via TicketLock)

When to use which:
  TaskGraph     - predictable graphs, levels have similar job durations, low overhead
  ReactiveGraph - uneven job durations where level barriers waste CPU; pipelines
                  where downstream work can start before the slowest upstream finishes
"""

from std.atomic    import Atomic
from std.algorithm import parallelize
from std.sys       import num_physical_cores
from ashcore.queue import SPSCQueue, PopResult
from ashcore.sync  import TicketLock, Semaphore
from ashcore.debug import DEBUG, dbg_assert, dbg_bounds, dbg_positive


# ---------------------------------------------------------------------------
# ThreadPool  — simple, correct, fast
# ---------------------------------------------------------------------------

comptime MAX_WORKERS: Int = 256


struct ThreadPool:
    """
    Fixed-size thread pool that drains a job queue in parallel.

    Workers compete for tasks via an atomic counter (work-sharing, low overhead).
    The pool re-uses OS threads managed by the Mojo runtime's parallelize
    primitive — no thread creation or destruction per run.

    Example:
        var pool = ThreadPool()         # num_physical_cores() workers

        var data = List[Int](capacity=1024)
        data.resize(1024, 0)

        @parameter
        def process(i: Int):
            data[i] = i * i

        pool.run[process](1024)
        print(data[42])  # 1764
    """
    var n_workers: Int

    def __init__(out self, n_workers: Int = 0):
        var w = n_workers if n_workers > 0 else num_physical_cores()
        if w <= 0:
            w = 1   # guard against num_physical_cores() returning 0 (containers, CI)
        if w > MAX_WORKERS:
            w = MAX_WORKERS
        self.n_workers = w

    def run[dispatch: def(Int) capturing -> None](
        mut self, n_tasks: Int
    ):
        """
        Distribute n_tasks across workers.
        dispatch(task_id) is called exactly once per task_id in [0, n_tasks).
        Order of execution is non-deterministic.
        """
        if n_tasks <= 0:
            return
        var next = Atomic[DType.int64](0)
        var n    = n_tasks
        var w    = self.n_workers

        # Each worker grabs CHUNK tasks per atomic — reduces atomic traffic 64×
        # vs one-at-a-time, cutting cache-coherency overhead under high thread counts.
        @parameter
        def worker(tid: Int):
            comptime CHUNK = 64
            while True:
                var start = Int(next.fetch_add(CHUNK))
                if start >= n:
                    break
                var stop = start + CHUNK
                if stop > n:
                    stop = n
                for i in range(start, stop):
                    dispatch(i)

        parallelize[worker](w, w)

    def run_range[dispatch: def(Int) capturing -> None](
        mut self, start: Int, stop: Int
    ):
        """
        Distribute tasks [start, stop) across workers.
        dispatch(i) called for each i in [start, stop).
        """
        if stop <= start:
            return
        var n    = stop - start
        var next = Atomic[DType.int64](0)
        var w    = self.n_workers

        @parameter
        def worker(tid: Int):
            comptime CHUNK = 64
            while True:
                var base = Int(next.fetch_add(CHUNK))
                if base >= n:
                    break
                var end = base + CHUNK
                if end > n:
                    end = n
                for i in range(base, end):
                    dispatch(start + i)

        parallelize[worker](w, w)


# ---------------------------------------------------------------------------
# TaskGraph  — dependency-aware parallel DAG executor
# ---------------------------------------------------------------------------

comptime MAX_GRAPH_JOBS: Int = 65536


struct TaskGraph:
    """
    Directed acyclic graph (DAG) of integer-keyed jobs with dependencies.

    Phase 1 — Build:
        var g = TaskGraph()
        var a = g.add_job()           # returns job ID
        var b = g.add_job()
        var c = g.add_job()
        g.add_dep(c, a)               # c depends on a
        g.add_dep(c, b)               # c depends on b

    Phase 2 — Execute:
        g.execute[dispatch](pool)     # dispatch(job_id) called for each job

    dispatch() may read from / write to any external state captured by the
    @parameter closure. Jobs within the same topological level are guaranteed
    to be independent by the DAG structure; it is the caller's responsibility
    to ensure that dispatch() for different jobs in the same level does not
    create data races.

    A sealed graph can be executed multiple times (e.g. with different captured
    data) by calling execute() again. The graph structure cannot be modified
    after seal().
    """

    # Build-time data
    var _n_jobs:    Int
    var _dep_from:  List[List[Int]]  # _dep_from[j] = jobs that j waits for
    var _sealed:    Bool

    # Computed by seal()
    var _levels_flat:  List[Int]   # job IDs in topological order
    var _level_starts: List[Int]   # _levels_flat index where each level starts
    var _level_sizes:  List[Int]   # number of jobs per level


    def __init__(out self):
        self._n_jobs    = 0
        self._dep_from  = List[List[Int]]()
        self._sealed    = False
        self._levels_flat  = List[Int]()
        self._level_starts = List[Int]()
        self._level_sizes  = List[Int]()

    # -----------------------------------------------------------------------
    # Build API

    def add_job(mut self) raises -> Int:
        """
        Add a job with no dependencies.
        Returns the job's integer ID (0-based, monotonically increasing).
        Raises if the graph is already sealed.
        """
        if self._sealed:
            raise Error("TaskGraph: cannot add jobs after seal()")
        if self._n_jobs >= MAX_GRAPH_JOBS:
            raise Error(
                "TaskGraph: max " + String(MAX_GRAPH_JOBS) + " jobs exceeded"
            )
        var id = self._n_jobs
        self._n_jobs += 1
        self._dep_from.append(List[Int]())
        return id

    def add_dep(mut self, job: Int, depends_on: Int) raises:
        """
        Declare that `job` must not start until `depends_on` has finished.
        Both IDs must have been returned by add_job().
        Duplicate edges are silently ignored.
        Cyclic dependencies are detected by seal() / execute().
        """
        if self._sealed:
            raise Error("TaskGraph: cannot add deps after seal()")
        self._check_id(job,        "job")
        self._check_id(depends_on, "depends_on")
        if job == depends_on:
            raise Error(
                "TaskGraph: job " + String(job) + " cannot depend on itself"
            )
        # Guard against duplicate edges (would corrupt in-degree computation)
        for d in range(len(self._dep_from[job])):
            if self._dep_from[job][d] == depends_on:
                return   # already recorded
        self._dep_from[job].append(depends_on)

    # -----------------------------------------------------------------------
    # Seal (topological sort)

    def seal(mut self) raises:
        """
        Compute topological execution order using Kahn's algorithm.
        Raises if the dependency graph contains a cycle.
        Must be called before execute(), or execute() calls it automatically.
        """
        if self._sealed:
            return

        var n = self._n_jobs
        if n == 0:
            self._sealed = True
            return

        # Build reverse-adjacency: dependents[i] = list of jobs that wait for i
        # This converts the O(n²) scan to O(n + edges) — one pass over all edges.
        var dependents = List[List[Int]]()
        var in_deg     = List[Int](capacity=n)
        in_deg.resize(n, 0)
        for _ in range(n):
            dependents.append(List[Int]())

        for job in range(n):
            for d in range(len(self._dep_from[job])):
                var dep = self._dep_from[job][d]
                dependents[dep].append(job)
            in_deg[job] = len(self._dep_from[job])

        # Kahn's BFS — O(n + edges)
        var q = List[Int]()
        for i in range(n):
            if in_deg[i] == 0:
                q.append(i)

        var levels_flat  = List[Int]()
        var level_starts = List[Int]()
        var level_sizes  = List[Int]()
        var processed    = 0

        while len(q) > 0:
            level_starts.append(len(levels_flat))
            level_sizes.append(len(q))

            var next_q = List[Int]()

            for qi in range(len(q)):
                var job = q[qi]
                levels_flat.append(job)
                processed += 1

                for d in range(len(dependents[job])):
                    var downstream = dependents[job][d]
                    in_deg[downstream] -= 1
                    if in_deg[downstream] == 0:
                        next_q.append(downstream)

            q = next_q^

        if processed != n:
            # Cycle detected — leave _sealed = False so the error propagates
            # to execute() as well, rather than silently running 0 jobs.
            raise Error(
                "TaskGraph: dependency cycle detected ("
                + String(n - processed) + " jobs unreachable)"
            )

        # Only commit the results if the full graph was processed cleanly.
        self._levels_flat  = levels_flat^
        self._level_starts = level_starts^
        self._level_sizes  = level_sizes^
        self._sealed = True

    # -----------------------------------------------------------------------
    # Execute

    def execute[dispatch: def(Int) capturing -> None](
        mut self,
        pool: ThreadPool
    ) raises:
        """
        Run all jobs respecting dependency order.
        dispatch(job_id) is called exactly once per job, from a worker thread.
        The same pool can be reused across multiple execute() calls.
        """
        if not self._sealed:
            self.seal()

        var n_levels = len(self._level_starts)
        var workers  = pool.n_workers

        for li in range(n_levels):
            var start = self._level_starts[li]
            var sz    = self._level_sizes[li]
            var next  = Atomic[DType.int64](0)

            @parameter
            def run_level(tid: Int):
                while True:
                    var i = Int(next.fetch_add(1))
                    if i >= sz:
                        break
                    dispatch(self._levels_flat[start + i])

            parallelize[run_level](workers, workers)
            # parallelize returns only after all workers finish → implicit barrier

    def execute_serial[dispatch: def(Int) capturing -> None](
        mut self
    ) raises:
        """
        Single-threaded execution in dependency order. Useful for debugging.
        """
        if not self._sealed:
            self.seal()
        for i in range(len(self._levels_flat)):
            dispatch(self._levels_flat[i])

    # -----------------------------------------------------------------------
    # Introspection

    def n_jobs(self) -> Int:
        return self._n_jobs

    def n_levels(self) -> Int:
        return len(self._level_starts)

    def is_sealed(self) -> Bool:
        return self._sealed

    def level_size(self, level: Int) -> Int:
        if level < 0 or level >= len(self._level_sizes):
            return 0
        return self._level_sizes[level]

    def dump(self) -> String:
        return (
            "TaskGraph(jobs=" + String(self._n_jobs)
            + ", levels="     + String(len(self._level_starts))
            + ", sealed="     + String(self._sealed)
            + ")"
        )

    # -----------------------------------------------------------------------
    # Internal

    def _check_id(self, id: Int, name: String) raises:
        if id < 0 or id >= self._n_jobs:
            raise Error(
                "TaskGraph: " + name + " id " + String(id)
                + " out of range [0, " + String(self._n_jobs) + ")"
            )


# ---------------------------------------------------------------------------
# ReactiveGraph  — event-queue driven, barrier-free DAG execution
# ---------------------------------------------------------------------------

struct ReactiveGraph:
    """
    Dependency-based job graph with atomic in-degree tracking.

    API is identical to TaskGraph (add_job / add_dep / seal / execute), but the
    execution model is fundamentally different:

      TaskGraph     level 0 finishes → level 1 starts → … (implicit barriers)
      ReactiveGraph job J completes  → J's dependents are decremented immediately;
                    any dependent that reaches in_deg=0 is pushed to the ready
                    queue and picked up by the next idle worker

    This eliminates barrier stalls when jobs at the same level have unequal cost.

    Zero-copy: only UInt64 job IDs flow through the internal ready queue.
    Atomic:    done counter is Atomic[int64]; in-deg reads are TicketLock-protected.

    Not suitable for graphs with cycles (seal() will raise as with TaskGraph).
    Not re-executable with modified in-degrees (call seal() only once; execute()
    is idempotent across multiple calls — each call resets live_deg from sealed state).
    """
    var _n:       Int
    var _in_deg:  List[Int]         # initial in-degrees (frozen at seal)
    var _deps_of: List[List[Int]]   # deps_of[j] = jobs that decrement when j done
    var _dep_from: List[List[Int]]  # dep_from[j] = jobs j explicitly depends on
    var _sealed:  Bool

    def __init__(out self):
        self._n        = 0
        self._in_deg   = List[Int]()
        self._deps_of  = List[List[Int]]()
        self._dep_from = List[List[Int]]()
        self._sealed   = False

    def add_job(mut self) raises -> Int:
        if self._sealed:
            raise Error("ReactiveGraph: cannot add_job after seal()")
        var id = self._n
        self._n += 1
        self._dep_from.append(List[Int]())
        return id

    def add_dep(mut self, job: Int, depends_on: Int) raises:
        """Record that `job` must run after `depends_on` completes."""
        if self._sealed:
            raise Error("ReactiveGraph: cannot add_dep after seal()")
        self._check_id(job,        "add_dep(job)")
        self._check_id(depends_on, "add_dep(depends_on)")
        if job == depends_on:
            raise Error("ReactiveGraph: self-loop on job " + String(job))
        for d in range(len(self._dep_from[job])):
            if self._dep_from[job][d] == depends_on:
                return   # deduplicate
        self._dep_from[job].append(depends_on)

    def seal(mut self) raises:
        """
        Validate the DAG (cycle detection via Kahn's), build reverse-adjacency
        list (deps_of) and initial in-degrees. Raises on cycle.
        """
        if self._sealed:
            return
        var n = self._n
        if n == 0:
            self._sealed = True
            return

        # Build deps_of (reverse adjacency) + in_deg
        var deps_of = List[List[Int]]()
        var in_deg  = List[Int](capacity=n)
        in_deg.resize(n, 0)
        for _ in range(n):
            deps_of.append(List[Int]())

        for job in range(n):
            for d in range(len(self._dep_from[job])):
                var dep = self._dep_from[job][d]
                deps_of[dep].append(job)
            in_deg[job] = len(self._dep_from[job])

        # Kahn's BFS — purely for cycle validation
        var q = List[Int]()
        for i in range(n):
            if in_deg[i] == 0:
                q.append(i)

        var processed = 0
        var tmp_deg   = List[Int](capacity=n)
        tmp_deg.resize(n, 0)
        for i in range(n):
            tmp_deg[i] = in_deg[i]

        var front = 0
        while front < len(q):
            var job = q[front]
            front  += 1
            processed += 1
            for d in range(len(deps_of[job])):
                var dn = deps_of[job][d]
                tmp_deg[dn] -= 1
                if tmp_deg[dn] == 0:
                    q.append(dn)

        if processed != n:
            raise Error(
                "ReactiveGraph: cycle detected ("
                + String(n - processed) + " jobs unreachable)"
            )

        self._in_deg  = in_deg^
        self._deps_of = deps_of^
        self._sealed  = True

    def execute[dispatch: def(Int) capturing -> None](
        mut self, pool: ThreadPool
    ) raises:
        """
        Run all jobs respecting dependencies, without level barriers.
        dispatch(job_id) is called exactly once per job from a worker thread.
        Safe to call multiple times on the same sealed graph.
        """
        if not self._sealed:
            self.seal()
        var n = self._n
        if n == 0:
            return

        # Fresh per-run in-degree copy (live_deg is mutated during execution)
        var live_deg = List[Int](capacity=n)
        live_deg.resize(n, 0)
        for i in range(n):
            live_deg[i] = self._in_deg[i]

        # MPMC ready queue: SPSCQueue + TicketLock serialising all push/pop
        var cap = 1
        while cap < n + n + 4:
            cap = cap + cap
        var ready    = SPSCQueue(cap)
        var q_lock   = TicketLock()
        # Semaphore tracks items in the ready queue: one post per push,
        # one wait per pop, so workers sleep instead of spinning when empty.
        var work_sem = Semaphore(0)
        var done     = Atomic[DType.int64](0)
        var w        = pool.n_workers

        # Seed: push all zero-dep jobs; one semaphore signal per pushed item.
        var n_seed = 0
        for i in range(n):
            if live_deg[i] == 0:
                _ = ready.push(UInt64(i))
                n_seed += 1
        work_sem.post_many(n_seed)

        @parameter
        def worker(tid: Int):
            while True:
                work_sem.wait()          # sleep until an item (or exit token) arrives

                if Int(done.load()) >= n:
                    return               # all jobs done; termination token consumed

                q_lock.lock()
                var r = ready.pop()
                q_lock.unlock()

                if not r.ok:
                    # Defensive: semaphore count should equal queue depth,
                    # so this branch is unreachable in correct operation.
                    work_sem.post()
                    continue

                var jid = Int(r.value)
                dispatch(jid)            # ← real work, outside any lock
                var new_done = Int(done.fetch_add(1)) + 1

                # Notify dependents: decrement their in-deg; enqueue if ready.
                var n_pushed = 0
                q_lock.lock()
                for idx in range(len(self._deps_of[jid])):
                    var dep = self._deps_of[jid][idx]
                    live_deg[dep] -= 1
                    if live_deg[dep] == 0:
                        _ = ready.push(UInt64(dep))
                        n_pushed += 1
                q_lock.unlock()

                if n_pushed > 0:
                    work_sem.post_many(n_pushed)

                if new_done == n:
                    # Post one exit token per worker; each sleeping or
                    # soon-to-sleep worker will consume one and return.
                    work_sem.post_many(w)
                    return

        parallelize[worker](w, w)

        if DEBUG:
            var final_done = Int(done.load())
            if final_done != n:
                print("[ASHEN] ReactiveGraph.execute: only " + String(final_done)
                    + "/" + String(n) + " jobs completed — possible race or cycle"
                    + " | " + self.dump())
                dbg_assert(False, "ReactiveGraph.execute: job count mismatch")

    def n_jobs(self) -> Int:
        return self._n

    def is_sealed(self) -> Bool:
        return self._sealed

    def dump(self) -> String:
        return (
            "ReactiveGraph(jobs=" + String(self._n)
            + ", sealed=" + String(self._sealed) + ")"
        )

    def _check_id(self, id: Int, name: String) raises:
        if id < 0 or id >= self._n:
            raise Error(
                "ReactiveGraph: " + name + " id " + String(id)
                + " out of range [0, " + String(self._n) + ")"
            )


# ---------------------------------------------------------------------------
# Convenience: parallel_for
# ---------------------------------------------------------------------------

def parallel_for[body: def(Int) capturing -> None](
    n: Int, n_workers: Int = 0
):
    """
    Run body(i) for i in [0, n) in parallel using n_workers threads.
    Shorthand for: ThreadPool(n_workers).run[body](n)
    """
    var pool = ThreadPool(n_workers)
    pool.run[body](n)


def parallel_for_range[body: def(Int) capturing -> None](
    start: Int, stop: Int, n_workers: Int = 0
):
    """
    Run body(i) for i in [start, stop) in parallel.
    """
    if stop <= start:
        return
    var n    = stop - start
    var next = Atomic[DType.int64](0)
    var w    = ThreadPool(n_workers).n_workers

    @parameter
    def worker(tid: Int):
        while True:
            var i = Int(next.fetch_add(1))
            if i >= n:
                break
            body(start + i)

    parallelize[worker](w, w)
