"""
AshCore - Arena Allocator  (Tsoding-style growing arena)

Allocates by advancing a pointer into a region.  When the region is full
a new one is allocated automatically — no OOM, no raises, no limits.
Reset is O(1): rewinds all region indices, reuses the memory on the next run.
free_all() returns every region to the OS.

Thread-safety: none.  Use one Arena per thread or pair with a Mutex.
"""

from std.memory import UnsafePointer, memset_zero, memcpy
from ashcore.debug import DEBUG, dbg_positive, dbg_power_of_two, dbg_assert

comptime CACHE_LINE:    Int = 64               # AVX-512 / cache line
comptime REGION_DEFAULT: Int = 8 * 1024 * 1024  # 8 MiB per region


@always_inline
def _align_up(offset: Int, alignment: Int) -> Int:
    return (offset + alignment - 1) & ~(alignment - 1)


# Opaque handle returned by checkpoint(); restore() rewinds to it.
struct ArenaCheckpoint:
    var region: Int
    var pos:    Int

    def __init__(out self, region: Int, pos: Int):
        self.region = region
        self.pos    = pos


struct Arena:
    """
    Growing linear bump allocator.

    API contract (C style — caller is responsible):
      · alloc(size, alignment) — size > 0, alignment must be power-of-2.
        Violating these preconditions is undefined behaviour, not an error.
      · Returned pointers are valid until reset() / restore() rewinds past them,
        or until free_all() is called.
      · reset() is O(1) — no memory is freed; it is reused on the next run.
      · free_all() releases every region; further alloc() re-grows from scratch.

    Example:
        var a = Arena()                     # 8 MiB first region, auto-grows
        var p = a.alloc(sizeof_mytype)      # bump pointer, no error check needed
        a.reset()                           # O(1) rewind
    """
    var _regions: List[List[UInt8]]   # list of heap regions; pointers into data
    var _region:  Int                  # index of the active region
    var _pos:     Int                  # byte offset inside the active region
    var _peak:    Int                  # lifetime high-water mark (total bytes)
    var _rgn_sz:  Int                  # default size for each new region


    def __init__(out self, region_size: Int = REGION_DEFAULT):
        self._rgn_sz  = region_size if region_size > 0 else REGION_DEFAULT
        self._region  = 0
        self._pos     = 0
        self._peak    = 0
        self._regions = List[List[UInt8]]()
        var r = List[UInt8](capacity=self._rgn_sz)
        r.resize(self._rgn_sz, 0)
        self._regions.append(r^)

    # ── Core allocation ────────────────────────────────────────────────────────

    def alloc(
        mut self,
        size:      Int,
        alignment: Int = CACHE_LINE,
    ) -> UnsafePointer[UInt8, MutAnyOrigin]:
        """
        Allocate `size` bytes with the given power-of-2 alignment.
        Never fails: grows into a new region when the current one is full.
        Precondition: size > 0, alignment is a power-of-2.
        Debug: aborts on precondition violation.
        """
        dbg_positive(size, "Arena.alloc: size")
        dbg_power_of_two(alignment, "Arena.alloc: alignment")
        var aligned = _align_up(self._pos, alignment)
        var end     = aligned + size

        if end > len(self._regions[self._region]):
            self._grow(aligned + size)   # move to a large-enough region
            aligned = _align_up(0, alignment)
            end     = aligned + size

        var ptr   = self._regions[self._region].unsafe_ptr() + aligned
        self._pos = end

        var total = self._used_raw()
        if total > self._peak:
            self._peak = total

        return UnsafePointer[UInt8, MutAnyOrigin](ptr)

    def alloc_zeroed(
        mut self,
        size:      Int,
        alignment: Int = CACHE_LINE,
    ) -> UnsafePointer[UInt8, MutAnyOrigin]:
        """alloc() + memset to zero."""
        var ptr = self.alloc(size, alignment)
        memset_zero(ptr, size)
        return ptr

    def alloc_simd[dtype: DType, width: Int](
        mut self,
    ) -> UnsafePointer[UInt8, MutAnyOrigin]:
        """Allocate CACHE_LINE-aligned storage for SIMD[dtype, width]."""
        comptime if dtype == DType.bool or dtype == DType.uint8 or dtype == DType.int8:
            return self.alloc(width * 1, CACHE_LINE)
        elif dtype == DType.float16 or dtype == DType.bfloat16 or dtype == DType.uint16 or dtype == DType.int16:
            return self.alloc(width * 2, CACHE_LINE)
        elif dtype == DType.float32 or dtype == DType.uint32 or dtype == DType.int32:
            return self.alloc(width * 4, CACHE_LINE)
        else:
            return self.alloc(width * 8, CACHE_LINE)

    def copy_str(
        mut self,
        s: String,
        alignment: Int = 1,
    ) -> UnsafePointer[UInt8, MutAnyOrigin]:
        """Copy string bytes into the arena (null-terminated)."""
        var n   = s.byte_length() + 1
        var dst = self.alloc(n, alignment)
        memcpy(dest=dst, src=s.unsafe_ptr(), count=n - 1)
        (dst + n - 1)[0] = 0
        return dst

    # ── Checkpoint / scoped lifetime ───────────────────────────────────────────

    def checkpoint(self) -> ArenaCheckpoint:
        """Save current position. Pair with restore() to free a scope's allocs."""
        return ArenaCheckpoint(self._region, self._pos)

    def restore(mut self, cp: ArenaCheckpoint):
        """
        Rewind to a previously saved checkpoint.
        No-op if cp points past the current position.
        """
        if cp.region > self._region:
            return
        if cp.region == self._region and cp.pos >= self._pos:
            return
        self._region = cp.region
        self._pos    = cp.pos

    # ── Lifetime ───────────────────────────────────────────────────────────────

    def reset(mut self):
        """O(1) rewind to the start. Memory is kept and reused on next allocs."""
        self._region = 0
        self._pos    = 0

    def reset_zeroed(mut self):
        """Rewind and zero previously used bytes (prevents data leakage)."""
        for i in range(self._region):
            memset_zero(self._regions[i].unsafe_ptr(), len(self._regions[i]))
        memset_zero(self._regions[self._region].unsafe_ptr(), self._pos)
        self._region = 0
        self._pos    = 0

    def free_all(mut self):
        """Release all regions to the OS.  Arena is empty but still usable."""
        self._regions = List[List[UInt8]]()
        self._region  = 0
        self._pos     = 0
        var r = List[UInt8](capacity=self._rgn_sz)
        r.resize(self._rgn_sz, 0)
        self._regions.append(r^)

    # ── Introspection ──────────────────────────────────────────────────────────

    def used(self) -> Int:
        """Total bytes currently allocated (O(n_regions))."""
        return self._used_raw()

    def peak_usage(self) -> Int:
        return self._peak

    def n_regions(self) -> Int:
        return len(self._regions)

    def capacity(self) -> Int:
        """Total bytes across all regions."""
        var total = 0
        for i in range(len(self._regions)):
            total += len(self._regions[i])
        return total

    def dump(self) -> String:
        return (
            "Arena(regions=" + String(len(self._regions))
            + ", used=" + String(self._used_raw())
            + ", peak=" + String(self._peak)
            + ", rgn_sz=" + String(self._rgn_sz) + ")"
        )

    # ── Internal ───────────────────────────────────────────────────────────────

    def _used_raw(self) -> Int:
        var total = 0
        for i in range(self._region):
            total += len(self._regions[i])
        return total + self._pos

    def _grow(mut self, min_size: Int):
        """Move to the next usable region, allocating a new one if needed."""
        # Scan forward for an existing region that is large enough to reuse.
        var next = self._region + 1
        while next < len(self._regions):
            if len(self._regions[next]) >= min_size:
                self._region = next
                self._pos    = 0
                return
            next += 1
        # No suitable region found — allocate a fresh one.
        var sz = self._rgn_sz if self._rgn_sz >= min_size else min_size
        var r  = List[UInt8](capacity=sz)
        r.resize(sz, 0)
        self._regions.append(r^)
        self._region = len(self._regions) - 1
        self._pos    = 0
