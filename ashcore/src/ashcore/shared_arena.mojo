"""
SharedArena — thread-safe wrapper around Arena.

Kept in a separate module to avoid a circular import:
  arena.mojo  → ashcore.debug only
  sync.mojo   → ashcore.debug only
  shared_arena.mojo → ashcore.arena + ashcore.sync (no cycle)
"""

from std.memory import UnsafePointer
from ashcore.arena import Arena, ArenaCheckpoint, CACHE_LINE, REGION_DEFAULT
from ashcore.sync  import TicketLock


struct SharedArena:
    """
    Thread-safe Arena. Wraps Arena with a TicketLock — all operations are
    serialized. For maximum throughput give each thread its own Arena instead;
    use SharedArena only when multiple threads must allocate from the same pool.

    API is identical to Arena.

    Example:
        var a = SharedArena()       # shared across threads
        @parameter
        def worker(tid: Int):
            var p = a.alloc(64)     # safe from any thread
        pool.run[worker](n)
    """
    var _arena: Arena
    var _mu:    TicketLock

    def __init__(out self, region_size: Int = REGION_DEFAULT):
        self._arena = Arena(region_size)
        self._mu    = TicketLock()

    def alloc(mut self, size: Int, alignment: Int = CACHE_LINE) -> UnsafePointer[UInt8, MutAnyOrigin]:
        self._mu.lock()
        var p = self._arena.alloc(size, alignment)
        self._mu.unlock()
        return p

    def alloc_zeroed(mut self, size: Int, alignment: Int = CACHE_LINE) -> UnsafePointer[UInt8, MutAnyOrigin]:
        self._mu.lock()
        var p = self._arena.alloc_zeroed(size, alignment)
        self._mu.unlock()
        return p

    def alloc_simd[dtype: DType, width: Int](mut self) -> UnsafePointer[UInt8, MutAnyOrigin]:
        self._mu.lock()
        var p = self._arena.alloc_simd[dtype, width]()
        self._mu.unlock()
        return p

    def copy_str(mut self, s: String, alignment: Int = 1) -> UnsafePointer[UInt8, MutAnyOrigin]:
        self._mu.lock()
        var p = self._arena.copy_str(s, alignment)
        self._mu.unlock()
        return p

    def checkpoint(mut self) -> ArenaCheckpoint:
        self._mu.lock()
        var cp = self._arena.checkpoint()
        self._mu.unlock()
        return cp

    def restore(mut self, cp: ArenaCheckpoint):
        self._mu.lock()
        self._arena.restore(cp)
        self._mu.unlock()

    def reset(mut self):
        self._mu.lock()
        self._arena.reset()
        self._mu.unlock()

    def reset_zeroed(mut self):
        self._mu.lock()
        self._arena.reset_zeroed()
        self._mu.unlock()

    def free_all(mut self):
        self._mu.lock()
        self._arena.free_all()
        self._mu.unlock()

    def used(mut self) -> Int:
        self._mu.lock()
        var u = self._arena.used()
        self._mu.unlock()
        return u

    def peak_usage(mut self) -> Int:
        self._mu.lock()
        var p = self._arena.peak_usage()
        self._mu.unlock()
        return p

    def n_regions(mut self) -> Int:
        self._mu.lock()
        var n = self._arena.n_regions()
        self._mu.unlock()
        return n

    def capacity(mut self) -> Int:
        self._mu.lock()
        var c = self._arena.capacity()
        self._mu.unlock()
        return c

    def dump(mut self) -> String:
        self._mu.lock()
        var s = self._arena.dump()
        self._mu.unlock()
        return s
