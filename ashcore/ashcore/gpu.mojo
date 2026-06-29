"""AshCore — GPU-compatible parallel execution (currently CPU-only).

GPU_AVAILABLE=False: all work runs via std.algorithm.parallelize.
Flip to True and implement the GPU branch when DeviceContext is stable.
"""

from std.atomic    import Atomic
from std.algorithm import parallelize
from std.sys       import num_physical_cores
from ashcore.debug import DEBUG, dbg_assert


comptime GPU_AVAILABLE: Bool = False


@always_inline
def gpu_parallel_for[body: def(Int) capturing -> None](n: Int):
    """Launch body(i) for i in [0, n).  CPU path now; GPU path when GPU_AVAILABLE=True."""
    if GPU_AVAILABLE:
        dbg_assert(False, "GPU_AVAILABLE=True but GPU launch not implemented yet")
    else:
        _cpu_parallel_for[body](n)


@always_inline
def _cpu_parallel_for[body: def(Int) capturing -> None](n: Int):
    """Work-sharing via atomic counter, CHUNK=64 tasks per fetch."""
    var W    = num_physical_cores()
    var next = Atomic[DType.int64](0)
    var n_r  = n

    @parameter
    def worker(_tid: Int):
        comptime CHUNK = 64
        while True:
            var start = Int(next.fetch_add(CHUNK))
            if start >= n_r:
                break
            var stop = start + CHUNK
            if stop > n_r:
                stop = n_r
            for i in range(start, stop):
                body(i)

    parallelize[worker](W, W)


def gpu_info() -> String:
    """Human-readable execution-mode string."""
    if GPU_AVAILABLE:
        return "parallel: GPU (DeviceContext)"
    return "parallel: CPU (std.algorithm.parallelize, CHUNK=64)"
