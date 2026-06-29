"""Stress: DAG re-execute 100× — results must be identical every run."""
from ashcore.reactivegraph import ReactiveGraph
from ashcore.threadpool    import ThreadPool
from std.atomic      import Atomic

def main() raises:
    comptime N: Int = 32
    var pool = ThreadPool()
    var g    = ReactiveGraph()

    for _ in range(N):
        _ = g.add_job()
    for i in range(1, N):
        g.add_dep(i, i - 1)
    g.seal()

    var mismatches = 0
    for _ in range(100):
        var counter = Atomic[DType.int64](0)

        @parameter
        def dispatch(jid: Int):
            _ = counter.fetch_add(1)

        g.execute[dispatch](pool)
        if Int(counter.load()) != N:
            mismatches += 1

    print("runs=100")
    print("mismatches=" + String(mismatches))
    if mismatches == 0:
        print("result=OK")
    else:
        print("result=FAIL_mismatches=" + String(mismatches))
