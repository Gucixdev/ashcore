"""
Stress: Queue flood — 4 producers × 100k events each.

Uses EventQueue via direct parallelize (not pool.run) to avoid capture nesting issues.
Consumer drains after all producers finish. pushed == drained must hold.
"""
from ashcore.queue import EventQueue, pack_event, event_payload
from std.atomic      import Atomic
from std.algorithm   import parallelize

def main() raises:
    comptime N:      Int = 100000
    comptime N_PROD: Int = 4
    comptime TOTAL:  Int = N * N_PROD
    comptime MOD:    Int = 1000000007

    var q         = EventQueue(TOTAL + 64)
    var pushed    = Atomic[DType.int64](0)
    var chk_push  = Atomic[DType.int64](0)

    @parameter
    def produce(tid: Int):
        for i in range(N):
            var payload = UInt64(tid * N + i)
            while not q.push(pack_event(UInt64(1), payload)):
                pass
            _ = pushed.fetch_add(1)
            _ = chk_push.fetch_add(Int64(payload) % Int64(MOD))

    parallelize[produce](N_PROD, N_PROD)

    var p         = Int(pushed.load())
    var drained   = 0
    var chk_drain = Int64(0)
    while not q.is_empty():
        var r = q.pop()
        if r.ok:
            drained += 1
            chk_drain += Int64(event_payload(r.value) % UInt64(MOD))

    var chk_p = Int(chk_push.load() % Int64(MOD))
    var chk_d = Int(chk_drain % Int64(MOD))

    print("pushed="    + String(p))
    print("drained="   + String(drained))
    print("chk_push="  + String(chk_p))
    print("chk_drain=" + String(chk_d))
    # p == TOTAL was trivially true (capacity > total); removed. Payload checksum is the real guard.
    if drained == TOTAL and chk_p == chk_d:
        print("result=OK")
    else:
        print("result=FAIL drained=" + String(drained) + "/" + String(TOTAL)
              + " chk=" + String(chk_p) + "/" + String(chk_d))
