/*
 * Benchmark: Parallel reduction — sum 1M int64_t values.
 * Same algorithm as bench_reduce.mojo: per-thread partial, tree-merge.
 * Compile: gcc -O2 -o bench_reduce bench_reduce.c -lpthread
 */
#include <stdio.h>
#include <stdint.h>
#include <pthread.h>
#include <time.h>
#include <unistd.h>

#define N       1000000
#define MAX_W   256

static int64_t  data[N];
static int64_t  partials[MAX_W];
static int      W;

static int64_t ns_now(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (int64_t)ts.tv_sec * 1000000000LL + ts.tv_nsec;
}

typedef struct { int tid; int start; int stop; } WorkArg;
static WorkArg args[MAX_W];

static void *reduce_slice(void *arg) {
    WorkArg *a = (WorkArg *)arg;
    int64_t acc = 0;
    for (int i = a->start; i < a->stop; i++)
        acc += data[i];
    partials[a->tid] = acc;
    return NULL;
}

int main(void) {
    /* detect core count */
    W = (int)sysconf(_SC_NPROCESSORS_ONLN);
    if (W > MAX_W) W = MAX_W;
    if (W < 1)     W = 1;

    for (int i = 0; i < N; i++)
        data[i] = (int64_t)i;

    /* warmup */
    volatile int64_t warmup = 0;
    for (int i = 0; i < N; i++) warmup += data[i];
    (void)warmup;

    pthread_t threads[MAX_W];
    int chunk = N / W;

    int64_t t0 = ns_now();

    for (int t = 0; t < W; t++) {
        args[t].tid   = t;
        args[t].start = t * chunk;
        args[t].stop  = (t == W - 1) ? N : args[t].start + chunk;
        pthread_create(&threads[t], NULL, reduce_slice, &args[t]);
    }
    for (int t = 0; t < W; t++)
        pthread_join(threads[t], NULL);

    int64_t total = 0;
    for (int t = 0; t < W; t++)
        total += partials[t];

    int64_t t1 = ns_now();
    int64_t ns = t1 - t0;

    int64_t expected = (int64_t)N * (int64_t)(N - 1) / 2;

    printf("reduce_ns=%lld\n",   (long long)ns);
    printf("workers=%d\n",       W);
    printf("n=%d\n",             N);
    printf("result=%lld\n",      (long long)total);
    printf("expected=%lld\n",    (long long)expected);
    printf("correct=%s\n",       total == expected ? "True" : "False");
    printf("per_elem_ps=%lld\n", (long long)((ns * 1000) / N));
    return 0;
}
