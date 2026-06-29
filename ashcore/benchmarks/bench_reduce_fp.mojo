"""
Benchmark: Parallel reduction — float32, bfloat16, GPU (50M values each).

50M × 4B (f32) = 200MB, 50M × 2B (bf16) = 100MB — both exceed L3 cache,
so this measures real DRAM bandwidth rather than L3 cache speed.

Separate from bench_reduce.mojo due to Mojo 1.0.0b2 compiler crash when
combining Int64 SIMD closures with float SIMD closures in the same function.

Output (key=value):
    workers=<thread count>
    n=<element count>
    reduce_f32_ns=<wall time ns>
    reduce_bf16_ns=<wall time ns>
    reduce_gpu_ns=<-1 if GPU unavailable>
"""
from std.algorithm import parallelize
from std.sys       import num_physical_cores
from std.time      import perf_counter_ns

def main() raises:
    var N = 50_000_000
    var W = num_physical_cores()

    print("workers=" + String(W))
    print("n="       + String(N))

    # ── Float32 parallel reduction ─────────────────────────────────────────────
    var data_f32 = List[Float32](capacity=N)
    data_f32.resize(N, Float32(0))
    for i in range(N):
        data_f32[i] = Float32(i)
    var dp_f32 = data_f32.unsafe_ptr()

    comptime STRIDE_F32: Int = 16    # 16×4B = 64B cache-line per partial slot
    var pp_f32 = List[Float32](capacity=W * STRIDE_F32)
    pp_f32.resize(W * STRIDE_F32, Float32(0))
    var pf = pp_f32.unsafe_ptr()

    var t_f32 = perf_counter_ns()

    @parameter
    def reduce_f32(tid: Int):
        var chunk = N // W
        var start = tid * chunk
        var stop  = start + chunk
        if tid == W - 1:
            stop = N
        comptime LANES_F32: Int = 16
        var vacc = SIMD[DType.float32, LANES_F32](0)
        var i = start
        while i + LANES_F32 <= stop:
            vacc += dp_f32.load[width=LANES_F32](i)
            i    += LANES_F32
        var acc = vacc.reduce_add()
        while i < stop:
            acc += dp_f32[i]
            i   += 1
        pf[tid * STRIDE_F32] = acc

    parallelize[reduce_f32](W, W)
    var total_f32 = Float32(0)
    for t in range(W):
        total_f32 += pf[t * STRIDE_F32]
    var f32_ns = perf_counter_ns() - t_f32
    _ = total_f32

    # ── BFloat16 parallel reduction (widen to float32 before accumulate) ───────
    # bf16 has 8-bit mantissa — direct sum of 1M values would saturate; widen first.
    var data_bf16 = List[BFloat16](capacity=N)
    data_bf16.resize(N, BFloat16(0))
    for i in range(N):
        data_bf16[i] = Float32(i).cast[DType.bfloat16]()
    var dp_bf16 = data_bf16.unsafe_ptr()

    comptime STRIDE_BF16: Int = 32   # 32×2B = 64B cache-line per partial slot
    var pp_bf = List[Float32](capacity=W * STRIDE_BF16)
    pp_bf.resize(W * STRIDE_BF16, Float32(0))
    var pb = pp_bf.unsafe_ptr()

    var t_bf16 = perf_counter_ns()

    @parameter
    def reduce_bf16(tid: Int):
        var chunk = N // W
        var start = tid * chunk
        var stop  = start + chunk
        if tid == W - 1:
            stop = N
        # LANES=8: load 8 BFloat16 (16B = XMM), cast to 8×Float32 (32B = YMM).
        comptime LANES_BF16: Int = 8
        var vacc = SIMD[DType.float32, LANES_BF16](0)
        var i = start
        while i + LANES_BF16 <= stop:
            vacc += dp_bf16.load[width=LANES_BF16](i).cast[DType.float32]()
            i    += LANES_BF16
        var acc = vacc.reduce_add()
        while i < stop:
            acc += dp_bf16[i].cast[DType.float32]()
            i   += 1
        pb[tid * STRIDE_BF16] = acc

    parallelize[reduce_bf16](W, W)
    var total_bf16 = Float32(0)
    for t in range(W):
        total_bf16 += pb[t * STRIDE_BF16]
    var bf16_ns = perf_counter_ns() - t_bf16
    _ = total_bf16

    print("reduce_f32_ns="  + String(f32_ns))
    print("reduce_bf16_ns=" + String(bf16_ns))
    print("reduce_gpu_ns=-1")  # GPU disabled — Mojo 1.0.0b2 crash with gpu import + SIMD closures
