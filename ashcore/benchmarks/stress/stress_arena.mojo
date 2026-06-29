"""Stress: Arena 50 forced region grows + checkpoint/restore."""
from ashcore.arena import Arena

def main() raises:
    var a = Arena(65536)    # 64 KiB regions — forces grow every ~1100 allocs
    var allocs = 0
    for _ in range(50):
        var cp = a.checkpoint()
        for _ in range(1100):   # 1100 × 64B = 70.4 KiB > 64 KiB → forces new region
            _ = a.alloc(64)
            allocs += 1
        if a.n_regions() < 2:
            print("result=FAIL_regions")
            return
        a.restore(cp)
    print("allocs="              + String(allocs))
    print("regions="             + String(a.n_regions()))
    print("used_after_restore="  + String(a.used()))
    # Exact check: checkpoint was at pos=0 (start of each iteration),
    # so restore must bring used() back to exactly 0 — not just "< 65536"
    if a.used() == 0:
        print("result=OK")
    else:
        print("result=FAIL_used_nonzero=" + String(a.used()))
