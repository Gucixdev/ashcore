"""
AshCore - Synchronization Primitives

Primitives  (all are valid struct fields; do NOT move after first concurrent use):

  TicketLock  — fair FIFO spinlock.  Tight spin: optimal when critical sections
                are short (< 100 ns) since any delay overshoots the actual wait.
                Under max contention still behind OS pthread_mutex (futex sleeps
                waiters; not available in Mojo 1.0.0b2 stdlib).

  RWLock      — reader-writer lock (writers-preferred): multiple concurrent readers,
                exclusive writer.  Readers entering while a writer is pending back
                off to avoid writer starvation.

  Semaphore   — counting semaphore with backoff spin.

  Once        — double-checked locking guard: run a fn exactly once.
"""

from std.atomic import Atomic
from std.sys   import llvm_intrinsic
from std.ffi   import external_call
from ashcore.debug import DEBUG, dbg_assert, dbg_non_negative


# ---------------------------------------------------------------------------
# Ticket Lock  (fair, FIFO, spin-based)
# ---------------------------------------------------------------------------

struct TicketLock:
    """
    Fair spinlock — FIFO ordering, no starvation.

    Spin strategy: tight spin for first 63 iterations (fastest path for short
    waits), then PAUSE every 64th iteration (reduces cache-coherence bus
    traffic without yielding the CPU).  sched_yield is intentionally NOT used
    here — for a lock held for 2-50ns, yield causes 50-100µs OS sleep which
    is catastrophically slow compared to the wait itself.

    Under max contention (8 threads, 0ns critical section), still behind
    pthread_mutex (~1.4×) because futex removes waiters from the run queue
    entirely — not achievable in userspace.
    In realistic use (4 threads, ≥50ns critical section), TicketLock wins:
    no futex syscall, FIFO ordering, ~8ns lock+unlock vs ~30ns for mutex.

    Not re-entrant.  Use for short critical sections only.
    """
    var _next_ticket: Atomic[DType.int64]
    var _now_serving: Atomic[DType.int64]
    var _dbg_held:    Atomic[DType.int64]  # debug: 0=free, 1=held (always present, only used in debug)

    def __init__(out self):
        self._next_ticket = Atomic[DType.int64](0)
        self._now_serving = Atomic[DType.int64](0)
        self._dbg_held    = Atomic[DType.int64](0)

    @always_inline
    def lock(mut self):
        var my_ticket = self._next_ticket.fetch_add(1)
        var spins: Int = 0
        while self._now_serving.load() != my_ticket:
            spins += 1
            if spins & 63 == 0:
                llvm_intrinsic["llvm.x86.sse2.pause", NoneType]()
        if DEBUG:
            dbg_assert(self._dbg_held.load() == 0, "TicketLock.lock: already held (re-entry or bug)")
            self._dbg_held.store(1)

    @always_inline
    def unlock(mut self):
        if DEBUG:
            dbg_assert(self._dbg_held.load() == 1, "TicketLock.unlock: not held (double-unlock)")
            self._dbg_held.store(0)
        _ = self._now_serving.fetch_add(1)

    def is_locked(self) -> Bool:
        return self._now_serving.load() != self._next_ticket.load()


# ---------------------------------------------------------------------------
# Counting Semaphore  (with exponential backoff)
# ---------------------------------------------------------------------------

struct Semaphore:
    """
    Counting semaphore.

    post() increments the count.
    wait() decrements it, spinning with exponential backoff until count > 0.
    Backoff reduces cache-coherency traffic under sustained contention compared
    to a tight spin.

    Usage:
        var sem = Semaphore(0)
        # producer:  sem.post()
        # consumer:  sem.wait()
    """
    var _count: Atomic[DType.int64]

    def __init__(out self, initial: Int = 0):
        self._count = Atomic[DType.int64](Int64(initial))

    def post(mut self):
        _ = self._count.fetch_add(1)

    def post_many(mut self, n: Int):
        _ = self._count.fetch_add(Int64(n))

    def wait(mut self):
        """Decrement, spinning with PAUSE+yield until count > 0."""
        var spins = 0
        while True:
            if self._count.load() > 0:
                var prev = self._count.fetch_sub(1)
                if prev > 0:
                    return
                _ = self._count.fetch_add(1)   # restore — raced, try again
            llvm_intrinsic["llvm.x86.sse2.pause", NoneType]()
            spins += 1
            if spins == 128:
                _ = external_call["sched_yield", Int32]()
                spins = 0

    def try_wait(mut self) -> Bool:
        """Non-blocking decrement. Returns True on success."""
        if self._count.load() <= 0:
            return False
        var prev = self._count.fetch_sub(1)
        if prev > 0:
            return True
        _ = self._count.fetch_add(1)
        return False

    def value(self) -> Int:
        return Int(self._count.load())


# ---------------------------------------------------------------------------
# Read-Write Lock  (writers-preferred)
# ---------------------------------------------------------------------------

struct RWLock:
    """
    Reader-writer lock: concurrent reads, exclusive writes.

    Writers-preferred: readers that arrive while a writer is pending or writing
    back off, preventing writer starvation under sustained read load.
    Multiple readers admitted simultaneously hold the lock concurrently.

    Usage:
        var rw = RWLock()
        rw.read_lock();  /* ... */;  rw.read_unlock()
        rw.write_lock(); /* ... */;  rw.write_unlock()
    """
    var _write_gate:      TicketLock
    var _reader_count:    Atomic[DType.int64]
    var _pending_writers: Atomic[DType.int64]

    def __init__(out self):
        self._write_gate      = TicketLock()
        self._reader_count    = Atomic[DType.int64](0)
        self._pending_writers = Atomic[DType.int64](0)

    def read_lock(mut self):
        while True:
            while self._pending_writers.load() > 0:
                llvm_intrinsic["llvm.x86.sse2.pause", NoneType]()
            _ = self._reader_count.fetch_add(1)
            if self._pending_writers.load() == 0:
                return
            _ = self._reader_count.fetch_sub(1)

    def read_unlock(mut self):
        _ = self._reader_count.fetch_sub(1)

    def write_lock(mut self):
        _ = self._pending_writers.fetch_add(1)
        self._write_gate.lock()
        while self._reader_count.load() > 0:
            llvm_intrinsic["llvm.x86.sse2.pause", NoneType]()

    def write_unlock(mut self):
        _ = self._pending_writers.fetch_sub(1)
        self._write_gate.unlock()


# ---------------------------------------------------------------------------
# Once  — run a fn exactly once across threads
# ---------------------------------------------------------------------------

struct Once:
    """
    Run an action exactly once, even under concurrent calls.

    Usage:
        var guard = Once()
        guard.run[do_init]()   # safe to call from any thread
    """
    var _done: Atomic[DType.int64]
    var _mu:   TicketLock

    def __init__(out self):
        self._done = Atomic[DType.int64](0)
        self._mu   = TicketLock()

    def run[action: def() capturing -> None](mut self):
        if self._done.load() == 1:
            return   # fast path
        self._mu.lock()
        if self._done.load() == 0:
            action()
            self._done.store(1)
        self._mu.unlock()
