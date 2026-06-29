/*
 * C reference: pthread_mutex under the same realistic scenario.
 * 4 threads, ITERS per thread, ~50ns critical section (100-iteration loop).
 * Compare against Mojo TicketLock.
 */
#include <pthread.h>
#include <stdio.h>
#include <stdint.h>
#include <time.h>

#define WORKERS   4
#define ITERS     50000

static pthread_mutex_t mu = PTHREAD_MUTEX_INITIALIZER;
static long long counter  = 0;

static int64_t now_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (int64_t)ts.tv_sec * 1000000000LL + ts.tv_nsec;
}

static void *worker(void *arg) {
    (void)arg;
    for (int i = 0; i < ITERS; i++) {
        pthread_mutex_lock(&mu);
        volatile int acc = 0;
        for (int j = 0; j < 100; j++) acc += j;
        counter += (acc & 1);  /* prevent DCE */
        counter += 1;
        pthread_mutex_unlock(&mu);
    }
    return NULL;
}

int main(void) {
    pthread_t threads[WORKERS];
    int64_t t0 = now_ns();
    for (int i = 0; i < WORKERS; i++) pthread_create(&threads[i], NULL, worker, NULL);
    for (int i = 0; i < WORKERS; i++) pthread_join(threads[i], NULL);
    int64_t t1 = now_ns();
    int64_t ns = t1 - t0;
    long long total = (long long)WORKERS * ITERS;
    printf("lock_ns=%ld\n",   (long)ns);
    printf("per_op_ns=%ld\n", (long)(ns / total));
    printf("counter=%lld\n",  counter);
    printf("correct=%s\n",    counter == total ? "True" : "False");
    return 0;
}
