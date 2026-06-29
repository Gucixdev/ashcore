"""AshCore — ThreadPool: fixed worker count, work-sharing via atomic counter."""

from std.atomic    import Atomic
from std.algorithm import parallelize
from std.sys       import num_physical_cores
from ashcore.debug import DEBUG, dbg_assert


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
