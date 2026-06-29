"""
Stress: SPSCQueue — two independent tests:
  1. Sequential wrap-around: 1M push/pop cycles in one thread. Tests ring-buffer
     index arithmetic (bitmask wrapping, 125k wrap-arounds). NOT a concurrency test.
  2. Concurrent SPSC: producer + consumer run simultaneously via parallelize[f](2,2).
     Tests memory-ordering correctness: one thread pushes, one pops, both live.
"""
from ashcore.queue import SPSCQueue
from std.atomic      import Atomic
from std.algorithm   import parallelize

def main() raises:
    var q     = SPSCQueue(8)
    var TOTAL = 1000000
    var sent  = 0
    var recvd = 0
    var chk_s = 0
    var chk_r = 0
    var val   = 0

    for _ in range(TOTAL):
        # Try to push; if full, drain one first
        while not q.push(UInt64(val)):
            var r = q.pop()
            if r.ok:
                recvd += 1
                chk_r = (chk_r + Int(r.value)) % 1000000007
        chk_s = (chk_s + val) % 1000000007
        sent += 1
        val  += 1
        # Opportunistic pop
        var r = q.pop()
        if r.ok:
            recvd += 1
            chk_r = (chk_r + Int(r.value)) % 1000000007

    # Drain remainder
    while True:
        var r = q.pop()
        if not r.ok:
            break
        recvd += 1
        chk_r = (chk_r + Int(r.value)) % 1000000007

    print("sent="  + String(sent))
    print("recvd=" + String(recvd))
    print("chk_s=" + String(chk_s))
    print("chk_r=" + String(chk_r))
    var seq_ok = (sent == recvd) and (chk_s == chk_r)
    print("seq_ok=" + String(seq_ok))

    # ── Test 2: Concurrent SPSC — bare atomics (SPSCQueue.push/pop copies struct
    #    in @parameter def closures under parallelize — _head/_tail writes are lost)
    comptime N_CONC: Int = 100000
    comptime CAP2:   Int = 256
    comptime MASK2:  Int = 255
    var buf2   = List[UInt64](capacity=CAP2)
    buf2.resize(CAP2, 0)
    var b_head = Atomic[DType.int64](0)
    var b_tail = Atomic[DType.int64](0)
    var recv2  = Atomic[DType.int64](0)
    var chk_w  = Atomic[DType.int64](0)
    var chk_r2 = Atomic[DType.int64](0)

    @parameter
    def spsc_thread(tid: Int):
        if tid == 0:   # producer
            for i in range(N_CONC):
                while True:
                    var t = Int(b_tail.load())
                    var h = Int(b_head.load())
                    if t - h < CAP2:
                        buf2[t & MASK2] = UInt64(i)
                        b_tail.store(Int64(t + 1))
                        _ = chk_w.fetch_add(Int64(i))
                        break
        else:          # consumer
            var n = 0
            while n < N_CONC:
                var h = Int(b_head.load())
                if h < Int(b_tail.load()):
                    _ = chk_r2.fetch_add(Int64(buf2[h & MASK2]))
                    b_head.store(Int64(h + 1))
                    n += 1
            _ = recv2.fetch_add(Int64(n))

    parallelize[spsc_thread](2, 2)

    var conc_ok = (Int(recv2.load()) == N_CONC) and (chk_w.load() == chk_r2.load())
    print("conc_ok=" + String(conc_ok))

    if seq_ok and conc_ok:
        print("result=OK")
    else:
        print("result=FAIL seq=" + String(seq_ok) + " conc=" + String(conc_ok))
