"""
Stress: TicketLock counter integrity — W threads × 100k lock/unlock, W = physical cores.
Uses parallelize directly (same pattern as bench_sync.mojo which passes correctness).
"""
from ashcore.sync  import TicketLock
from std.algorithm   import parallelize
from std.sys         import num_physical_cores

def main() raises:
    comptime OPS: Int = 100000
    var W       = num_physical_cores()
    var lock    = TicketLock()
    var counter = 0

    @parameter
    def hammer(tid: Int):
        for _ in range(OPS):
            lock.lock()
            counter += 1
            lock.unlock()

    parallelize[hammer](W, W)

    var expected = W * OPS
    print("workers="  + String(W))
    print("ops_each=" + String(OPS))
    print("counter="  + String(counter))
    print("expected=" + String(expected))
    if counter == expected:
        print("result=OK")
    else:
        print("result=FAIL counter=" + String(counter))
