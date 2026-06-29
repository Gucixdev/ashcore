"""
Benchmark: Python threading.Lock contention — 8 threads, 100k lock/unlock pairs.
Equivalent to bench_sync.mojo / bench_sync.c.
"""
import threading
import time

WORKERS = 8
ITERS   = 100_000

mu      = threading.Lock()
counter = 0

def worker():
    global counter
    for _ in range(ITERS):
        with mu:
            counter += 1

threads = [threading.Thread(target=worker) for _ in range(WORKERS)]

t0 = time.perf_counter_ns()
for t in threads: t.start()
for t in threads: t.join()
t1 = time.perf_counter_ns()

total_ops = WORKERS * ITERS
print(f"lock_ns={t1 - t0}")
print(f"total_ops={total_ops}")
print(f"per_op_ns={(t1 - t0) // total_ops}")
print(f"counter={counter}")
print(f"workers={WORKERS}")
