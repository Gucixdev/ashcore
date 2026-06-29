"""
Benchmark: Parallel reduction — sum 10M Int64 values.

Each worker computes a partial sum over its slice (no shared state).
Tree-merge of partials on the main thread.

10M × 8B = 80MB — exceeds typical L3 cache, so this measures real DRAM bandwidth.

Output (key=value):
    reduce_ns=<wall time ns>
    workers=<thread count>
    n=<element count>
    result=<final sum>
    expected=<N*(N-1)/2>
    correct=<True/False>
    per_elem_ps=<ps per element>
"""
from std.algorithm import parallelize
from std.sys       import num_physical_cores
from std.time      import perf_counter_ns

def main() raises:
    var N = 10_000_000
    var W = num_physical_cores()

    # Input: 0..N-1
    var data = List[Int64](capacity=N)
    data.resize(N, Int64(0))
    for i in range(N):
        data[i] = Int64(i)

    # Per-worker partials — padded to 64B per slot to avoid false sharing.
    # Without padding: all W slots fit on one cache line → every write bounces
    # the cache line between cores. With STRIDE=8: each slot is 8×Int64=64B.
    comptime STRIDE: Int = 8
    var partials = List[Int64](capacity=W * STRIDE)
    partials.resize(W * STRIDE, Int64(0))

    var dp = data.unsafe_ptr()
    var pp = partials.unsafe_ptr()

    # Warmup: one full pass to warm caches + single-thread scalar baseline
    var warm_sum = Int64(0)
    for i in range(N):
        warm_sum += dp[i]
    _ = warm_sum

    # Single-thread scalar baseline — result printed to prevent dead-code elimination
    var t_scalar0 = perf_counter_ns()
    var scalar_sum = Int64(0)
    for i in range(N):
        scalar_sum += dp[i]
    var scalar_ns = perf_counter_ns() - t_scalar0

    # Single-thread SIMD baseline — 8×Int64 per iteration
    var t_simd0 = perf_counter_ns()
    comptime LANES_ST: Int = 8
    var vacc_st = SIMD[DType.int64, LANES_ST](0)
    var ii = 0
    while ii + LANES_ST <= N:
        vacc_st += dp.load[width=LANES_ST](ii)
        ii += LANES_ST
    var simd_sum = vacc_st.reduce_add()
    while ii < N:
        simd_sum += dp[ii]
        ii += 1
    var simd_ns = perf_counter_ns() - t_simd0

    var t0 = perf_counter_ns()

    @parameter
    def reduce_slice(tid: Int):
        var chunk = N // W
        var start = tid * chunk
        var stop  = start + chunk
        if tid == W - 1:
            stop = N

        # SIMD accumulator: 8 × Int64 per iteration (AVX2 YMM or AVX-512 ZMM).
        # Tail loop handles remaining elements when (stop-start) % LANES != 0.
        alias LANES = 8
        var vacc = SIMD[DType.int64, LANES](0)
        var i    = start
        while i + LANES <= stop:
            vacc += dp.load[width=LANES](i)
            i    += LANES
        var acc = vacc.reduce_add()
        while i < stop:
            acc += dp[i]
            i   += 1

        pp[tid * STRIDE] = acc   # stride-padded write to avoid cache-line bounce

    parallelize[reduce_slice](W, W)

    # Tree merge
    var total = Int64(0)
    for t in range(W):
        total += pp[t * STRIDE]

    var t1 = perf_counter_ns()
    var ns = t1 - t0

    var expected = Int64(N) * Int64(N - 1) // Int64(2)

    var correct = (total == expected) and (scalar_sum == expected) and (simd_sum == expected)
    print("reduce_ns="    + String(ns))
    print("scalar_ns="   + String(scalar_ns))
    print("simd_ns="     + String(simd_ns))
    print("workers="     + String(W))
    print("n="           + String(N))
    print("result="      + String(total))
    print("expected="    + String(expected))
    print("correct="     + String(correct))
    print("per_elem_ps=" + String((ns * 1000) // N))
