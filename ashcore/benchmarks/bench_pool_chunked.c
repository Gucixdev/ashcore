/*
 * Fair C benchmark: ThreadPool with CHUNK=64 — same batching as Mojo.
 *
 * The standard bench_pool.c does one atomic per task → serial bottleneck.
 * This version uses CHUNK=64 (same as Mojo's ThreadPool) to show that the
 * speedup is from BATCHING, not from Mojo itself.
 *
 * Expected result: ~0.5ms (similar to Mojo), confirming the bottleneck is
 * atomic contention, not language performance.
 *
 * Compile: gcc -O2 -o bench_pool_chunked bench_pool_chunked.c -lpthread
 */
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdatomic.h>
#include <pthread.h>
#include <time.h>
#include <unistd.h>

#define N     1000000
#define MOD   1000000007
#define CHUNK 64

static int        buf[N];
static atomic_int next_idx;
static int        total_workers;

static int64_t ns_now(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (int64_t)ts.tv_sec * 1000000000LL + ts.tv_nsec;
}

static void *worker(void *arg) {
    (void)arg;
    for (;;) {
        int start = atomic_fetch_add(&next_idx, CHUNK);
        if (start >= N) break;
        int stop = start + CHUNK;
        if (stop > N) stop = N;
        for (int i = start; i < stop; i++)
            buf[i] = (int)(((long long)i * i) % MOD);
    }
    return NULL;
}

int main(void) {
    total_workers = (int)sysconf(_SC_NPROCESSORS_ONLN);
    if (total_workers < 1) total_workers = 1;

    pthread_t *threads = malloc(total_workers * sizeof(pthread_t));

    /* warmup */
    atomic_store(&next_idx, 0);
    for (int t = 0; t < total_workers; t++)
        pthread_create(&threads[t], NULL, worker, NULL);
    for (int t = 0; t < total_workers; t++)
        pthread_join(threads[t], NULL);

    /* timed run */
    atomic_store(&next_idx, 0);
    int64_t t0 = ns_now();
    for (int t = 0; t < total_workers; t++)
        pthread_create(&threads[t], NULL, worker, NULL);
    for (int t = 0; t < total_workers; t++)
        pthread_join(threads[t], NULL);
    int64_t t1 = ns_now();

    /* checksum */
    long long chk = 0;
    for (int i = 0; i < N; i++)
        chk = (chk + buf[i]) % MOD;

    int64_t ns = t1 - t0;
    printf("pool_ns=%lld\n",  (long long)ns);
    printf("workers=%d\n",    total_workers);
    printf("chunk=%d\n",      CHUNK);
    printf("checksum=%lld\n", chk);
    free(threads);
    return 0;
}
