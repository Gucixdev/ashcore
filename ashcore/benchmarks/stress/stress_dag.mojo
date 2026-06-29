"""Stress: ReactiveGraph 1000 jobs, 5 layers of 200, fan-out deps."""
from ashcore.reactivegraph import ReactiveGraph
from ashcore.threadpool    import ThreadPool
from std.atomic      import Atomic

def main() raises:
    comptime LAYERS: Int = 5
    comptime PER:    Int = 200
    comptime N:      Int = LAYERS * PER
    var pool = ThreadPool()
    var g    = ReactiveGraph()

    var ids = List[Int](capacity=N)
    ids.resize(N, 0)
    for k in range(N):
        ids[k] = g.add_job()

    for layer in range(1, LAYERS):
        for j in range(PER):
            var jid = layer * PER + j
            for prev in range(PER):
                g.add_dep(jid, (layer - 1) * PER + prev)

    g.seal()

    var counter = Atomic[DType.int64](0)

    @parameter
    def dispatch(jid: Int):
        _ = counter.fetch_add(1)

    g.execute[dispatch](pool)
    var run1 = Int(counter.load())

    counter.store(Int64(0))   # exact reset — avoids fetch_add(-run1) masking bug
    g.execute[dispatch](pool)
    var run2 = Int(counter.load())

    print("n_jobs="    + String(N))
    print("run1="      + String(run1))
    print("run2="      + String(run2))
    if run1 == N and run2 == N:
        print("result=OK")
    else:
        print("result=FAIL run1=" + String(run1) + " run2=" + String(run2))
