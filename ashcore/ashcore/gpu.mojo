"""AshCore — GPU-accelerated parallel execution with CPU fallback.

GPU path (DeviceContext-based) is currently disabled: this build's `max`
package does not provide the `runtime.asyncrt` module (no GPU runtime
available in this environment), so it cannot be imported at all - Mojo
resolves imports at compile time, not conditionally at runtime, so no
try/except can guard against a genuinely absent module. has_gpu(),
gpu_map_f64(), and gpu_abs_diffs() keep their original signatures and
always take the CPU path below until a MAX distribution with GPU/runtime
support is available.
"""

from std.atomic    import Atomic
from std.algorithm import parallelize
from std.sys       import num_physical_cores
from memory        import UnsafePointer


# ── GPU availability ──────────────────────────────────────────────────────────

def has_gpu() -> Bool:
    """True iff a GPU DeviceContext can be created. Always False in this
    build (runtime.asyncrt is unavailable — see module docstring)."""
    return False


def gpu_info() -> String:
    """Human-readable execution-mode string."""
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


# ── GPU map / reduce helpers ──────────────────────────────────────────────────
#
# The DeviceContext-based kernels these used to dispatch to are removed for
# now (see module docstring) — both functions always take the CPU path below.

def gpu_map_f64(
    prices: List[Float64],
    period: Int,
) -> List[Float64]:
    """SMA over a Float64 price list. CPU-only in this build."""
    return _cpu_sma(prices, period)


def gpu_abs_diffs(prices: List[Float64]) -> List[Float64]:
    """Absolute bar-to-bar changes. CPU-only in this build."""
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
