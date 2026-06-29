"""
ashcore example: 3-stage DAG pipeline using TaskGraph.

  A (gen)       → fill array with 1..N
  B (transform) → square each element    (waits on A)
  C (reduce)    → sum all squares        (waits on B)

TaskGraph handles topological ordering; dispatch(job_id) is called once per job.
"""
from ashcore.taskgraph import TaskGraph

def main() raises:
    var N = 100_000

    var data = List[Int](capacity=N)
    data.resize(N, 0)

    var result = List[Int](capacity=1)
    result.resize(1, 0)

    var dp = data.unsafe_ptr()
    var rp = result.unsafe_ptr()

    var g = TaskGraph()
    var A = g.add_job()   # gen
    var B = g.add_job()   # transform
    var C = g.add_job()   # reduce
    g.add_dep(B, A)
    g.add_dep(C, B)

    @parameter
    def run(jid: Int):
        if jid == A:
            for i in range(N):
                dp[i] = i + 1
        elif jid == B:
            for i in range(N):
                dp[i] = dp[i] * dp[i]
        elif jid == C:
            var acc = Int(0)
            for i in range(N):
                acc += dp[i]
            rp[0] = acc

    g.execute_serial[run]()
    _ = dp; _ = rp

    # Expected: sum of i^2 for i=1..N = N*(N+1)*(2N+1)/6
    var expected = N * (N + 1) * (2 * N + 1) // 6
    print("N        = " + String(N))
    print("result   = " + String(result[0]))
    print("expected = " + String(expected))
    print("match    = " + String(result[0] == expected))
