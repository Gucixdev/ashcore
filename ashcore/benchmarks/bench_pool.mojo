"""
Benchmark: ThreadPool — parallel computation over 1M items.
Each task computes i*i mod 1e9+7 stored as Int32 — matching C's int[] layout
so the memory footprint (4MB vs 8MB) is a fair comparison.
"""
from ashcore.jobs import ThreadPool
from std.time import perf_counter_ns

def main() raises:
    var N    = 1000000
    var pool = ThreadPool()

    var buf = List[Int32](capacity=N)
    buf.resize(N, Int32(0))
    var ptr = buf.unsafe_ptr()

    @parameter
    def warmup(i: Int):
        ptr[i] = Int32(i & 1)
    pool.run[warmup](10000)

    @parameter
    def work(i: Int):
        ptr[i] = Int32((i * i) % 1000000007)

    var t0 = perf_counter_ns()
    pool.run[work](N)
    var t1 = perf_counter_ns()

    var chk: Int = 0
    for i in range(N):
        chk = (chk + Int(ptr[i])) % 1000000007

    # Verify: recompute expected checksum sequentially (ground truth)
    var expected: Int = 0
    for i in range(N):
        expected = (expected + (i * i) % 1000000007) % 1000000007

    print("pool_ns="  + String(t1 - t0))
    print("workers="  + String(pool.n_workers))
    print("n="        + String(N))
    print("checksum=" + String(chk))
    print("correct="  + String(chk == expected))
