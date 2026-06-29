"""AshCore — TaskGraph: static DAG executor with topological level barriers."""

from std.atomic    import Atomic
from std.algorithm import parallelize
from ashcore.debug import DEBUG, dbg_assert
from ashcore.threadpool import ThreadPool


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

    dispatch() may read/write any external state captured by the @parameter
    closure. Jobs within the same topological level are independent by DAG
    structure; the caller ensures no data races within a level.

    A sealed graph can be executed multiple times with different captured data.
    """

    var _n_jobs:    Int
    var _dep_from:  List[List[Int]]
    var _sealed:    Bool

    var _levels_flat:  List[Int]
    var _level_starts: List[Int]
    var _level_sizes:  List[Int]

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
        """Add a job with no dependencies. Returns the job's integer ID."""
        if self._sealed:
            raise Error("TaskGraph: cannot add jobs after seal()")
        if self._n_jobs >= MAX_GRAPH_JOBS:
            raise Error("TaskGraph: max " + String(MAX_GRAPH_JOBS) + " jobs exceeded")
        var id = self._n_jobs
        self._n_jobs += 1
        self._dep_from.append(List[Int]())
        return id

    def add_dep(mut self, job: Int, depends_on: Int) raises:
        """Declare that `job` must not start until `depends_on` has finished."""
        if self._sealed:
            raise Error("TaskGraph: cannot add deps after seal()")
        self._check_id(job,        "job")
        self._check_id(depends_on, "depends_on")
        if job == depends_on:
            raise Error("TaskGraph: job " + String(job) + " cannot depend on itself")
        for d in range(len(self._dep_from[job])):
            if self._dep_from[job][d] == depends_on:
                return
        self._dep_from[job].append(depends_on)

    # -----------------------------------------------------------------------
    # Seal (topological sort via Kahn's algorithm)

    def seal(mut self) raises:
        """Compute topological execution order. Raises if the graph has a cycle."""
        if self._sealed:
            return
        var n = self._n_jobs
        if n == 0:
            self._sealed = True
            return

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
            raise Error(
                "TaskGraph: dependency cycle detected ("
                + String(n - processed) + " jobs unreachable)"
            )

        self._levels_flat  = levels_flat^
        self._level_starts = level_starts^
        self._level_sizes  = level_sizes^
        self._sealed = True

    # -----------------------------------------------------------------------
    # Execute

    def execute[dispatch: def(Int) capturing -> None](
        mut self, pool: ThreadPool
    ) raises:
        """Run all jobs respecting dependency order. dispatch(job_id) called once per job."""
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

    def execute_serial[dispatch: def(Int) capturing -> None](
        mut self
    ) raises:
        """Single-threaded execution in dependency order. Useful for debugging."""
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
            + ", sealed="     + String(self._sealed) + ")"
        )

    def _check_id(self, id: Int, name: String) raises:
        if id < 0 or id >= self._n_jobs:
            raise Error(
                "TaskGraph: " + name + " id " + String(id)
                + " out of range [0, " + String(self._n_jobs) + ")"
            )
