"""
ashcore example: per-request scratch arena (game-frame allocator pattern).

One arena is reused across requests: checkpoint before, restore after.
No system allocations happen after the first request fills the region.
"""
from ashcore.arena import Arena

def main() raises:
    var a = Arena(64 * 1024)

    print("── Request 1 ──────────────────────")
    var cp1 = a.checkpoint()
    _ = a.alloc(1024, 8)
    _ = a.alloc(256, 4)
    var s1 = a.copy_str(String("hello from request 1"))
    print("  allocated 1024 + 256 bytes + string")
    print("  used  = " + String(a.used()) + " bytes")
    a.restore(cp1)
    print("  after restore: used = " + String(a.used()))

    print("── Request 2 (same memory, zero extra syscalls) ──")
    var cp2 = a.checkpoint()
    _ = a.alloc(512, 8)
    var s2 = a.copy_str(String("request 2 reuses the same region"))
    print("  allocated 512 bytes + string")
    print("  used  = " + String(a.used()) + " bytes")
    a.restore(cp2)

    print("── Request 3 (zeroed buffer) ──────")
    var cp3 = a.checkpoint()
    _ = a.alloc_zeroed(4096, 8)
    print("  allocated 4096 zeroed bytes; used = " + String(a.used()))
    a.restore(cp3)

    print("── Summary ────────────────────────")
    print("  peak  = " + String(a.peak_usage()) + " bytes")
    print("  regs  = " + String(a.n_regions()))
    a.free_all()
    print("  after free_all: regs = " + String(a.n_regions()))
