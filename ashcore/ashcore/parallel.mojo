"""AshCore — parallel_for / parallel_for_range convenience wrappers."""

from std.atomic    import Atomic
from std.algorithm import parallelize
from ashcore.threadpool import ThreadPool


def parallel_for[body: def(Int) capturing -> None](
    n: Int, n_workers: Int = 0
):
    """Run body(i) for i in [0, n) in parallel. Shorthand for ThreadPool(n_workers).run[body](n)."""
    var pool = ThreadPool(n_workers)
    pool.run[body](n)


def parallel_for_range[body: def(Int) capturing -> None](
    start: Int, stop: Int, n_workers: Int = 0
):
    """Run body(i) for i in [start, stop) in parallel."""
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
