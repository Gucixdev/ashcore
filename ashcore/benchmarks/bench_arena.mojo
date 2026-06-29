"""
Benchmark: Arena allocator — 1M x 64B sequential allocs + O(1) reset.
"""
from ashcore.arena import Arena
from std.time import perf_counter_ns

def main() raises:
    var N     = 1000000
    var arena = Arena(N * 64 + 65536)

    for _ in range(1000):
        var _ = arena.alloc(64)
    arena.reset()

    # Track used bytes before and verify monotonic growth
    var t0 = perf_counter_ns()
    for _ in range(N):
        var _ = arena.alloc(64)
    var t1 = perf_counter_ns()
    var used_after = arena.used()
    arena.reset()
    var t2 = perf_counter_ns()
    var used_after_reset = arena.used()

    # Correctness: used() must be >= N*64 after allocs (alignment may add padding),
    # and exactly 0 after reset.
    var correct = (used_after >= N * 64) and (used_after_reset == 0)

    print("alloc_total_ns=" + String(t1 - t0))
    print("reset_ns="       + String(t2 - t1))
    print("per_op_ns="      + String(UInt((t1 - t0) // N)))
    print("n="              + String(N))
    print("correct="        + String(correct))
