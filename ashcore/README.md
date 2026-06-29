# ashcore

Low-level systems primitives for Mojo — arena allocator, thread pool, DAG scheduler, lock-free queues.

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![Platform: linux-64](https://img.shields.io/badge/platform-linux--64-lightgrey)
![Mojo MAX ≥26.4](https://img.shields.io/badge/MAX-%E2%89%A526.4-orange)

---

## Requirements

- [Modular MAX SDK](https://docs.modular.com/max/) ≥ 26.4 (`magic` CLI)
- linux-64 only — `TicketLock` uses `llvm.x86.sse2.pause` and `sched_yield` which are x86-64/POSIX. macOS/Windows/aarch64 patches welcome.

## Install

```bash
git clone git@github.com:Gucixdev/ashcore.git
cd ashcore
magic install
```

Run anything with:

```bash
magic run mojo run -I src <file.mojo>
```

---

## Components

### Arena

Bump-pointer allocator. Never frees individual allocations — resets in O(1). Auto-grows by adding regions; memory is never moved.

```mojo
from ashcore.arena import Arena

var a = Arena()                   # 8 MiB first region, grows automatically
var p = a.alloc(64)               # 64-byte, cache-line aligned
var q = a.alloc_zeroed(128)       # same + memset
var cp = a.checkpoint()           # save position
a.reset()                         # O(1) rewind — all pointers invalid after this
a.restore(cp)                     # rewind to exact saved position
```

| Method | Notes |
|---|---|
| `Arena(region_size)` | Default 8 MiB; grows by adding regions |
| `alloc(size, alignment)` | Never fails; alignment defaults to 64 B |
| `alloc_zeroed(size)` | `alloc` + memset |
| `alloc_simd[dtype, width]()` | Cache-line aligned slot for a SIMD vector |
| `copy_str(s)` | Copies string bytes + null terminator |
| `checkpoint()` → `ArenaCheckpoint` | |
| `restore(cp)` | Rewinds to checkpoint |
| `reset()` | O(1) rewind to start |
| `free_all()` | Returns all regions to OS |
| `used()` / `peak_usage()` / `n_regions()` | Stats |

### SharedArena

Thread-safe drop-in for `Arena`. Wraps it with a `TicketLock` — identical API, all operations serialized. For maximum throughput give each thread its own `Arena` instead; use `SharedArena` only when threads must allocate from the same pool.

```mojo
from ashcore.shared_arena import SharedArena

var a = SharedArena()

@parameter
def worker(tid: Int):
    var p = a.alloc(64)   # safe from any thread
    _ = p

pool.run[worker](n)
```

---

### Sync

#### TicketLock

FIFO spinlock. Guarantees ordering — no starvation. Tight spin + PAUSE every 64 iterations.

```mojo
from ashcore.sync import TicketLock

var mu = TicketLock()
mu.lock()
# critical section
mu.unlock()
```

Realistic performance (4 threads, ~50 ns critical section): **17 ms** vs C `pthread_mutex` **62 ms** → 3.6× faster.
Worst-case (8 threads, 0 ns critical section): ~87 ms vs C 61 ms — `futex` removes waiters from the run queue entirely, userspace cannot match that.

#### RWLock

Writers-preferred reader-writer lock built on `TicketLock`.

```mojo
from ashcore.sync import RWLock

var rw = RWLock()
rw.read_lock();  # ... read ...  rw.read_unlock()
rw.write_lock(); # ... write ... rw.write_unlock()
```

#### Semaphore

Counting semaphore with PAUSE + `sched_yield` backoff.

```mojo
from ashcore.sync import Semaphore

var sem = Semaphore(0)
# producer thread:
sem.post()
# consumer thread:
sem.wait()          # blocks until count > 0
_ = sem.try_wait()  # non-blocking; returns Bool
```

#### Once

Runs a parameterized action exactly once across threads.

```mojo
from ashcore.sync import Once

var guard = Once()

@parameter
def init():
    # expensive one-time setup

guard.run[init]()   # safe to call from any number of threads
```

---

### ThreadPool

Fixed thread pool. Default worker count = `num_physical_cores()`. Dispatches in chunks of 64 tasks per atomic to minimize cache-line contention.

```mojo
from ashcore.jobs import ThreadPool

var pool = ThreadPool()        # physical core count
var data = List[Int](capacity=1024)
data.resize(1024, 0)

@parameter
def process(i: Int):
    data[i] = i * i

pool.run[process](1024)        # calls process(0..1023) in parallel
pool.run_range[process](10, 20) # calls process(10..19)
```

Shorthand without creating a pool:

```mojo
from ashcore.jobs import parallel_for

@parameter
def work(i: Int):
    pass

parallel_for[work](N)
parallel_for[work](N, n_workers=4)
```

---

### TaskGraph / ReactiveGraph

Static DAGs with dependency tracking. Both use the same build API.

**TaskGraph** — level-by-level with barriers between levels:

```mojo
from ashcore.jobs import TaskGraph, ThreadPool

var pool = ThreadPool()
var g = TaskGraph()

var a = g.add_job()
var b = g.add_job()
var c = g.add_job()
g.add_dep(c, a)   # c depends on a
g.add_dep(c, b)   # c depends on b

@parameter
def run(jid: Int):
    pass

g.execute[run](pool)   # a and b run in parallel, then c
```

**ReactiveGraph** — barrier-free: each job enqueues its dependents atomically as it finishes. Lower overhead for deep graphs with uneven runtimes.

```mojo
from ashcore.jobs import ReactiveGraph, ThreadPool

var pool = ThreadPool()
var g = ReactiveGraph()
# same build API as TaskGraph
g.execute[run](pool)   # idempotent — can be called multiple times
```

Both raise on cycles (detected at `seal()`). `execute` calls `seal()` automatically on first call.

---

### Queue

#### SPSCQueue

Wait-free ring buffer. Capacity rounded to next power of 2. **One producer thread, one consumer thread only.**

```mojo
from ashcore.queue import SPSCQueue, pack_event, event_payload

var q = SPSCQueue(4096)

# producer:
if not q.push(pack_event(1, 42)):
    pass  # full — retry or drop

# consumer:
var r = q.pop()
if r.ok:
    print(event_payload(r.value))
```

Events are packed `UInt64`: upper 16 bits = tag, lower 48 bits = payload.

| Helper | Notes |
|---|---|
| `pack_event(tag, payload)` | Both `UInt64` |
| `event_tag(event)` | Upper 16 bits |
| `event_payload(event)` | Lower 48 bits |

#### EventQueue

Multi-producer single-consumer. Wraps `SPSCQueue` + `TicketLock` for thread-safe `push`.

```mojo
from ashcore.queue import EventQueue, pack_event, event_payload

var q = EventQueue(8192)

# from any thread:
_ = q.push(pack_event(MY_TAG, data))

# consumer thread only:
var r = q.pop()
if r.ok:
    dispatch(event_tag(r.value), event_payload(r.value))
```

---

### Debug guards

All guards compile away to nothing when `DEBUG = False` (the default). Enable with `sed -i 's/DEBUG: Bool = False/DEBUG: Bool = True/' src/ashcore/debug.mojo`.

```mojo
from ashcore.debug import dbg_assert, dbg_bounds, dbg_unreachable

dbg_assert(x > 0, "must be positive")
dbg_bounds(i, 0, len)
dbg_unreachable("should never reach this branch")
```

| Guard | Checks |
|---|---|
| `dbg_assert(cond, msg)` | Arbitrary condition |
| `dbg_bounds(i, lo, hi)` | `lo <= i < hi` |
| `dbg_positive(x, msg)` | `x > 0` |
| `dbg_non_negative(x, msg)` | `x >= 0` |
| `dbg_power_of_two(x, msg)` | `x & (x-1) == 0` |
| `dbg_eq(a, b, msg)` | `a == b` |
| `dbg_unreachable(msg)` | Always aborts in debug mode |

---

## Limitations

| Component | Thread safety |
|---|---|
| `Arena` | **Not thread-safe.** Give each thread its own arena, or use `SharedArena` for a shared pool. |
| `SPSCQueue` | Exactly **1 producer + 1 consumer**. Multiple producers = silent data corruption. |
| `EventQueue` | **N producers** (TicketLock on push) + **1 consumer** only. |
| `ThreadPool.run` | The dispatch function runs concurrently — shared state inside it is your problem. |
| `TaskGraph` / `ReactiveGraph` | Build phase (`add_job`, `add_dep`) is **single-threaded only**. `execute` is safe from one thread. |
| `TicketLock`, `RWLock`, `Semaphore`, `Once` | Thread-safe by design. |

---

## Performance

Measured on linux-64, best of 3 runs, no background load.

| Benchmark | Result |
|---|---|
| Arena 1M × 64 B allocs | ~1 ns/alloc |
| Arena reset | O(1) — single integer write |
| TicketLock, 4 threads, 50 ns crit section | **17 ms** vs C pthread_mutex **62 ms** (3.6×) |
| TicketLock, 8 threads, 0 ns crit section | 87 ms vs C 61 ms (futex wins in kernel — expected) |
| Parallel SIMD reduce 1M Int64 | AVX2 auto-vectorized (8×Int64 / iteration) |

---

## Testing

```bash
./run          # unit tests: arena, jobs, queue, debug
./bench        # benchmarks — best of 3 runs
./stresstest   # 7 extreme scenarios: forced grows, MPSC flood, DAG respawn,
               # TicketLock contention, SPSC wrap-around, concurrent SPSC, debug guards
./compare      # Mojo vs C vs Python side-by-side
./test all     # all of the above in one shot
```

##TODO
hash system 

## License

[MIT](LICENSE)
