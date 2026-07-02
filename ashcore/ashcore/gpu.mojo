"""AshCore — GPU-accelerated parallel execution with CPU fallback.

GPU path uses Mojo's DeviceContext (stable since MAX 26.x / Mojo 1.0.0b2):

  DeviceContext()                             — acquire GPU device
  ctx.enqueue_create_buffer[dtype](n)         — allocate device memory
  ctx.enqueue_create_host_buffer[dtype](n)    — allocate pinned host memory
  ctx.enqueue_copy(dst, src)                  — H→D or D→H transfer
  ctx.enqueue_function[kernel](args,          — launch GPU kernel
      grid_dim=blocks, block_dim=threads)
  ctx.synchronize()                           — wait for completion

  Inside a GPU kernel:
    thread_idx.x, block_idx.x, block_dim.x   — thread addressing

NOTE: gpu_parallel_for stays CPU-only by design. GPU kernels require fixed,
concrete function signatures and cannot capture arbitrary closures. Use the
typed GPU operations (gpu_map_f64, gpu_abs_diffs) for GPU-accelerated work.
"""

from std.atomic      import Atomic
from std.algorithm   import parallelize
from std.sys         import num_physical_cores
from memory          import UnsafePointer
from runtime.asyncrt import DeviceContext


# ── GPU availability ──────────────────────────────────────────────────────────

def has_gpu() -> Bool:
    """Runtime check — True iff a GPU DeviceContext can be created."""
    try:
        _ = DeviceContext()
        return True
    except:
        return False


def gpu_info() -> String:
    """Human-readable execution-mode string."""
    if has_gpu():
        return "parallel: GPU (DeviceContext)"
    return "parallel: CPU (std.algorithm.parallelize, CHUNK=64)"


# ── CPU parallel_for (unchanged) ──────────────────────────────────────────────

@always_inline
def gpu_parallel_for[body: def(Int) capturing -> None](n: Int):
    """Launch body(i) for i in [0, n) on CPU worker pool.

    GPU path intentionally omitted: GPU kernels require fixed concrete
    signatures and cannot capture arbitrary closures. Use gpu_map_f64 or
    gpu_abs_diffs for GPU-accelerated bulk Float64 operations.
    """
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
            if start >= n_r: break
            var stop = start + CHUNK
            if stop > n_r: stop = n_r
            for i in range(start, stop):
                body(i)

    parallelize[worker](W, W)


# ── GPU kernels ───────────────────────────────────────────────────────────────

alias GPU_BLOCK_SIZE = 256


def _gpu_sma_kernel(
    prices: UnsafePointer[Float64],
    output: UnsafePointer[Float64],
    n:      UInt,
    period: UInt,
):
    """GPU kernel: compute one SMA output value per thread.

    Each thread i computes output[i] = mean(prices[i : i+period]).
    Launched with grid_dim = ceil(out_n / GPU_BLOCK_SIZE).
    """
    from gpu import thread_idx, block_idx, block_dim
    var tid  = block_idx.x * block_dim.x + thread_idx.x
    var out_n = n - period + 1
    if tid >= out_n: return
    var s = Float64(0)
    for j in range(period):
        s += prices[tid + j]
    output[tid] = s / Float64(period)


def _gpu_abs_diff_kernel(
    prices: UnsafePointer[Float64],
    diffs:  UnsafePointer[Float64],
    n:      UInt,
):
    """GPU kernel: compute absolute bar-to-bar change per thread.

    Thread i computes diffs[i] = |prices[i+1] - prices[i]|.
    """
    from gpu import thread_idx, block_idx, block_dim
    var tid = block_idx.x * block_dim.x + thread_idx.x
    if tid >= n - 1: return
    var d = prices[tid + 1] - prices[tid]
    diffs[tid] = d if d >= Float64(0) else -d


# ── GPU map / reduce helpers ──────────────────────────────────────────────────

def gpu_map_f64(
    prices: List[Float64],
    period: Int,
) -> List[Float64]:
    """GPU-accelerated SMA over a Float64 price list.

    Falls back to CPU loop if no GPU is available at runtime.
    """
    var n = len(prices)
    if n < period or period <= 0:
        return List[Float64]()

    try:
        var ctx   = DeviceContext()
        var out_n = n - period + 1

        # Pinned host input buffer
        var h_in = ctx.enqueue_create_host_buffer[DType.float64](n)
        var h_in_ptr = h_in.unsafe_ptr()
        for i in range(n):
            h_in_ptr[i] = prices[i]

        # Device buffers
        var d_in  = ctx.enqueue_create_buffer[DType.float64](n)
        var d_out = ctx.enqueue_create_buffer[DType.float64](out_n)

        # H→D transfer
        ctx.enqueue_copy(d_in, h_in)

        # Launch SMA kernel
        var blocks = (out_n + GPU_BLOCK_SIZE - 1) // GPU_BLOCK_SIZE
        ctx.enqueue_function[_gpu_sma_kernel](
            d_in.unsafe_ptr(), d_out.unsafe_ptr(),
            UInt(n), UInt(period),
            grid_dim=blocks, block_dim=GPU_BLOCK_SIZE,
        )

        # D→H transfer
        var h_out = ctx.enqueue_create_host_buffer[DType.float64](out_n)
        ctx.enqueue_copy(h_out, d_out)
        ctx.synchronize()

        var result = List[Float64]()
        var h_out_ptr = h_out.unsafe_ptr()
        for i in range(out_n):
            result.append(h_out_ptr[i])
        return result^

    except:
        # CPU fallback
        return _cpu_sma(prices, period)


def gpu_abs_diffs(prices: List[Float64]) -> List[Float64]:
    """GPU-accelerated absolute bar-to-bar changes.

    Falls back to CPU loop if no GPU is available at runtime.
    """
    var n = len(prices)
    if n < 2:
        return List[Float64]()

    try:
        var ctx = DeviceContext()
        var m   = n - 1

        var h_in = ctx.enqueue_create_host_buffer[DType.float64](n)
        var h_in_ptr = h_in.unsafe_ptr()
        for i in range(n):
            h_in_ptr[i] = prices[i]

        var d_in   = ctx.enqueue_create_buffer[DType.float64](n)
        var d_diff = ctx.enqueue_create_buffer[DType.float64](m)

        ctx.enqueue_copy(d_in, h_in)

        var blocks = (m + GPU_BLOCK_SIZE - 1) // GPU_BLOCK_SIZE
        ctx.enqueue_function[_gpu_abs_diff_kernel](
            d_in.unsafe_ptr(), d_diff.unsafe_ptr(), UInt(n),
            grid_dim=blocks, block_dim=GPU_BLOCK_SIZE,
        )

        var h_diff = ctx.enqueue_create_host_buffer[DType.float64](m)
        ctx.enqueue_copy(h_diff, d_diff)
        ctx.synchronize()

        var result = List[Float64]()
        var h_ptr  = h_diff.unsafe_ptr()
        for i in range(m):
            result.append(h_ptr[i])
        return result^

    except:
        return _cpu_abs_diffs(prices)


# ── CPU fallbacks ─────────────────────────────────────────────────────────────

def _cpu_sma(prices: List[Float64], period: Int) -> List[Float64]:
    var result = List[Float64]()
    var n = len(prices)
    if period <= 0 or period > n: return result^
    for i in range(period - 1, n):
        var s = Float64(0)
        for j in range(period): s += prices[i - period + 1 + j]
        result.append(s / Float64(period))
    return result^


def _cpu_abs_diffs(prices: List[Float64]) -> List[Float64]:
    var result = List[Float64]()
    for i in range(1, len(prices)):
        var d = prices[i] - prices[i-1]
        result.append(d if d >= Float64(0) else -d)
    return result^
