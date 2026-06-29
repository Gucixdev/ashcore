/*
 * Benchmark: pthreads — parallel computation over 1M items with 6 workers.
 * Each task computes i*i mod 1e9+7. Uses an atomic counter for work-sharing,
 * matching AshCore's ThreadPool design exactly.
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>
#include <stdatomic.h>
#include <time.h>
#include <sys/sysinfo.h>

#define MOD 1000000007

static long ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000000000L + ts.tv_nsec;
}

static int          N;
static int         *buf;
static atomic_int   next_idx;

static void *worker(void *arg) {
    (void)arg;
    for (;;) {
        int i = atomic_fetch_add(&next_idx, 1);
        if (i >= N) break;
        buf[i] = (int)(((long long)i * i) % MOD);
    }
    return NULL;
}

int main(void) {
    N = 1000000;
    int nw = get_nprocs();
    if (nw < 1) nw = 1;

    buf = malloc(N * sizeof(int));
    if (!buf) { fputs("OOM\n", stderr); return 1; }

    pthread_t *threads = malloc(nw * sizeof(pthread_t));

    /* warm up */
    atomic_store(&next_idx, N - 1000);
    for (int i = 0; i < nw; i++) pthread_create(&threads[i], NULL, worker, NULL);
    for (int i = 0; i < nw; i++) pthread_join(threads[i], NULL);

    atomic_store(&next_idx, 0);
    long t0 = ns();
    for (int i = 0; i < nw; i++) pthread_create(&threads[i], NULL, worker, NULL);
    for (int i = 0; i < nw; i++) pthread_join(threads[i], NULL);
    long t1 = ns();

    long long chk = 0;
    for (int i = 0; i < N; i++) chk = (chk + buf[i]) % MOD;

    printf("pool_ns=%ld\n",   t1 - t0);
    printf("workers=%d\n",    nw);
    printf("n=%d\n",          N);
    printf("checksum=%lld\n", chk);

    free(buf); free(threads);
    return 0;
}
