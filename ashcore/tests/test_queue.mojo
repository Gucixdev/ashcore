"""Tests for ashcore.queue — 3 tests per exported symbol."""

from ashcore.queue import (
    SPSCQueue, EventQueue, PopResult,
    pack_event, event_tag, event_payload
)
from std.atomic import Atomic
from std.algorithm import parallelize


def assert_eq(label: String, got: Int, want: Int) raises:
    if got != want:
        raise Error("FAIL " + label + ": got " + String(got) + ", want " + String(want))
    print("  PASS " + label)

def assert_true(label: String, cond: Bool) raises:
    if not cond:
        raise Error("FAIL " + label + ": expected True")
    print("  PASS " + label)


# ── pack_event / event_tag / event_payload ──────────────────────────────────

def test_pack_event() raises:
    print("test_pack_event")
    # 1. pack then unpack round-trips correctly
    var ev = pack_event(7, 12345)
    assert_true("pack: tag==7",     event_tag(ev) == 7)
    assert_true("pack: payload",    event_payload(ev) == 12345)
    # 2. max tag (16 bits = 65535) and max payload (48 bits)
    var max_tag = UInt64(0xFFFF)
    var max_pay = UInt64(0x0000_FFFF_FFFF_FFFF)
    var ev2 = pack_event(max_tag, max_pay)
    assert_true("pack: max_tag",     event_tag(ev2) == max_tag)
    assert_true("pack: max_payload", event_payload(ev2) == max_pay)
    # 3. tag=0, payload=0 → event==0
    var ev3 = pack_event(0, 0)
    assert_true("pack: zero event", ev3 == 0)
    print()


# ── SPSCQueue.__init__ ──────────────────────────────────────────────────────

def test_spsc_init() raises:
    print("test_spsc_init")
    # 1. default capacity is rounded to power-of-2 (4096)
    var q = SPSCQueue(4096)
    assert_eq("spsc init: cap=4096", q.capacity(), 4096)
    assert_true("spsc init: empty",  q.is_empty())
    # 2. capacity that is not a power-of-2 is rounded up
    var q2 = SPSCQueue(3000)
    assert_eq("spsc init: 3000→4096", q2.capacity(), 4096)
    # 3. capacity=1 rounds to 1 (already power-of-2)
    var q3 = SPSCQueue(1)
    assert_eq("spsc init: cap=1", q3.capacity(), 1)
    print()


# ── SPSCQueue.push / pop ────────────────────────────────────────────────────

def test_spsc_push_pop() raises:
    print("test_spsc_push_pop")
    var q = SPSCQueue(4)
    # 1. push up to capacity, pop in FIFO order
    assert_true("spsc: push 0", q.push(10))
    assert_true("spsc: push 1", q.push(20))
    assert_true("spsc: push 2", q.push(30))
    assert_true("spsc: push 3", q.push(40))
    var r0 = q.pop(); assert_true("spsc: pop 0 ok",    r0.ok); assert_true("spsc: pop 0 val", r0.value == 10)
    var r1 = q.pop(); assert_true("spsc: pop 1 ok",    r1.ok); assert_true("spsc: pop 1 val", r1.value == 20)
    var r2 = q.pop(); assert_true("spsc: pop 2 ok",    r2.ok); assert_true("spsc: pop 2 val", r2.value == 30)
    var r3 = q.pop(); assert_true("spsc: pop 3 ok",    r3.ok); assert_true("spsc: pop 3 val", r3.value == 40)
    # 2. pop on empty returns ok=False
    var empty = q.pop()
    assert_true("spsc: empty ok=False", not empty.ok)
    # 3. push on full returns False; len stays at capacity
    var q2 = SPSCQueue(2)
    assert_true("spsc full: push 1", q2.push(1))
    assert_true("spsc full: push 2", q2.push(2))
    assert_true("spsc full: push 3 returns False", not q2.push(3))
    assert_eq("spsc full: len=2", q2.len(), 2)
    print()


# ── SPSCQueue: wrap-around (ring buffer correctness) ───────────────────────

def test_spsc_wrap() raises:
    print("test_spsc_wrap")
    var q = SPSCQueue(4)
    # Fill, drain, fill again — indices wrap around the ring
    # 1. fill and half-drain
    _ = q.push(1); _ = q.push(2); _ = q.push(3); _ = q.push(4)
    _ = q.pop();   _ = q.pop()
    # 2. push 2 more (wraps past the end of buffer)
    assert_true("wrap: push after drain", q.push(5))
    assert_true("wrap: push after drain", q.push(6))
    # 3. remaining pops return correct values in order
    var r3 = q.pop(); assert_true("wrap: val=3", r3.value == 3)
    var r4 = q.pop(); assert_true("wrap: val=4", r4.value == 4)
    var r5 = q.pop(); assert_true("wrap: val=5", r5.value == 5)
    var r6 = q.pop(); assert_true("wrap: val=6", r6.value == 6)
    assert_true("wrap: empty after drain", q.is_empty())
    print()


# ── SPSCQueue: capacity=1 edge case ─────────────────────────────────────────

def test_spsc_capacity_one() raises:
    print("test_spsc_capacity_one")
    var q = SPSCQueue(1)
    assert_eq("cap1: capacity=1",      q.capacity(), 1)
    assert_true("cap1: push OK",       q.push(UInt64(99)))
    assert_true("cap1: is_full",       q.is_full())
    assert_eq("cap1: len=1",           q.len(), 1)
    # 1. second push must fail (full at cap=1)
    assert_true("cap1: full → False",  not q.push(UInt64(77)))
    # 2. pop returns correct value
    var r = q.pop()
    assert_true("cap1: pop ok",        r.ok)
    assert_true("cap1: val=99",        r.value == UInt64(99))
    # 3. empty after pop, can push again
    assert_true("cap1: empty after",   q.is_empty())
    assert_eq("cap1: len=0",           q.len(), 0)
    assert_true("cap1: re-push",       q.push(UInt64(42)))
    assert_eq("cap1: len=1 re-push",   q.len(), 1)
    print()


# ── SPSCQueue: basic concurrent producer+consumer ────────────────────────────

def test_spsc_concurrent() raises:
    print("test_spsc_concurrent")
    # Run one producer and one consumer on separate parallelize calls.
    # SPSC contract: ONE producer, ONE consumer — verified by non-overlapping phases.
    comptime N: Int = 1024
    var q    = SPSCQueue(N)
    var sent = Atomic[DType.int64](0)
    var recv = Atomic[DType.int64](0)

    @parameter
    def producer(tid: Int):
        for i in range(N):
            while not q.push(UInt64(i)):
                pass
            _ = sent.fetch_add(1)

    @parameter
    def consumer(tid: Int):
        for i in range(N):
            while True:
                var r = q.pop()
                if r.ok:
                    _ = recv.fetch_add(1)
                    break

    parallelize[producer](1, 1)
    parallelize[consumer](1, 1)

    # 1. all elements sent equals all received
    assert_true("spsc concurrent: sent==recv",
                Int(sent.load()) == Int(recv.load()))
    # 2. queue is empty after full drain
    assert_true("spsc concurrent: empty after drain", q.is_empty())
    # 3. correct count
    assert_eq("spsc concurrent: N items", Int(sent.load()), N)
    print()


# ── EventQueue.__init__ ─────────────────────────────────────────────────────

def test_event_queue_init() raises:
    print("test_event_queue_init")
    # 1. default capacity
    var q = EventQueue(4096)
    assert_eq("eq init: cap=4096", q.capacity(), 4096)
    assert_true("eq init: empty",  q.is_empty())
    # 2. custom capacity round-up
    var q2 = EventQueue(100)
    assert_eq("eq init: 100→128", q2.capacity(), 128)
    # 3. len=0 on fresh queue
    assert_eq("eq init: len=0", q2.len(), 0)
    print()


# ── EventQueue.push / pop ───────────────────────────────────────────────────

def test_event_queue_push_pop() raises:
    print("test_event_queue_push_pop")
    var q = EventQueue(8)
    # 1. basic push/pop round-trip
    assert_true("eq: push 1",    q.push(pack_event(1, 100)))
    assert_true("eq: push 2",    q.push(pack_event(2, 200)))
    var r1 = q.pop()
    assert_true("eq: pop1 ok",   r1.ok)
    assert_true("eq: pop1 tag",  event_tag(r1.value) == 1)
    assert_true("eq: pop1 pay",  event_payload(r1.value) == 100)
    # 2. pop on empty returns ok=False
    _ = q.pop()   # consume second
    var empty = q.pop()
    assert_true("eq: empty ok=False", not empty.ok)
    # 3. full queue push returns False
    var q2 = EventQueue(2)
    _ = q2.push(1); _ = q2.push(2)
    assert_true("eq: full push False", not q2.push(3))
    print()


# ── EventQueue: concurrent producers ───────────────────────────────────────

def test_event_queue_concurrent_push() raises:
    print("test_event_queue_concurrent_push")
    # 4 producers × 512 pushes each = 2048 total; queue cap = 4096
    comptime PRODUCERS: Int = 4
    comptime PER_PROD:  Int = 512
    comptime TOTAL:     Int = PRODUCERS * PER_PROD

    var q       = EventQueue(4096)
    var dropped = Atomic[DType.int64](0)
    var pushed  = Atomic[DType.int64](0)

    @parameter
    def producer(tid: Int):
        for i in range(PER_PROD):
            var ev = pack_event(UInt64(tid), UInt64(i))
            if q.push(ev):
                _ = pushed.fetch_add(1)
            else:
                _ = dropped.fetch_add(1)

    parallelize[producer](PRODUCERS, PRODUCERS)

    var n_pushed = Int(pushed.load())
    var n_drain  = 0
    while True:
        var r = q.pop()
        if not r.ok:
            break
        n_drain += 1

    # 1. total pushed by workers matches what we drained
    assert_true("concurrent: drained == pushed",
                n_drain == n_pushed)
    # 2. queue is empty after draining
    assert_true("concurrent: empty after drain", q.is_empty())
    # 3. no silent corruption (dropped + pushed = total)
    assert_true("concurrent: no corruption",
                n_pushed + Int(dropped.load()) == TOTAL)
    print()


# ── main ────────────────────────────────────────────────────────────────────

def main() raises:
    print("=== Queue Tests ===\n")
    test_pack_event()
    test_spsc_init()
    test_spsc_push_pop()
    test_spsc_wrap()
    test_spsc_capacity_one()
    test_spsc_concurrent()
    test_event_queue_init()
    test_event_queue_push_pop()
    test_event_queue_concurrent_push()
    print("=== All queue tests passed ===")
