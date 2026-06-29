"""
Benchmark: TicketLock (FIFO + exponential backoff).
8 threads × 100k lock/unlock pairs — worst case for spinlocks.
"""
from ashcore.sync import TicketLock
from std.algorithm  import parallelize
from std.time       import perf_counter_ns

def main() raises:
    var ITERS     = 100000
    var WORKERS   = 8
    var total_ops = WORKERS * ITERS

    var tl      = TicketLock()
    var tl_ctr: Int = 0

    @parameter
    def worker(tid: Int):
        for _ in range(ITERS):
            tl.lock()
            tl_ctr += 1
            tl.unlock()

    var t0 = perf_counter_ns()
    parallelize[worker](WORKERS, WORKERS)
    var t1 = perf_counter_ns()
    var ns = t1 - t0

    print("lock_ns="    + String(ns))
    print("per_op_ns="  + String(UInt(ns // total_ops)))
    print("counter="    + String(tl_ctr))
    print("workers="    + String(WORKERS))
    print("total_ops="  + String(total_ops))
    print("correct="    + String(tl_ctr == total_ops))
