"""Tests for ashcore.sync and ashcore.jobs — 3 tests per exported function."""

from ashcore.sync  import TicketLock, RWLock, Semaphore, Once
from ashcore.jobs  import ThreadPool, TaskGraph, ReactiveGraph, parallel_for, parallel_for_range
from std.algorithm   import parallelize
from std.atomic      import Atomic
from std.time        import perf_counter_ns

def assert_eq(label: String, got: Int, want: Int) raises:
    if got != want:
        raise Error("FAIL " + label + ": got " + String(got) + ", want " + String(want))
    print("  PASS " + label)

def assert_true(label: String, cond: Bool) raises:
    if not cond:
        raise Error("FAIL " + label + ": expected True")
    print("  PASS " + label)

# -----------------------------------------------------------------------
# TicketLock

def test_ticket_lock_mutual_exclusion() raises:
    print("test_ticket_lock_mutual_exclusion")
    var mu      = TicketLock()
    var counter: Int = 0
    # 1. 10 000 parallel incs under lock → exactly 10 000
    @parameter
    def inc(tid: Int):
        mu.lock()
        counter += 1
        mu.unlock()
    parallelize[inc](10000, 8)
    assert_eq("TicketLock: counter after 10k incs", counter, 10000)
    # 2. is_locked() is False after all workers finish
    assert_true("TicketLock: not locked after use", not mu.is_locked())
    # 3. sequential reuse — lock/unlock twice, counter reaches 2
    var seq: Int = 0
    mu.lock(); seq += 1; mu.unlock()
    mu.lock(); seq += 1; mu.unlock()
    assert_eq("TicketLock: sequential reuse", seq, 2)
    print()

def test_ticket_lock_is_locked() raises:
    print("test_ticket_lock_is_locked")
    var mu = TicketLock()
    # 1. unlocked on construction
    assert_true("is_locked: False on init", not mu.is_locked())
    # 2. False after a complete lock/unlock cycle
    mu.lock()
    mu.unlock()
    assert_true("is_locked: False after unlock", not mu.is_locked())
    # 3. True while the lock is held (single-threaded to avoid race on reading)
    mu.lock()
    var held = mu.is_locked()
    mu.unlock()
    assert_true("is_locked: True while held", held)
    print()

# -----------------------------------------------------------------------
# RWLock

def test_rw_lock_write_counter() raises:
    print("test_rw_lock_write_counter")
    var rw      = RWLock()
    var counter: Int = 0
    # 1. 100 serial writers → counter == 100 (no race)
    @parameter
    def writer(tid: Int):
        rw.write_lock()
        counter += 1
        rw.write_unlock()
    parallelize[writer](100, 4)
    assert_eq("RWLock: write counter", counter, 100)
    # 2. reads after writes see final value
    @parameter
    def reader(tid: Int):
        rw.read_lock()
        var _ = counter
        rw.read_unlock()
    parallelize[reader](200, 8)
    assert_eq("RWLock: readers see final value", counter, 100)
    # 3. mixed: more writes, verify counter
    @parameter
    def writer2(tid: Int):
        rw.write_lock()
        counter += 1
        rw.write_unlock()
    parallelize[writer2](50, 4)
    assert_eq("RWLock: counter after more writes", counter, 150)
    print()

def test_rw_lock_concurrent_reads() raises:
    print("test_rw_lock_concurrent_reads")
    var rw = RWLock()
    var max_concurrent = Atomic[DType.int64](0)
    var active         = Atomic[DType.int64](0)
    # 1. multiple readers can hold simultaneously — peak active > 1
    @parameter
    def reader(tid: Int):
        rw.read_lock()
        var n = Int(active.fetch_add(1)) + 1
        _ = max_concurrent.max(Int64(n))
        var s = 0
        for i in range(1000):   # simulate work
            s += i
        _ = active.fetch_sub(1)
        rw.read_unlock()
    parallelize[reader](64, 8)
    assert_true("RWLock: concurrent readers admitted", Int(max_concurrent.load()) > 1)
    # 2. active count returns to 0 after all readers done
    assert_eq("RWLock: active=0 after all done", Int(active.load()), 0)
    # 3. read_lock / read_unlock balanced — no lingering readers block a writer
    var write_ran: Int = 0
    rw.write_lock()
    write_ran = 1
    rw.write_unlock()
    assert_eq("RWLock: writer admitted after readers done", write_ran, 1)
    print()

def test_rw_lock_writer_exclusion() raises:
    print("test_rw_lock_writer_exclusion")
    var rw       = RWLock()
    # 1. writer sets value; subsequent reader sees new value
    var slot = List[Int]()
    slot.append(0)
    rw.write_lock()
    slot[0] = 42
    rw.write_unlock()
    rw.read_lock()
    var read_val = slot[0]
    rw.read_unlock()
    assert_eq("RWLock: reader sees written value", read_val, 42)
    # 2. concurrent writers produce a correct total (no lost updates)
    var total: Int = 0
    @parameter
    def add_writer(tid: Int):
        rw.write_lock()
        total += 1
        rw.write_unlock()
    parallelize[add_writer](500, 4)
    assert_eq("RWLock: no lost writes", total, 500)
    # 3. write_unlock without reading leaves the lock clean for next writer
    var after: Int = 0
    rw.write_lock()
    after += 1
    rw.write_unlock()
    rw.write_lock()
    after += 1
    rw.write_unlock()
    assert_eq("RWLock: double write-cycle clean — lock reusable", after, 2)
    print()

# -----------------------------------------------------------------------
# Semaphore

def test_semaphore_post_wait() raises:
    print("test_semaphore_post_wait")
    var sem     = Semaphore(0)
    var counter = Atomic[DType.int64](0)
    # 1. balanced producers/consumers — value returns to 0
    @parameter
    def producer(i: Int):
        _ = counter.fetch_add(1)
        sem.post()
    @parameter
    def consumer(i: Int):
        sem.wait()
    parallelize[producer](200, 4)
    parallelize[consumer](200, 4)
    assert_eq("Semaphore: counter=200 after producers", Int(counter.load()), 200)
    assert_eq("Semaphore: value=0 after consumers",     sem.value(), 0)
    # 2. initial value > 0 allows immediate waits
    var sem2 = Semaphore(3)
    sem2.wait(); sem2.wait(); sem2.wait()
    assert_eq("Semaphore: initial=3 drained to 0", sem2.value(), 0)
    # 3. post_many(n) allows exactly n waits without blocking
    var sem3 = Semaphore(0)
    sem3.post_many(5)
    assert_eq("Semaphore: post_many(5) value=5", sem3.value(), 5)
    for _ in range(5):
        sem3.wait()
    assert_eq("Semaphore: post_many drained to 0", sem3.value(), 0)
    print()

def test_semaphore_try_wait() raises:
    print("test_semaphore_try_wait")
    var sem = Semaphore(0)
    # 1. try_wait on empty semaphore returns False
    assert_true("try_wait: False when empty", not sem.try_wait())
    # 2. try_wait after post returns True and decrements
    sem.post()
    assert_true("try_wait: True after post", sem.try_wait())
    assert_eq("try_wait: value=0 after success", sem.value(), 0)
    # 3. try_wait is non-blocking — second call after drain returns False
    assert_true("try_wait: False on re-try", not sem.try_wait())
    print()

# -----------------------------------------------------------------------
# Once

def test_once_basic() raises:
    print("test_once_basic")
    var once  = Once()
    var count: Int = 0
    # 1. first run() executes the action
    @parameter
    def do_init():
        count += 1
    once.run[do_init]()
    assert_eq("Once: action ran once", count, 1)
    # 2. subsequent calls are no-ops
    once.run[do_init]()
    once.run[do_init]()
    assert_eq("Once: still 1 after repeated calls", count, 1)
    # 3. concurrent calls — exactly one wins
    var once2  = Once()
    var count2: Int = 0
    @parameter
    def maybe(tid: Int):
        @parameter
        def action():
            count2 += 1
        once2.run[action]()
    parallelize[maybe](500, 8)
    assert_eq("Once: concurrent calls run once", count2, 1)
    print()

def test_once_stress() raises:
    print("test_once_stress")
    # 1. slow action under 500 threads, 10 trials — never runs more than once
    for trial in range(10):
        var once = Once()
        var cnt: Int = 0
        @parameter
        def worker(tid: Int):
            @parameter
            def slow():
                var s = 0
                for i in range(10000):
                    s += i
                cnt += 1
            once.run[slow]()
        parallelize[worker](500, 8)
        if cnt != 1:
            raise Error("FAIL Once stress trial " + String(trial) + ": cnt=" + String(cnt))
    print("  PASS Once: 10 trials x 500 threads, always exactly 1 execution")
    # 2. done flag is stable — re-checking doesn't re-run
    var once2 = Once()
    var n: Int = 0
    @parameter
    def init2():
        n += 1
    once2.run[init2]()
    once2.run[init2]()
    assert_eq("Once: idempotent after done", n, 1)
    # 3. two independent Once objects are independent
    var oa = Once(); var a: Int = 0
    var ob = Once(); var b: Int = 0
    @parameter
    def ia(): a += 1
    @parameter
    def ib(): b += 1
    oa.run[ia](); oa.run[ia]()
    ob.run[ib](); ob.run[ib]()
    assert_eq("Once: two instances independent a", a, 1)
    assert_eq("Once: two instances independent b", b, 1)
    print()

# -----------------------------------------------------------------------
# ThreadPool

def test_thread_pool_run() raises:
    print("test_thread_pool_run")
    var pool = ThreadPool(4)
    # 1. each task_id dispatched exactly once — fill results[i] = i*i
    var results = List[Int](capacity=1024)
    results.resize(1024, 0)
    @parameter
    def fill(i: Int):
        results[i] = i * i
    pool.run[fill](1024)
    assert_eq("pool.run: results[0]",    results[0],    0)
    assert_eq("pool.run: results[31]",   results[31],   961)
    assert_eq("pool.run: results[1023]", results[1023], 1046529)
    # 2. n_tasks=0 is a no-op (no crash, no dispatch)
    var ran: Int = 0
    @parameter
    def should_not_run(i: Int):
        ran += 1
    pool.run[should_not_run](0)
    assert_eq("pool.run: 0 tasks never dispatches", ran, 0)
    # 3. all 1M tasks run — sum of (i & 1) == 524288
    var n      = 1 << 20
    var parity = List[Int](capacity=n)
    parity.resize(n, 0)
    @parameter
    def set_parity(i: Int):
        parity[i] = i & 1
    pool.run[set_parity](n)
    var total: Int = 0
    for i in range(n):
        total += parity[i]
    assert_eq("pool.run: 1M task sum", total, 524288)
    print()

def test_thread_pool_run_range() raises:
    print("test_thread_pool_run_range")
    var pool = ThreadPool(4)
    # 1. dispatches i for i in [start, stop), indices correct
    var buf = List[Int](capacity=100)
    buf.resize(100, -1)
    @parameter
    def mark(i: Int):
        buf[i - 50] = i
    pool.run_range[mark](50, 100)
    assert_eq("run_range: buf[0]=50",  buf[0],  50)
    assert_eq("run_range: buf[49]=99", buf[49], 99)
    # 2. stop <= start is a no-op
    var ran: Int = 0
    @parameter
    def should_not(i: Int):
        ran += 1
    pool.run_range[should_not](10, 10)
    assert_eq("run_range: empty range no-op", ran, 0)
    # 3. large offset range — verify no capture corruption
    var big = List[Int](capacity=1000)
    big.resize(1000, 0)
    @parameter
    def big_mark(i: Int):
        big[i - 5000] = i
    pool.run_range[big_mark](5000, 6000)
    assert_eq("run_range: large offset [0]",   big[0],   5000)
    assert_eq("run_range: large offset [999]", big[999], 5999)
    print()

# -----------------------------------------------------------------------
# TaskGraph

def test_task_graph_flat() raises:
    print("test_task_graph_flat")
    var g    = TaskGraph()
    var pool = ThreadPool(4)
    for _ in range(8):
        _ = g.add_job()
    g.seal()
    # 1. flat graph has 1 level containing all jobs
    assert_eq("flat: n_levels=1",     g.n_levels(),    1)
    assert_eq("flat: level_size(0)=8", g.level_size(0), 8)
    # 2. each job dispatched exactly once with its ID
    var vals = List[Int](capacity=8)
    vals.resize(8, 0)
    @parameter
    def compute(id: Int):
        vals[id] = id + 1
    g.execute[compute](pool)
    for i in range(8):
        assert_eq("flat: val[" + String(i) + "]", vals[i], i + 1)
    # 3. out-of-range level_size returns 0
    assert_eq("flat: level_size(-1)=0",  g.level_size(-1), 0)
    assert_eq("flat: level_size(99)=0",  g.level_size(99), 0)
    print()

def test_task_graph_diamond() raises:
    print("test_task_graph_diamond")
    # Diamond:  A → {B, C} → D
    var g    = TaskGraph()
    var pool = ThreadPool(4)
    var a_id = g.add_job()
    var b_id = g.add_job()
    var c_id = g.add_job()
    var d_id = g.add_job()
    g.add_dep(b_id, a_id)
    g.add_dep(c_id, a_id)
    g.add_dep(d_id, b_id)
    g.add_dep(d_id, c_id)
    g.seal()
    # 1. 3 levels: A / {B,C} / D
    assert_eq("diamond: n_levels=3", g.n_levels(), 3)
    assert_eq("diamond: l0=1",       g.level_size(0), 1)
    assert_eq("diamond: l1=2",       g.level_size(1), 2)
    assert_eq("diamond: l2=1",       g.level_size(2), 1)
    # 2. data dependency satisfied: D = B + C = (A*2) + (A+3) = 5*2 + 5+3 = 18
    var out = List[Int](capacity=4)
    out.resize(4, 0)
    @parameter
    def run_dag(id: Int):
        if id == 0:   out[0] = 5
        elif id == 1: out[1] = out[0] * 2
        elif id == 2: out[2] = out[0] + 3
        elif id == 3: out[3] = out[1] + out[2]
    g.execute[run_dag](pool)
    assert_eq("diamond: D value", out[3], 18)
    # 3. re-execute produces the same result
    for i in range(4):
        out[i] = 0
    g.execute[run_dag](pool)
    assert_eq("diamond: re-execute D value", out[3], 18)
    print()

def test_task_graph_chain() raises:
    print("test_task_graph_chain")
    # Chain 0→1→2→…→9
    var g    = TaskGraph()
    var pool = ThreadPool(4)
    var prev = g.add_job()
    for _ in range(9):
        var cur = g.add_job()
        g.add_dep(cur, prev)
        prev = cur
    g.seal()
    # 1. n levels == n jobs for a pure chain
    assert_eq("chain: n_levels=10", g.n_levels(), 10)
    assert_eq("chain: n_jobs=10",   g.n_jobs(),   10)
    # 2. data dependency: acc[i] = acc[i-1] * 2, starting from 1 → acc[9] = 512
    var acc = List[Int](capacity=10)
    acc.resize(10, 0)
    @parameter
    def chain_run(id: Int):
        if id == 0: acc[0] = 1
        else:       acc[id] = acc[id - 1] * 2
    g.execute[chain_run](pool)
    assert_eq("chain: acc[0]=1",   acc[0], 1)
    assert_eq("chain: acc[9]=512", acc[9], 512)
    # 3. execute_serial produces the same sequence
    var acc2 = List[Int](capacity=10)
    acc2.resize(10, 0)
    @parameter
    def chain_run2(id: Int):
        if id == 0: acc2[0] = 1
        else:       acc2[id] = acc2[id - 1] * 2
    g.execute_serial[chain_run2]()
    assert_eq("chain: serial acc[9]=512", acc2[9], 512)
    print()

def test_task_graph_errors() raises:
    print("test_task_graph_errors")
    # 1. add_dep with self-loop raises
    var g  = TaskGraph()
    var a  = g.add_job()
    var ok = False
    try:
        g.add_dep(a, a)
    except:
        ok = True
    assert_true("add_dep: self-loop raises", ok)
    # 2. add_dep out-of-range raises
    var ok2 = False
    try:
        g.add_dep(a, 99)
    except:
        ok2 = True
    assert_true("add_dep: out-of-range raises", ok2)
    # 3. add_job after seal raises
    g.seal()
    var ok3 = False
    try:
        var _ = g.add_job()
    except:
        ok3 = True
    assert_true("add_job: after seal raises", ok3)
    print()

def test_task_graph_cycle() raises:
    print("test_task_graph_cycle")
    # 1. cycle detected at seal — raises
    var g = TaskGraph()
    var x = g.add_job()
    var y = g.add_job()
    var z = g.add_job()
    g.add_dep(y, x)
    g.add_dep(z, y)
    g.add_dep(x, z)
    var caught = False
    try:
        g.seal()
    except e:
        caught = True
        print("  cycle caught:", e)
    assert_true("cycle: seal raises", caught)
    # 2. after failed seal, execute also raises (not a silent no-op)
    var exec_raised = False
    try:
        var pool = ThreadPool(1)
        @parameter
        def noop(id: Int): pass
        g.execute[noop](pool)
    except:
        exec_raised = True
    assert_true("cycle: execute re-raises", exec_raised)
    # 3. duplicate dep does not cause false cycle
    var g2 = TaskGraph()
    var a  = g2.add_job()
    var b  = g2.add_job()
    g2.add_dep(b, a)
    g2.add_dep(b, a)
    g2.add_dep(b, a)
    var sealed_ok = False
    try:
        g2.seal()
        sealed_ok = True
    except:
        pass
    assert_true("cycle: dup dep no false cycle", sealed_ok)
    assert_eq("cycle: dup dep n_levels=2", g2.n_levels(), 2)
    print()

def test_task_graph_empty() raises:
    print("test_task_graph_empty")
    var g    = TaskGraph()
    var pool = ThreadPool(2)
    # 1. empty graph seals without error
    g.seal()
    assert_eq("empty: n_jobs=0",   g.n_jobs(),   0)
    assert_eq("empty: n_levels=0", g.n_levels(), 0)
    # 2. execute on empty graph dispatches nothing
    var ran: Int = 0
    @parameter
    def noop(id: Int):
        ran += 1
    g.execute[noop](pool)
    assert_eq("empty: execute dispatches 0 jobs", ran, 0)
    # 3. execute_serial on empty graph does nothing
    g.execute_serial[noop]()
    assert_eq("empty: execute_serial dispatches 0", ran, 0)
    print()

# -----------------------------------------------------------------------
# parallel_for

def test_parallel_for() raises:
    print("test_parallel_for")
    # 1. basic correctness — buf[i] = i % 100 for all i in [0, 10000)
    var buf = List[Int](capacity=10000)
    buf.resize(10000, 0)
    @parameter
    def fill(i: Int):
        buf[i] = i % 100
    parallel_for[fill](10000)
    var ok = True
    for i in range(10000):
        if buf[i] != i % 100:
            ok = False
    assert_true("parallel_for: correctness", ok)
    # 2. n=0 is a no-op
    var ran: Int = 0
    @parameter
    def should_not(i: Int):
        ran += 1
    parallel_for[should_not](0)
    assert_eq("parallel_for: n=0 no-op", ran, 0)
    # 3. n=1 dispatches exactly index 0
    var single = List[Int](capacity=1)
    single.resize(1, -1)
    @parameter
    def one(i: Int):
        single[i] = 42
    parallel_for[one](1)
    assert_eq("parallel_for: n=1 dispatches index 0", single[0], 42)
    print()

# -----------------------------------------------------------------------
# parallel_for_range

def test_parallel_for_range() raises:
    print("test_parallel_for_range")
    # 1. [500, 1000) — verify every index, no capture corruption
    var buf = List[Int](capacity=1000)
    buf.resize(1000, 0)
    @parameter
    def mark(i: Int):
        buf[i - 500] = i
    parallel_for_range[mark](500, 1000, 4)
    var ok = True
    for i in range(500):
        if buf[i] != 500 + i:
            ok = False
    assert_true("parallel_for_range: [500,1000) correct", ok)
    # 2. empty range [x, x) is a no-op
    var ran: Int = 0
    @parameter
    def noop(i: Int):
        ran += 1
    parallel_for_range[noop](100, 100)
    assert_eq("parallel_for_range: empty no-op", ran, 0)
    # 3. stop < start is also a no-op
    parallel_for_range[noop](200, 50)
    assert_eq("parallel_for_range: stop<start no-op", ran, 0)
    print()

# -----------------------------------------------------------------------
# Benchmark

def bench_pool() raises:
    print("bench_pool")
    var pool = ThreadPool()
    var n    = 1 << 20
    var sb   = List[Int](capacity=n)
    sb.resize(n, 0)
    @parameter
    def work(i: Int):
        sb[i] = i & 1
    var t0 = perf_counter_ns()
    pool.run[work](n)
    var t1 = perf_counter_ns()
    var total: Int = 0
    for i in range(n):
        total += sb[i]
    assert_eq("bench: 1M task parity sum", total, 524288)
    print("  " + String(n) + " tasks in " + String(t1 - t0) + " ns"
          + "  (" + String(pool.n_workers) + " workers)")
    print()

# -----------------------------------------------------------------------
# ReactiveGraph

def test_reactive_flat() raises:
    print("test_reactive_flat")
    var g    = ReactiveGraph()
    var pool = ThreadPool(4)
    for _ in range(8):
        _ = g.add_job()
    g.seal()
    # 1. all jobs dispatched exactly once
    var hits = List[Int](capacity=8)
    hits.resize(8, 0)
    @parameter
    def mark(id: Int):
        hits[id] += 1
    g.execute[mark](pool)
    var all_one = True
    for i in range(8):
        if hits[i] != 1:
            all_one = False
    assert_true("reactive flat: each job dispatched once", all_one)
    # 2. re-execute is idempotent — same result
    for i in range(8):
        hits[i] = 0
    g.execute[mark](pool)
    var all_one2 = True
    for i in range(8):
        if hits[i] != 1:
            all_one2 = False
    assert_true("reactive flat: re-execute correct", all_one2)
    # 3. n_jobs correct
    assert_eq("reactive flat: n_jobs=8", g.n_jobs(), 8)
    print()

def test_reactive_diamond() raises:
    print("test_reactive_diamond")
    # A→{B,C}→D  (same topology as TaskGraph diamond test)
    var g    = ReactiveGraph()
    var pool = ThreadPool(4)
    var a    = g.add_job()
    var b    = g.add_job()
    var c    = g.add_job()
    var d    = g.add_job()
    g.add_dep(b, a); g.add_dep(c, a)
    g.add_dep(d, b); g.add_dep(d, c)
    g.seal()
    # 1. data flows correctly: D = B + C = (A*2) + (A+3), A=5 → D=18
    var out = List[Int](capacity=4)
    out.resize(4, 0)
    @parameter
    def run_dag(id: Int):
        if id == 0:   out[0] = 5
        elif id == 1: out[1] = out[0] * 2
        elif id == 2: out[2] = out[0] + 3
        elif id == 3: out[3] = out[1] + out[2]
    g.execute[run_dag](pool)
    assert_eq("reactive diamond: D=18", out[3], 18)
    # 2. matches TaskGraph result on same computation
    var tg = TaskGraph()
    var ta = tg.add_job(); var tb = tg.add_job()
    var tc = tg.add_job(); var td = tg.add_job()
    tg.add_dep(tb, ta); tg.add_dep(tc, ta)
    tg.add_dep(td, tb); tg.add_dep(td, tc)
    tg.seal()
    var out2 = List[Int](capacity=4)
    out2.resize(4, 0)
    @parameter
    def run_dag2(id: Int):
        if id == 0:   out2[0] = 5
        elif id == 1: out2[1] = out2[0] * 2
        elif id == 2: out2[2] = out2[0] + 3
        elif id == 3: out2[3] = out2[1] + out2[2]
    tg.execute[run_dag2](pool)
    assert_eq("reactive diamond: matches TaskGraph", out[3], out2[3])
    # 3. re-execute from scratch produces same result
    for i in range(4):
        out[i] = 0
    g.execute[run_dag](pool)
    assert_eq("reactive diamond: re-execute D=18", out[3], 18)
    print()

def test_reactive_chain() raises:
    print("test_reactive_chain")
    var g    = ReactiveGraph()
    var pool = ThreadPool(4)
    var prev = g.add_job()
    for _ in range(9):
        var cur = g.add_job()
        g.add_dep(cur, prev)
        prev = cur
    g.seal()
    # 1. chain: acc[i] = acc[i-1] * 2, acc[0]=1 → acc[9]=512
    var acc = List[Int](capacity=10)
    acc.resize(10, 0)
    @parameter
    def chain_run(id: Int):
        if id == 0: acc[0] = 1
        else:       acc[id] = acc[id - 1] * 2
    g.execute[chain_run](pool)
    assert_eq("reactive chain: acc[9]=512", acc[9], 512)
    # 2. wide fan-out: job 0 → all others (10 leaves)
    var g2    = ReactiveGraph()
    var root = g2.add_job()
    for _ in range(10):
        var leaf = g2.add_job()
        g2.add_dep(leaf, root)
    g2.seal()
    var cnt = Atomic[DType.int64](0)
    @parameter
    def fan(id: Int):
        _ = cnt.fetch_add(1)
    g2.execute[fan](pool)
    assert_eq("reactive fan-out: 11 jobs ran", Int(cnt.load()), 11)
    # 3. cycle raises at seal
    var g3 = ReactiveGraph()
    var x  = g3.add_job(); var y = g3.add_job()
    g3.add_dep(y, x); g3.add_dep(x, y)
    var caught = False
    try:
        g3.seal()
    except:
        caught = True
    assert_true("reactive cycle: seal raises", caught)
    print()

def test_reactive_errors() raises:
    print("test_reactive_errors")
    # 1. add_dep after seal raises
    var g = ReactiveGraph()
    var a = g.add_job(); var b = g.add_job()
    g.seal()
    var ok = False
    try:
        g.add_dep(b, a)
    except:
        ok = True
    assert_true("reactive: add_dep after seal raises", ok)
    # 2. self-loop raises
    var g2 = ReactiveGraph()
    var j  = g2.add_job()
    var ok2 = False
    try:
        g2.add_dep(j, j)
    except:
        ok2 = True
    assert_true("reactive: self-loop raises", ok2)
    # 3. out-of-range dep raises
    var g3 = ReactiveGraph()
    _ = g3.add_job()
    var ok3 = False
    try:
        g3.add_dep(0, 99)
    except:
        ok3 = True
    assert_true("reactive: out-of-range dep raises", ok3)
    print()

def test_reactive_stress() raises:
    print("test_reactive_stress")
    # 100 jobs in a diamond-wide structure (10 "waves" of 10 parallel jobs)
    var g    = ReactiveGraph()
    var pool = ThreadPool(6)
    comptime WAVES: Int = 10
    comptime W:     Int = 10
    comptime TOTAL: Int = WAVES * W
    var ids = List[Int](capacity=TOTAL)
    ids.resize(TOTAL, 0)
    for w in range(WAVES):
        for j in range(W):
            ids[w * W + j] = g.add_job()
            if w > 0:
                # each job in wave w depends on all jobs in wave w-1
                for p in range(W):
                    g.add_dep(ids[w * W + j], ids[(w - 1) * W + p])
    g.seal()
    # 1. all 100 jobs run exactly once
    var hits = List[Int](capacity=TOTAL)
    hits.resize(TOTAL, 0)
    @parameter
    def run_stress(id: Int):
        hits[id] += 1
    g.execute[run_stress](pool)
    var all_hit = True
    for i in range(TOTAL):
        if hits[i] != 1:
            all_hit = False
    assert_true("reactive stress: all 100 jobs ran exactly once", all_hit)
    # 2. second execute also correct
    for i in range(TOTAL):
        hits[i] = 0
    g.execute[run_stress](pool)
    var all_hit2 = True
    for i in range(TOTAL):
        if hits[i] != 1:
            all_hit2 = False
    assert_true("reactive stress: second execute correct", all_hit2)
    # 3. n_jobs = 100
    assert_eq("reactive stress: n_jobs=100", g.n_jobs(), TOTAL)
    print()

def test_reactive_empty() raises:
    print("test_reactive_empty")
    var g    = ReactiveGraph()
    var pool = ThreadPool(2)
    # 1. seal on empty graph works
    g.seal()
    assert_true("reactive empty: sealed", g.is_sealed())
    assert_eq("reactive empty: n_jobs=0", g.n_jobs(), 0)
    # 2. execute dispatches nothing
    var ran: Int = 0
    @parameter
    def noop(id: Int):
        ran += 1
    g.execute[noop](pool)
    assert_eq("reactive empty: 0 dispatches", ran, 0)
    # 3. dump has non-empty output
    var s = g.dump()
    assert_true("reactive empty: dump non-empty", s.byte_length() > 0)
    print()

# -----------------------------------------------------------------------

def main() raises:
    print("=== Sync & Jobs Tests ===\n")
    test_ticket_lock_mutual_exclusion()
    test_ticket_lock_is_locked()
    test_rw_lock_write_counter()
    test_rw_lock_concurrent_reads()
    test_rw_lock_writer_exclusion()
    test_semaphore_post_wait()
    test_semaphore_try_wait()
    test_once_basic()
    test_once_stress()
    test_thread_pool_run()
    test_thread_pool_run_range()
    test_task_graph_flat()
    test_task_graph_diamond()
    test_task_graph_chain()
    test_task_graph_errors()
    test_task_graph_cycle()
    test_task_graph_empty()
    test_parallel_for()
    test_parallel_for_range()
    bench_pool()
    test_reactive_flat()
    test_reactive_diamond()
    test_reactive_chain()
    test_reactive_errors()
    test_reactive_stress()
    test_reactive_empty()
    print("=== All sync/jobs tests passed ===")
