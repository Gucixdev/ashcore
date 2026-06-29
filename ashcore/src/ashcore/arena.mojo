"""
AshCore - Arena Allocator  (Tsoding-style growing arena)

Backed by raw OS slabs (malloc/free) — zero metadata overhead, no
zero-initialization waste, full control over every byte.

  alloc()    — O(1) bump-pointer, never raises
  reset()    — O(1) rewind; oversized one-off slabs freed immediately
  free_all() — returns every slab to the OS

Thread-safety: none.  Use one Arena per thread or pair with SharedArena.
"""

from std.memory import UnsafePointer, memset_zero, memcpy
from ashcore.debug import DEBUG, dbg_positive, dbg_power_of_two, dbg_assert

comptime CACHE_LINE:     Int = 64               # AVX-512 / cache-line alignment
comptime REGION_DEFAULT: Int = 8 * 1024 * 1024  # 8 MiB default slab size


@always_inline
def _align_up(offset: Int, alignment: Int) -> Int:
    return (offset + alignment - 1) & ~(alignment - 1)


# ── raw slab helpers ──────────────────────────────────────────────────────────

@always_inline
def _slab_new(n: Int) -> Int:
    """Allocate n bytes; returns raw address (Int).  Panics on OOM in debug."""
    var ptr = UnsafePointer[UInt8].alloc(n)
    if DEBUG:
        dbg_assert(Int(ptr) != 0, "Arena._slab_new: malloc returned null")
    return Int(ptr)

@always_inline
def _slab_del(addr: Int):
    """Free a slab by raw address."""
    if addr != 0:
        UnsafePointer[UInt8](unsafe_from_address=addr).free()


# ── ArenaCheckpoint ───────────────────────────────────────────────────────────

struct ArenaCheckpoint(Copyable, ImplicitlyCopyable, Movable, ImplicitlyDeletable):
    """Opaque position marker returned by Arena.checkpoint()."""
    var region: Int
    var pos:    Int

    def __init__(out self, region: Int, pos: Int):
        self.region = region
        self.pos    = pos


# ── Arena ─────────────────────────────────────────────────────────────────────

struct Arena(Movable):
    """
    Growing linear bump allocator backed by raw OS slabs.

    Each slab is a single malloc()  with no List metadata or zero-init cost.
    On overflow the allocator scans for a reusable slab or appends a fresh one.

    reset() is O(1) for normal slabs.  Oversized slabs (created by a single
    alloc() larger than the default slab size) are freed on reset() to prevent
    memory bloat across request / frame cycles.

    Returned pointers carry __origin_of(self): the compiler enforces that the
    Arena outlives any allocation.  reset() / restore() rewind the bump pointer
    logically — existing pointers become dangling but the type system cannot
    detect that (inherent arena limitation).

    Example:
        var a = Arena()
        var p = a.alloc(sizeof[MyStruct]())   # bump-allocated, never fails
        a.reset()                              # O(1) rewind, ready for next frame
    """
    var _ptrs:   List[Int]   # raw addresses of malloc'd slabs
    var _sizes:  List[Int]   # byte capacity of each slab
    var _region: Int          # index of the active slab
    var _pos:    Int          # byte offset within the active slab
    var _peak:   Int          # lifetime high-water mark
    var _rgn_sz: Int          # target slab size; oversized slabs freed on reset()

    def __init__(out self, region_size: Int = REGION_DEFAULT):
        self._rgn_sz = region_size if region_size > 0 else REGION_DEFAULT
        self._region = 0
        self._pos    = 0
        self._peak   = 0
        self._ptrs   = List[Int]()
        self._sizes  = List[Int]()
        var addr = _slab_new(self._rgn_sz)
        self._ptrs.append(addr)
        self._sizes.append(self._rgn_sz)

    def __del__(owned self):
        for i in range(len(self._ptrs)):
            _slab_del(self._ptrs[i])

    def __moveinit__(out self, owned other: Self):
        self._ptrs   = other._ptrs^
        self._sizes  = other._sizes^
        self._region = other._region
        self._pos    = other._pos
        self._peak   = other._peak
        self._rgn_sz = other._rgn_sz

    # ── Core allocation ───────────────────────────────────────────────────────

    def alloc(
        mut self,
        size:      Int,
        alignment: Int = CACHE_LINE,
    ) -> UnsafePointer[UInt8, __origin_of(self)]:
        """
        Bump-allocate `size` aligned bytes.  Never raises; grows into a new
        slab when the current one is full.

        The returned pointer is valid until the Arena is destroyed, or until
        reset() / restore() rewinds past this allocation.

        Preconditions: size > 0, alignment is a power-of-2.
        """
        dbg_positive(size, "Arena.alloc: size")
        dbg_power_of_two(alignment, "Arena.alloc: alignment")

        var aligned = _align_up(self._pos, alignment)
        var end     = aligned + size

        if end > self._sizes[self._region]:
            self._grow(size)
            aligned = _align_up(0, alignment)
            end     = aligned + size

        var addr  = self._ptrs[self._region] + aligned
        self._pos = end

        var total = self._used_raw()
        if total > self._peak:
            self._peak = total

        return UnsafePointer[UInt8, __origin_of(self)](unsafe_from_address=addr)

    def alloc_zeroed(
        mut self,
        size:      Int,
        alignment: Int = CACHE_LINE,
    ) -> UnsafePointer[UInt8, __origin_of(self)]:
        """alloc() then zero the bytes."""
        var ptr = self.alloc(size, alignment)
        memset_zero(ptr, size)
        return ptr

    def alloc_simd[dtype: DType, width: Int](
        mut self,
    ) -> UnsafePointer[Scalar[dtype], __origin_of(self)]:
        """
        Allocate CACHE_LINE-aligned storage for SIMD[dtype, width].
        Returns UnsafePointer[Scalar[dtype]] ready for SIMD.load() / .store().
        """
        var n_bytes = width * dtype.sizeof()
        var raw = self.alloc(n_bytes, CACHE_LINE)
        return UnsafePointer[Scalar[dtype], __origin_of(self)](
            unsafe_from_address=Int(raw)
        )

    def copy_str(
        mut self,
        s:         String,
        alignment: Int = 1,
    ) -> UnsafePointer[UInt8, __origin_of(self)]:
        """Copy string bytes (null-terminated) into the arena."""
        var n   = s.byte_length() + 1
        var dst = self.alloc(n, alignment)
        memcpy(dest=dst, src=s.unsafe_ptr(), count=n - 1)
        (dst + n - 1)[0] = 0
        return dst

    # ── Checkpoint / scoped lifetime ──────────────────────────────────────────

    def checkpoint(self) -> ArenaCheckpoint:
        """Save current bump position.  Pair with restore() for scoped allocs."""
        return ArenaCheckpoint(self._region, self._pos)

    def restore(mut self, cp: ArenaCheckpoint):
        """Rewind to a previously saved checkpoint."""
        if cp.region > self._region:
            return
        if cp.region == self._region and cp.pos >= self._pos:
            return
        self._region = cp.region
        self._pos    = cp.pos

    # ── Lifetime ──────────────────────────────────────────────────────────────

    def reset(mut self):
        """
        O(1) rewind.  Normal-sized slabs are kept for reuse on the next run.
        Oversized slabs (from large one-off allocs) are freed to prevent
        memory bloat across request / frame cycles.
        """
        # _grow() always appends oversized slabs at the end of the list.
        while len(self._ptrs) > 1:
            var last = len(self._ptrs) - 1
            if self._sizes[last] > self._rgn_sz:
                _slab_del(self._ptrs.pop())
                _ = self._sizes.pop()
            else:
                break
        self._region = 0
        self._pos    = 0

    def reset_zeroed(mut self):
        """Rewind and zero previously used bytes (prevents data leakage)."""
        for i in range(self._region):
            memset_zero(
                UnsafePointer[UInt8](unsafe_from_address=self._ptrs[i]),
                self._sizes[i],
            )
        memset_zero(
            UnsafePointer[UInt8](unsafe_from_address=self._ptrs[self._region]),
            self._pos,
        )
        self.reset()

    def free_all(mut self):
        """Release all slabs to the OS.  Arena is empty but still usable."""
        for i in range(len(self._ptrs)):
            _slab_del(self._ptrs[i])
        self._ptrs   = List[Int]()
        self._sizes  = List[Int]()
        self._region = 0
        self._pos    = 0
        var addr = _slab_new(self._rgn_sz)
        self._ptrs.append(addr)
        self._sizes.append(self._rgn_sz)

    # ── Introspection ─────────────────────────────────────────────────────────

    def used(self) -> Int:
        """Total bytes currently bump-allocated (O(n_slabs))."""
        return self._used_raw()

    def peak_usage(self) -> Int:
        return self._peak

    def n_regions(self) -> Int:
        return len(self._ptrs)

    def capacity(self) -> Int:
        """Total bytes across all slabs."""
        var total = 0
        for i in range(len(self._sizes)):
            total += self._sizes[i]
        return total

    def dump(self) -> String:
        return (
            "Arena(slabs=" + String(len(self._ptrs))
            + ", used="    + String(self._used_raw())
            + ", peak="    + String(self._peak)
            + ", slab_sz=" + String(self._rgn_sz) + ")"
        )

    # ── Internal ──────────────────────────────────────────────────────────────

    def _used_raw(self) -> Int:
        var total = 0
        for i in range(self._region):
            total += self._sizes[i]
        return total + self._pos

    def _grow(mut self, min_size: Int):
        """Advance to the next slab large enough for min_size bytes."""
        var next = self._region + 1
        while next < len(self._ptrs):
            if self._sizes[next] >= min_size:
                self._region = next
                self._pos    = 0
                return
            next += 1
        # No suitable slab — allocate a fresh one.
        # If min_size > _rgn_sz the slab is "oversized" and will be freed on
        # the next reset() call to prevent long-lived memory bloat.
        var sz   = self._rgn_sz if self._rgn_sz >= min_size else min_size
        var addr = _slab_new(sz)
        self._ptrs.append(addr)
        self._sizes.append(sz)
        self._region = len(self._ptrs) - 1
        self._pos    = 0
