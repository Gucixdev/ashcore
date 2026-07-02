"""
AshCore - Event Queue

Two queue types for different threading models:

  SPSCQueue   — Single-Producer Single-Consumer ring buffer.
                Wait-free: push and pop are each a single atomic store.
                Capacity is rounded to the next power of 2.
                Thread-safety contract: exactly ONE thread calls push(),
                exactly ONE different thread (or the same thread in
                alternate phases) calls pop().

  EventQueue  — Multi-Producer Single-Consumer queue.
                Push serialises via a Mutex; pop is wait-free.
                Suitable when many threads emit events to one consumer.

Both store UInt64 values.  Use pack_event / event_tag / event_payload
to embed a 16-bit type tag and 48-bit payload in a single word:

    var ev  = pack_event(MY_TYPE, value)
    queue.push(ev)
    var raw = queue.pop().value()
    var tag = event_tag(raw)
    var pay = event_payload(raw)
"""

from std.atomic    import Atomic
from ashcore.sync  import TicketLock
from ashcore.debug import DEBUG, dbg_assert


# ── Event packing helpers ───────────────────────────────────────────────────

@always_inline
def pack_event(tag: UInt64, payload: UInt64) -> UInt64:
    """Pack a 16-bit tag and 48-bit payload into one UInt64."""
    return (tag << 48) | (payload & 0x0000_FFFF_FFFF_FFFF)

@always_inline
def event_tag(event: UInt64) -> UInt64:
    """Extract the 16-bit tag from a packed event."""
    return event >> 48

@always_inline
def event_payload(event: UInt64) -> UInt64:
    """Extract the 48-bit payload from a packed event."""
    return event & 0x0000_FFFF_FFFF_FFFF


# ── Result type for pop() ───────────────────────────────────────────────────

struct PopResult:
    """
    Result of a pop() call.  Check .ok before reading .value.

    Example:
        var r = q.pop()
        if r.ok:
            handle(r.value)
    """
    var ok:    Bool
    var value: UInt64

    def __init__(out self, ok: Bool, value: UInt64):
        self.ok    = ok
        self.value = value


# ── SPSC ring buffer ────────────────────────────────────────────────────────

struct SPSCQueue:
    """
    Single-producer, single-consumer wait-free ring buffer of UInt64.

    Capacity is automatically rounded up to the next power of 2.

    Thread-safety:
      · Exactly ONE thread may call push() at a time.
      · Exactly ONE thread may call pop()  at a time.
      · The producer and consumer may be different threads.
      · push() and pop() are safe to call concurrently with each other.

    Usage:
        var q = SPSCQueue(4096)         # capacity rounded to power-of-2
        _ = q.push(pack_event(1, 42))   # producer; returns False if full
        var r = q.pop()                 # consumer; r.ok == False if empty
        if r.ok:
            print(event_payload(r.value))
    """
    var _buf:         List[UInt64]
    var _cap:         Int                      # actual capacity (power of 2)
    var _mask:        Int                      # cap - 1
    var _head:        Atomic[DType.int64]     # consumer position (monotonic)
    var _tail:        Atomic[DType.int64]     # producer position (monotonic)
    var _dbg_pushing: Atomic[DType.int64]     # debug: detects concurrent push
    var _dbg_popping: Atomic[DType.int64]     # debug: detects concurrent pop

    def __init__(out self, capacity: Int = 4096):
        # Round up to next power of 2
        var cap = 1
        while cap < capacity:
            cap = cap + cap
        self._cap         = cap
        self._mask        = cap - 1
        self._buf         = List[UInt64](capacity=cap)
        self._buf.resize(cap, UInt64(0))
        self._head        = Atomic[DType.int64](0)
        self._tail        = Atomic[DType.int64](0)
        self._dbg_pushing = Atomic[DType.int64](0)
        self._dbg_popping = Atomic[DType.int64](0)

    def push(mut self, val: UInt64) -> Bool:
        """
        Enqueue val.  Returns False (without blocking) if the queue is full.
        Must be called from at most one thread at a time (SPSC contract).
        Debug: aborts if concurrent push detected.
        """
        if DEBUG:
            var prev = self._dbg_pushing.fetch_add(1)
            dbg_assert(prev == 0, "SPSCQueue.push: concurrent producers — SPSC contract violated")
        var tail = Int(self._tail.load())
        var head = Int(self._head.load())
        if tail - head >= self._cap:
            if DEBUG: _ = self._dbg_pushing.fetch_sub(1)
            return False   # full
        self._buf[tail & self._mask] = val
        self._tail.store(Int64(tail + 1))
        if DEBUG: _ = self._dbg_pushing.fetch_sub(1)
        return True

    def pop(mut self) -> PopResult:
        """
        Dequeue the oldest item.  Returns PopResult(ok=False) if empty.
        Must be called from at most one thread at a time (SPSC contract).
        Debug: aborts if concurrent pop detected.
        """
        if DEBUG:
            var prev = self._dbg_popping.fetch_add(1)
            dbg_assert(prev == 0, "SPSCQueue.pop: concurrent consumers — SPSC contract violated")
        var head = Int(self._head.load())
        if head == Int(self._tail.load()):
            if DEBUG: _ = self._dbg_popping.fetch_sub(1)
            return PopResult(False, 0)   # empty
        var val = self._buf[head & self._mask]
        self._head.store(Int64(head + 1))
        if DEBUG: _ = self._dbg_popping.fetch_sub(1)
        return PopResult(True, val)

    def is_empty(self) -> Bool:
        return self._head.load() == self._tail.load()

    def is_full(self) -> Bool:
        return Int(self._tail.load()) - Int(self._head.load()) >= self._cap

    def len(self) -> Int:
        """Approximate number of items (may race with concurrent push/pop)."""
        var diff = Int(self._tail.load()) - Int(self._head.load())
        if diff < 0:
            return 0
        return diff

    def capacity(self) -> Int:
        return self._cap


# ── MPSC event queue ────────────────────────────────────────────────────────

struct EventQueue:
    """
    Multi-producer, single-consumer event queue.

    Any number of threads may call push() concurrently; they serialise via
    an internal Mutex.  pop() is wait-free and must be called from at most
    one thread at a time.

    Usage:
        var q = EventQueue(8192)
        # from any thread:
        _ = q.push(pack_event(MY_EV, data))
        # from the consumer thread:
        var r = q.pop()
        if r.ok:
            dispatch(r.value)
    """
    var _q:  SPSCQueue
    var _mu: TicketLock

    def __init__(out self, capacity: Int = 4096):
        self._q  = SPSCQueue(capacity)
        self._mu = TicketLock()

    def push(mut self, event: UInt64) -> Bool:
        """
        Enqueue event.  Blocks briefly if another producer is pushing.
        Returns False (without blocking) if the queue is full.
        """
        self._mu.lock()
        var ok = self._q.push(event)
        self._mu.unlock()
        return ok

    def pop(mut self) -> PopResult:
        """
        Dequeue one event.  Non-blocking; returns PopResult(ok=False) if empty.
        Must be called from at most one thread at a time.
        """
        return self._q.pop()

    def is_empty(self) -> Bool:
        return self._q.is_empty()

    def is_full(self) -> Bool:
        return self._q.is_full()

    def len(self) -> Int:
        return self._q.len()

    def capacity(self) -> Int:
        return self._q.capacity()
