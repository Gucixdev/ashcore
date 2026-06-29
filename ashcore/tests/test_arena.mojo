"""Tests for ashcore.arena — 3 tests per exported symbol."""

from ashcore.arena import Arena, ArenaCheckpoint, CACHE_LINE, REGION_DEFAULT


def assert_eq(label: String, got: Int, want: Int) raises:
    if got != want:
        raise Error("FAIL " + label + ": got " + String(got) + ", want " + String(want))
    print("  PASS " + label)

def assert_true(label: String, cond: Bool) raises:
    if not cond:
        raise Error("FAIL " + label + ": expected True")
    print("  PASS " + label)


# ── Arena.__init__ ──────────────────────────────────────────────────────────

def test_init() raises:
    print("test_init")
    # 1. default region size — starts empty, one region
    var a = Arena()
    assert_eq("init: used=0",      a.used(),      0)
    assert_eq("init: n_regions=1", a.n_regions(), 1)
    assert_eq("init: cap=REGION",  a.capacity(),  REGION_DEFAULT)
    # 2. custom region size
    var a2 = Arena(1024)
    assert_eq("init: custom cap", a2.capacity(), 1024)
    assert_eq("init: used=0",     a2.used(),     0)
    # 3. invalid size falls back to REGION_DEFAULT
    var a3 = Arena(0)
    assert_eq("init: cap=0 → default", a3.capacity(), REGION_DEFAULT)
    print()


# ── Arena.alloc ─────────────────────────────────────────────────────────────

def test_alloc() raises:
    print("test_alloc")
    var a = Arena(4096)
    # 1. first alloc — offset 0, 64B, CACHE_LINE aligned
    var p1 = a.alloc(64)
    assert_eq("alloc: used=64",          a.used(), 64)
    assert_true("alloc: 64B aligned",    (Int(p1) & 63) == 0)
    # 2. explicit alignment smaller than CACHE_LINE (align=16)
    var p2 = a.alloc(1, 16)
    assert_eq("alloc: used=65",          a.used(), 65)
    assert_true("alloc: 16B aligned",    (Int(p2) & 15) == 0)
    # 3. pointer is writable end-to-end
    var p3 = a.alloc(128, 1)
    p3[0]   = 0xAA
    p3[127] = 0xBB
    assert_true("alloc: first byte writable", p3[0] == 0xAA)
    assert_true("alloc: last byte writable",  p3[127] == 0xBB)
    print()


# ── Arena: auto-grow ─────────────────────────────────────────────────────────
# (key Tsoding-style feature: fills one region, starts the next)

def test_auto_grow() raises:
    print("test_auto_grow")
    var a = Arena(64)   # tiny region
    # 1. fill the first region exactly
    var p1 = a.alloc(64)
    assert_eq("grow: region 0 used", a.used(), 64)
    assert_eq("grow: still 1 region", a.n_regions(), 1)
    # 2. next alloc overflows — must auto-grow into region 1
    var p2 = a.alloc(64)
    assert_eq("grow: 2 regions after overflow", a.n_regions(), 2)
    assert_true("grow: region 1 ptr differs",   Int(p1) != Int(p2))
    # 3. oversized single alloc (larger than region_sz) — still works
    var a2 = Arena(16)
    var big = a2.alloc(1024)   # 1024 >> 16 → forces a big region
    assert_true("grow: big alloc not null", Int(big) != 0)
    assert_true("grow: big alloc n_regions >= 2", a2.n_regions() >= 2)
    print()


# ── Arena.alloc_zeroed ──────────────────────────────────────────────────────

def test_alloc_zeroed() raises:
    print("test_alloc_zeroed")
    var a = Arena(4096)
    # 1. previously-poisoned bytes are zeroed
    var tmp = a.alloc(64)
    for i in range(64):
        tmp[i] = 0xFF
    a.reset()
    var p = a.alloc_zeroed(64)
    var all_zero = True
    for i in range(64):
        if p[i] != 0:
            all_zero = False
    assert_true("alloc_zeroed: bytes are zero", all_zero)
    # 2. single-byte allocation is zero
    var p2 = a.alloc_zeroed(1, 1)
    assert_true("alloc_zeroed: size-1 zero", p2[0] == 0)
    # 3. default alignment is CACHE_LINE
    a.reset()
    var p3 = a.alloc_zeroed(32)
    assert_true("alloc_zeroed: default alignment", (Int(p3) & 63) == 0)
    print()


# ── Arena.alloc_simd ────────────────────────────────────────────────────────

def test_alloc_simd() raises:
    print("test_alloc_simd")
    var a = Arena(4096)
    # 1. float32 × 8 = 32 bytes, CACHE_LINE aligned
    var pf = a.alloc_simd[DType.float32, 8]()
    assert_eq("simd: float32x8 used=32",   a.used(), 32)
    assert_true("simd: float32x8 aligned", (Int(pf) & 63) == 0)
    # 2. int64 × 4 = 32 bytes — next CACHE_LINE boundary at 64
    var pi = a.alloc_simd[DType.int64, 4]()
    assert_eq("simd: int64x4 used=96",     a.used(), 96)
    assert_true("simd: int64x4 aligned",   (Int(pi) & 63) == 0)
    # 3. uint8 × 16 = 16 bytes — next boundary at 128
    var pu = a.alloc_simd[DType.uint8, 16]()
    assert_eq("simd: uint8x16 used=144",   a.used(), 144)
    assert_true("simd: uint8x16 aligned",  (Int(pu) & 63) == 0)
    print()


# ── Arena.copy_str ──────────────────────────────────────────────────────────

def test_copy_str() raises:
    print("test_copy_str")
    var a = Arena(4096)
    # 1. bytes match, null-terminated
    var s   = "hello, world"
    var p   = a.copy_str(s)
    var n   = s.byte_length()
    assert_true("copy_str: null terminator", p[n] == 0)
    var ok = True
    var src = s.unsafe_ptr()
    for i in range(n):
        if p[i] != src[i]:
            ok = False
    assert_true("copy_str: bytes match", ok)
    # 2. empty string — only the null byte
    var pos_before = a.used()
    var pe = a.copy_str("")
    assert_true("copy_str: empty null byte", pe[0] == 0)
    assert_eq("copy_str: empty used += 1", a.used(), pos_before + 1)
    # 3. two copies are independent (no alias)
    a.reset()
    var p1 = a.copy_str("AAA")
    var p2 = a.copy_str("BBB")
    p1[0] = 90   # 'Z'
    assert_true("copy_str: no alias", p2[0] != 90)
    print()


# ── Arena.checkpoint / restore ──────────────────────────────────────────────

def test_checkpoint_restore() raises:
    print("test_checkpoint_restore")
    var a = Arena(4096)
    # 1. checkpoint captures current region and pos
    var _ = a.alloc(100, 1)
    var cp = a.checkpoint()
    assert_eq("checkpoint: region=0", cp.region, 0)
    assert_eq("checkpoint: pos=100",  cp.pos,    100)
    var _ = a.alloc(200, 1)
    a.restore(cp)
    assert_eq("restore: used=100", a.used(), 100)
    # 2. nested checkpoints restore independently
    var cp0 = a.checkpoint()
    var _   = a.alloc(50, 1)
    var cp1 = a.checkpoint()
    var _   = a.alloc(50, 1)
    a.restore(cp1)
    assert_eq("restore: inner cp pos", a.used(), 150)
    a.restore(cp0)
    assert_eq("restore: outer cp pos", a.used(), 100)
    # 3. restore to a future position is a no-op
    var beyond = ArenaCheckpoint(0, 99999)
    a.restore(beyond)
    assert_eq("restore: future pos is no-op", a.used(), 100)
    print()


# ── Arena.checkpoint across region boundary ──────────────────────────────────

def test_checkpoint_cross_region() raises:
    print("test_checkpoint_cross_region")
    var a = Arena(64)
    var _ = a.alloc(64, 1)         # fills region 0 exactly
    var cp = a.checkpoint()        # checkpoint in region 0, pos=64
    assert_eq("cross-region: cp.region=0", cp.region, 0)
    # 1. alloc into region 1 (grow)
    var _ = a.alloc(64, 1)
    assert_eq("cross-region: 2 regions after grow", a.n_regions(), 2)
    assert_eq("cross-region: used=128 after grow", a.used(), 128)
    # 2. restore rewinds logical position — n_regions stays at 2 (list kept for reuse)
    a.restore(cp)
    assert_eq("cross-region: used=64 after restore", a.used(), 64)
    assert_eq("cross-region: n_regions still 2 (reusable)", a.n_regions(), 2)
    # 3. allocating after restore reuses existing region 1 — no extra region created
    var _ = a.alloc(32, 1)
    assert_eq("cross-region: used=96 (64+32)", a.used(), 96)
    assert_eq("cross-region: n_regions=2 (reused)", a.n_regions(), 2)
    print()


# ── Arena.reset ─────────────────────────────────────────────────────────────

def test_reset() raises:
    print("test_reset")
    var a = Arena(256)
    var _ = a.alloc(64)
    var _ = a.alloc(64)
    # 1. reset sets used=0
    a.reset()
    assert_eq("reset: used=0",    a.used(),      0)
    assert_eq("reset: region=0",  a.n_regions(), 1)  # regions not freed
    # 2. peak is preserved across reset
    assert_eq("reset: peak=128", a.peak_usage(), 128)
    # 3. can allocate again after reset (memory reused)
    var p = a.alloc(64)
    assert_eq("reset: used=64 after re-alloc", a.used(), 64)
    # 4. multi-region: regions are preserved (not freed) after reset
    var a2 = Arena(64)
    var _ = a2.alloc(64, 1)
    var _ = a2.alloc(64, 1)   # triggers grow to region 1
    assert_eq("reset: 2 regions before", a2.n_regions(), 2)
    a2.reset()
    assert_eq("reset: 2 regions preserved", a2.n_regions(), 2)
    assert_eq("reset: used=0 after multi-region", a2.used(), 0)
    print()


# ── Arena.reset_zeroed ──────────────────────────────────────────────────────

def test_reset_zeroed() raises:
    print("test_reset_zeroed")
    var a = Arena(256)
    var p = a.alloc(64)
    for i in range(64):
        p[i] = 0xAB
    # 1. used bytes are zeroed
    a.reset_zeroed()
    var zeroed = True
    for i in range(64):
        if p[i] != 0:
            zeroed = False
    assert_true("reset_zeroed: bytes zero", zeroed)
    # 2. used returns to 0
    assert_eq("reset_zeroed: used=0", a.used(), 0)
    # 3. peak is preserved
    assert_eq("reset_zeroed: peak=64", a.peak_usage(), 64)
    print()


# ── Arena.free_all ──────────────────────────────────────────────────────────

def test_free_all() raises:
    print("test_free_all")
    var a = Arena(64)
    var _ = a.alloc(64)   # fills region 0
    var _ = a.alloc(64)   # triggers region 1
    assert_eq("free_all: 2 regions before", a.n_regions(), 2)
    # 1. free_all drops all regions
    a.free_all()
    assert_eq("free_all: 1 region after",  a.n_regions(), 1)   # fresh region
    assert_eq("free_all: used=0",          a.used(),       0)
    # 2. arena is usable after free_all
    var p = a.alloc(64)
    assert_eq("free_all: alloc after", a.used(), 64)
    # 3. peak is preserved
    assert_true("free_all: peak preserved", a.peak_usage() >= 64)
    print()


# ── Arena.dump ──────────────────────────────────────────────────────────────

def test_dump() raises:
    print("test_dump")
    var a = Arena(1024)
    var _ = a.alloc(64)
    var s = a.dump()
    # 1. contains "Arena("
    assert_true("dump: has Arena(",   s.find("Arena(") >= 0)
    # 2. contains "regions="
    assert_true("dump: has regions=", s.find("regions=") >= 0)
    # 3. non-empty string
    assert_true("dump: non-empty",    s.byte_length() > 0)
    print()


# ── main ────────────────────────────────────────────────────────────────────

def main() raises:
    print("=== Arena Tests ===\n")
    test_init()
    test_alloc()
    test_auto_grow()
    test_alloc_zeroed()
    test_alloc_simd()
    test_copy_str()
    test_checkpoint_restore()
    test_checkpoint_cross_region()
    test_reset()
    test_reset_zeroed()
    test_free_all()
    test_dump()
    print("=== All arena tests passed ===")
