"""
Benchmark sweep: parallel float32 + bf16 reduction at multiple N values.

Shows how throughput changes as N grows past L3 cache into DRAM bandwidth territory.

  N=10M   float32=40MB  bf16=20MB  (L3 cache, likely)
  N=50M   float32=200MB bf16=100MB (DRAM, bandwidth-bound)
  N=100M  float32=400MB bf16=200MB (DRAM, clear bandwidth limit)
  N=500M  float32=2GB   bf16=1GB   (extreme — needs 3GB free RAM)

Output (one row per N):
  sweep_f32_ns_<N>=<ns>
  sweep_bf16_ns_<N>=<ns>

For 1B test (4GB RAM needed): set N=1_000_000_000 and run bench_reduce_fp.mojo directly.
"""
from std.algorithm import parallelize
from std.sys       import num_physical_cores
from std.time      import perf_counter_ns


def run_f32(N: Int, W: Int) -> UInt:
    var data = List[Float32](capacity=N)
    data.resize(N, Float32(0))
    for i in range(N):
        data[i] = Float32(i % 1000)
    var dp = data.unsafe_ptr()

    comptime STRIDE: Int = 16
    var pp = List[Float32](capacity=W * STRIDE)
    pp.resize(W * STRIDE, Float32(0))
    var pf = pp.unsafe_ptr()

    var t0 = perf_counter_ns()

    @parameter
    def reduce_f32(tid: Int):
        var chunk = N // W
        var start = tid * chunk
        var stop  = start + chunk
        if tid == W - 1:
            stop = N
        comptime LANES: Int = 16
        var vacc = SIMD[DType.float32, LANES](0)
        var i = start
        while i + LANES <= stop:
            vacc += dp.load[width=LANES](i)
            i    += LANES
        var acc = vacc.reduce_add()
        while i < stop:
            acc += dp[i]; i += 1
        pf[tid * STRIDE] = acc

    parallelize[reduce_f32](W, W)
    var total = Float32(0)
    for t in range(W):
        total += pf[t * STRIDE]
    var ns = perf_counter_ns() - t0
    _ = total; _ = dp; _ = pf
    return ns


def run_bf16(N: Int, W: Int) -> UInt:
    var data = List[BFloat16](capacity=N)
    data.resize(N, BFloat16(0))
    for i in range(N):
        data[i] = Float32(i % 1000).cast[DType.bfloat16]()
    var dp = data.unsafe_ptr()

    comptime STRIDE: Int = 32
    var pp = List[Float32](capacity=W * STRIDE)
    pp.resize(W * STRIDE, Float32(0))
    var pf = pp.unsafe_ptr()

    var t0 = perf_counter_ns()

    @parameter
    def reduce_bf16(tid: Int):
        var chunk = N // W
        var start = tid * chunk
        var stop  = start + chunk
        if tid == W - 1:
            stop = N
        comptime LANES: Int = 8
        var vacc = SIMD[DType.float32, LANES](0)
        var i = start
        while i + LANES <= stop:
            vacc += dp.load[width=LANES](i).cast[DType.float32]()
            i    += LANES
        var acc = vacc.reduce_add()
        while i < stop:
            acc += dp[i].cast[DType.float32](); i += 1
        pf[tid * STRIDE] = acc

    parallelize[reduce_bf16](W, W)
    var total = Float32(0)
    for t in range(W):
        total += pf[t * STRIDE]
    var ns = perf_counter_ns() - t0
    _ = total; _ = dp; _ = pf
    return ns


def main() raises:
    var W = num_physical_cores()
    print("workers=" + String(W))

    var sizes = List[Int]()
    sizes.append(10_000_000)
    sizes.append(50_000_000)
    sizes.append(100_000_000)
    sizes.append(500_000_000)

    for si in range(len(sizes)):
        var N = sizes[si]
        var f32_mb = N * 4 // 1_000_000
        var bf16_mb = N * 2 // 1_000_000
        print("--- N=" + String(N) + " f32=" + String(f32_mb) + "MB bf16=" + String(bf16_mb) + "MB ---")
        var f32_ns  = run_f32(N, W)
        var bf16_ns = run_bf16(N, W)
        var f32_gbs  = Float32(Int(N) * 4) / Float32(Int(f32_ns))
        var bf16_gbs = Float32(Int(N) * 2) / Float32(Int(bf16_ns))
        print("sweep_f32_ns_"  + String(N) + "=" + String(f32_ns))
        print("sweep_bf16_ns_" + String(N) + "=" + String(bf16_ns))
        print("f32_ms="  + String(Float32(Int(f32_ns))  / Float32(1_000_000)))
        print("bf16_ms=" + String(Float32(Int(bf16_ns)) / Float32(1_000_000)))
        print("f32_GBs="  + String(f32_gbs))
        print("bf16_GBs=" + String(bf16_gbs))
