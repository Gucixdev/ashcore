"""
AshCore — high-performance foundation library for Mojo.

Modules:
  arena        — growing bump allocator (Tsoding-style, auto-grows, no OOM)
  sync         — ticket lock, mutex, RW lock, semaphore, once
  threadpool   — fixed worker count, work-sharing via atomic counter
  taskgraph    — static DAG: topological levels, parallel barrier per level
  reactivegraph — reactive DAG: barrier-free, event-queue driven
  parallel     — parallel_for / parallel_for_range convenience wrappers
  queue        — SPSC and MPSC event queues
  debug        — comptime DEBUG flag + zero-cost guards (dbg_assert, dbg_bounds, ...)

Quick start:
    from ashcore.arena      import Arena
    from ashcore.sync       import TicketLock, Semaphore
    from ashcore.threadpool import ThreadPool
    from ashcore.taskgraph  import TaskGraph
    from ashcore.parallel   import parallel_for
    from ashcore.queue      import EventQueue, SPSCQueue, pack_event, event_tag
    from ashcore.debug      import DEBUG, dbg_assert, dbg_bounds
"""

from ashcore.arena        import Arena, ArenaCheckpoint, CACHE_LINE, REGION_DEFAULT
from ashcore.sync         import TicketLock, RWLock, Semaphore, Once
from ashcore.shared_arena import SharedArena
from ashcore.threadpool   import ThreadPool, MAX_WORKERS
from ashcore.taskgraph    import TaskGraph, MAX_GRAPH_JOBS
from ashcore.reactivegraph import ReactiveGraph
from ashcore.parallel     import parallel_for, parallel_for_range
from ashcore.queue import (
    SPSCQueue, EventQueue, PopResult,
    pack_event, event_tag, event_payload
)
from ashcore.debug import (
    DEBUG,
    dbg_assert, dbg_bounds, dbg_positive, dbg_non_negative,
    dbg_power_of_two, dbg_eq, dbg_unreachable
)
from ashcore.gpu import (
    GPU_AVAILABLE, gpu_parallel_for, gpu_info
)
