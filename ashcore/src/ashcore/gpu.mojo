"""
AshCore - GPU acceleration layer

Status: CPU fallback mode.
The build environment has a GTX 1050 Ti (Pascal, sm_61 — supported by MAX 26.4),
but the NVIDIA driver/library version is mismatched, preventing CUDA initialisation
at compile time.

When CUDA is fixed, enable GPU mode:
  1. Resolve driver mismatch (reinstall nvidia-dkms matching kernel version)
  2. Set GPU_AVAILABLE = True below
  3. Replace _cpu_parallel_for with a DeviceContext kernel launch

Architecture support in MAX 26.4:
  NVIDIA: sm_52+  (Maxwell, Pascal, Turing, Ampere, Hopper, Blackwell)
  AMD:    gfx90a+ (MI250X, MI300X, MI355X, Radeon 6900+)
  Apple:  Metal M1–M4
  CPU:    always available (parallelize-based fallback)

API:
    GPU_AVAILABLE: Bool            — False until driver fixed
    gpu_parallel_for[f](n)         — runs body(i) for i in [0,n)
    gpu_info()                     — human-readable status string
"""

from std.atomic    import Atomic
from std.algorithm import parallelize
from std.sys       import num_physical_cores
from ashcore.debug import DEBUG, dbg_assert


comptime GPU_AVAILABLE: Bool = False


@always_inline
def gpu_parallel_for[body: def(Int) capturing -> None](n: Int):
    """
    Launch body(i) for i in [0, n) in parallel.

    GPU mode (future, GPU_AVAILABLE=True): DeviceContext kernel launch.
    CPU mode (current): std.algorithm.parallelize with CHUNK=64 batching.

    The GPU_AVAILABLE branch is compile-time — zero overhead in either mode.
    """
    if GPU_AVAILABLE:
        dbg_assert(False, "GPU_AVAILABLE=True but GPU launch not implemented yet")
    else:
        _cpu_parallel_for[body](n)


@always_inline
def _cpu_parallel_for[body: def(Int) capturing -> None](n: Int):
    """CPU fallback: work-sharing via atomic counter, CHUNK=64."""
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
    """Return a human-readable GPU status string."""
    if GPU_AVAILABLE:
        return "GPU: enabled (DeviceContext)"
    return (
        "GPU: disabled (CPU fallback via parallelize)\n"
        "  Hardware:  GTX 1050 Ti (Pascal, sm_61) — MAX 26.4 compatible\n"
        "  Blocker:   NVIDIA driver/library version mismatch\n"
        "  Fix:       reinstall nvidia-dkms to match kernel version"
    )
