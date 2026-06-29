"""
Benchmark: Python memory allocation — 1M x 64B bytearrays.
Equivalent to bench_arena.mojo / bench_arena.c.
"""
import gc
import time

N = 1_000_000

# warm up
for _ in range(1000):
    _ = bytearray(64)

gc.disable()

t0 = time.perf_counter_ns()
chunks = [bytearray(64) for _ in range(N)]
t1 = time.perf_counter_ns()
del chunks
t2 = time.perf_counter_ns()

gc.enable()

print(f"alloc_total_ns={t1 - t0}")
print(f"free_ns={t2 - t1}")
print(f"per_op_ns={(t1 - t0) // N}")
print(f"n={N}")
