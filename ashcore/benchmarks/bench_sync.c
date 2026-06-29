/*
 * Benchmark: pthread_mutex contention — 8 threads, 100k lock/unlock pairs each.
 * Equivalent to bench_sync.mojo.
 */
#include <stdio.h>
#include <pthread.h>
#include <time.h>

static long ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000000000L + ts.tv_nsec;
}

#define WORKERS 8
#define ITERS   100000

static pthread_mutex_t mu = PTHREAD_MUTEX_INITIALIZER;
static long long counter  = 0;

static void *worker(void *arg) {
    (void)arg;
    for (int i = 0; i < ITERS; i++) {
        pthread_mutex_lock(&mu);
        counter++;
        pthread_mutex_unlock(&mu);
    }
    return NULL;
}

int main(void) {
    pthread_t threads[WORKERS];

    long t0 = ns();
    for (int i = 0; i < WORKERS; i++) pthread_create(&threads[i], NULL, worker, NULL);
    for (int i = 0; i < WORKERS; i++) pthread_join(threads[i], NULL);
    long t1 = ns();

    long total_ops = (long)WORKERS * ITERS;
    printf("lock_ns=%ld\n",   t1 - t0);
    printf("total_ops=%ld\n", total_ops);
    printf("per_op_ns=%ld\n", (t1 - t0) / total_ops);
    printf("counter=%lld\n",  counter);
    printf("workers=%d\n",    WORKERS);
    return 0;
}
