"""
ashcore example: parallel SIMD reduction of 10M float32 values.

Each worker sums its slice independently (no shared state during computation).
Partials are padded to 64 B cache-line slots to avoid false sharing.
"""
from std.sys  import num_physical_cores
from std.time import perf_counter_ns
from ashcore.parallel import parallel_for

def main() raises:
    var N = 10_000_000
    var W = num_physical_cores()

    # Input: values 0.0, 0.001, 0.002, ... cycling every 1000
    var data = List[Int](capacity=N)
    data.resize(N, 0)
    for i in range(N):
        data[i] = i % 1000

    # Per-worker partial sums — 8×Int = 64 B per slot (no false sharing)
    comptime STRIDE: Int = 8
    var partials = List[Int](capacity=W * STRIDE)
    partials.resize(W * STRIDE, 0)

    var dp = data.unsafe_ptr()
    var pp = partials.unsafe_ptr()

    var t0 = perf_counter_ns()

    @parameter
    def reduce_slice(tid: Int):
        var chunk = N // W
        var start = tid * chunk
        var stop  = start + chunk
        if tid == W - 1:
            stop = N
        var acc = Int(0)
        for i in range(start, stop):
            acc += dp[i]
        pp[tid * STRIDE] = acc

    parallel_for[reduce_slice](W)
    _ = dp  # keep dp alive past the closure (prevents DCE)

    var total = Int(0)
    for t in range(W):
        total += pp[t * STRIDE]

    var ms = Float32(perf_counter_ns() - t0) / Float32(1_000_000)

    # expected: sum of 0..999 cycling N/1000 times = 10000 * 999*1000/2 = 4_995_000_000
    var expected = (N // 1000) * 999 * 1000 // 2
    print("N        = " + String(N))
    print("workers  = " + String(W))
    print("result   = " + String(total))
    print("expected = " + String(expected))
    print("match    = " + String(total == expected))
    print("time     = " + String(ms) + " ms")
