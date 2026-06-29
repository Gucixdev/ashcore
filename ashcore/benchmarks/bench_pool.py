"""
Benchmark: Python parallel computation.
Tries multiprocessing.Pool (true parallelism) and threading (GIL-limited).
"""
import time
import multiprocessing
import concurrent.futures

N   = 1_000_000
MOD = 1_000_000_007

def _work(i: int) -> int:
    return (i * i) % MOD

def bench_multiprocessing():
    workers = multiprocessing.cpu_count()
    t0 = time.perf_counter_ns()
    with multiprocessing.Pool(processes=workers) as pool:
        results = pool.map(_work, range(N), chunksize=10000)
    t1 = time.perf_counter_ns()
    chk = sum(results) % MOD
    return t1 - t0, workers, chk

def bench_threading():
    workers = multiprocessing.cpu_count()
    results = [0] * N
    t0 = time.perf_counter_ns()
    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as ex:
        for i, v in zip(range(N), ex.map(_work, range(N), chunksize=10000)):
            results[i] = v
    t1 = time.perf_counter_ns()
    chk = sum(results) % MOD
    return t1 - t0, workers, chk

if __name__ == '__main__':
    mp_ns, mp_w, mp_chk = bench_multiprocessing()
    th_ns, th_w, th_chk = bench_threading()

    print(f"mp_pool_ns={mp_ns}")
    print(f"mp_workers={mp_w}")
    print(f"mp_checksum={mp_chk}")
    print(f"th_pool_ns={th_ns}")
    print(f"th_workers={th_w}")
    print(f"th_checksum={th_chk}")
    print(f"n={N}")
