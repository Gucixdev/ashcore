"""
Benchmark: parse_int and hex_digits throughput.

1M calls each: parse_int on "-12345", parse_uint on "99999", hex_digits on "1aFf00".

Output (key=value):
    parse_int_ns=<total ns for 1M calls>
    parse_uint_ns=<total ns for 1M calls>
    hex_ns=<total ns for 1M calls>
    iters=1000000
    parse_int_per_ns=<ns per call>
    parse_uint_per_ns=<ns per call>
    hex_per_ns=<ns per call>
"""
from ashparser.prim import parse_int, parse_uint, hex_digits
from ashparser.input import Input
from std.time import perf_counter_ns

def main() raises:
    var N = 1_000_000

    var s_int  = String("-12345")
    var s_uint = String("99999")
    var s_hex  = String("1aFf00")

    var t0 = perf_counter_ns()
    var dummy_i = Int64(0)
    for _ in range(N):
        var r = parse_int(Input.from_string(s_int))
        dummy_i = r.get()
    var int_ns = perf_counter_ns() - t0
    _ = dummy_i

    var t1 = perf_counter_ns()
    var dummy_u = UInt64(0)
    for _ in range(N):
        var r = parse_uint(Input.from_string(s_uint))
        dummy_u = r.get()
    var uint_ns = perf_counter_ns() - t1
    _ = dummy_u

    var t2 = perf_counter_ns()
    var dummy_h = String("")
    for _ in range(N):
        var r = hex_digits(Input.from_string(s_hex))
        dummy_h = r.get()
    var hex_ns = perf_counter_ns() - t2
    _ = dummy_h

    print("parse_int_ns="   + String(int_ns))
    print("parse_uint_ns="  + String(uint_ns))
    print("hex_ns="         + String(hex_ns))
    print("iters="          + String(N))
    print("parse_int_per_ns="  + String(Int(int_ns)  // N))
    print("parse_uint_per_ns=" + String(Int(uint_ns) // N))
    print("hex_per_ns="        + String(Int(hex_ns)  // N))
