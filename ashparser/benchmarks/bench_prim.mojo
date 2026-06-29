"""
Benchmark: primitive parser microbenchmarks.

Measures the cost of individual parsers on a fixed input string.
Output: digits_ns=<ns>  ident_ns=<ns>  take_while_ns=<ns>  N=<iters>
"""
from std.time import perf_counter_ns
from ashparser.input  import Input
from ashparser.prim   import digits, ident, take_while, _is_alpha


def main() raises:
    var N = 1_000_000

    # digits benchmark
    var s_digits = String("12345rest")
    var t0 = perf_counter_ns()
    var acc_d = Int(0)
    for _ in range(N):
        var r = digits(Input.from_string(s_digits))
        acc_d += r.rest.pos
    var digits_ns = perf_counter_ns() - t0
    _ = acc_d

    # ident benchmark
    var s_ident = String("foo_bar123rest")
    t0 = perf_counter_ns()
    var acc_id = Int(0)
    for _ in range(N):
        var r = ident(Input.from_string(s_ident))
        acc_id += r.rest.pos
    var ident_ns = perf_counter_ns() - t0
    _ = acc_id

    # take_while benchmark (force String extraction to measure real cost)
    var s_tw = String("abcdefghijklmnopqrstuvwxyz123")
    t0 = perf_counter_ns()
    var acc_tw = Int(0)
    for _ in range(N):
        var r = take_while[_is_alpha](Input.from_string(s_tw))
        acc_tw += r.get().byte_length()
    var tw_ns = perf_counter_ns() - t0
    _ = acc_tw

    print("N=" + String(N))
    print("digits_ns=" + String(digits_ns))
    print("ident_ns=" + String(ident_ns))
    print("take_while_ns=" + String(tw_ns))
    print("digits_per_ns=" + String(digits_ns // N))
    print("ident_per_ns=" + String(ident_ns // N))
    print("take_while_per_ns=" + String(tw_ns // N))
