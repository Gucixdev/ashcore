"""AshCore — ReactiveGraph: barrier-free, event-queue-driven DAG execution."""

from std.atomic    import Atomic
from std.algorithm import parallelize
from ashcore.queue import SPSCQueue, PopResult
from ashcore.sync  import TicketLock, Semaphore
from ashcore.debug import DEBUG, dbg_assert
from ashcore.threadpool import ThreadPool


struct ReactiveGraph:
    """
    Dependency-based job graph with atomic in-degree tracking.

    API matches TaskGraph (add_job / add_dep / seal / execute), but execution
    is barrier-free: each job starts the moment its last dependency completes.
    This eliminates stalls when jobs at the same topological level have unequal
    cost.

    Zero-copy: only UInt64 job IDs flow through the internal ready queue.
    Atomic:    done counter is Atomic[int64]; in-degree protected by TicketLock.

    Not suitable for graphs with cycles (seal() raises).
    Each execute() call resets live_deg from the sealed state.
    """
    var _n:       Int
    var _in_deg:  List[Int]
    var _deps_of: List[List[Int]]
    var _dep_from: List[List[Int]]
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
                return
        self._dep_from[job].append(depends_on)

    def seal(mut self) raises:
        """Validate the DAG (cycle detection via Kahn's), build reverse-adjacency."""
        if self._sealed:
            return
        var n = self._n
        if n == 0:
            self._sealed = True
            return

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
        dispatch(job_id) called exactly once per job from a worker thread.
        Safe to call multiple times on the same sealed graph.
        """
        if not self._sealed:
            self.seal()
        var n = self._n
        if n == 0:
            return

        var live_deg = List[Int](capacity=n)
        live_deg.resize(n, 0)
        for i in range(n):
            live_deg[i] = self._in_deg[i]

        var cap = 1
        while cap < n + n + 4:
            cap = cap + cap
        var ready    = SPSCQueue(cap)
        var q_lock   = TicketLock()
        var work_sem = Semaphore(0)
        var done     = Atomic[DType.int64](0)
        var w        = pool.n_workers

        var n_seed = 0
        for i in range(n):
            if live_deg[i] == 0:
                _ = ready.push(UInt64(i))
                n_seed += 1
        work_sem.post_many(n_seed)

        @parameter
        def worker(tid: Int):
            while True:
                work_sem.wait()

                if Int(done.load()) >= n:
                    return

                q_lock.lock()
                var r = ready.pop()
                q_lock.unlock()

                if not r.ok:
                    work_sem.post()
                    continue

                var jid = Int(r.value)
                dispatch(jid)
                var new_done = Int(done.fetch_add(1)) + 1

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
