/*
 * Benchmark: malloc/free — 1M x 64B allocs, then bulk free.
 * Equivalent to bench_arena.mojo for comparison.
 */
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

static long ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000000000L + ts.tv_nsec;
}

int main(void) {
    int N = 1000000;
    void **ptrs = malloc(N * sizeof(void *));
    if (!ptrs) { fputs("OOM\n", stderr); return 1; }

    /* warm up */
    for (int i = 0; i < 1000; i++) { void *p = malloc(64); free(p); }

    long t0 = ns();
    for (int i = 0; i < N; i++)
        ptrs[i] = malloc(64);
    long t1 = ns();
    for (int i = 0; i < N; i++)
        free(ptrs[i]);
    free(ptrs);
    long t2 = ns();

    printf("alloc_total_ns=%ld\n", t1 - t0);
    printf("free_ns=%ld\n",        t2 - t1);
    printf("per_op_ns=%ld\n",      (t1 - t0) / N);
    printf("n=%d\n",               N);
    return 0;
}
