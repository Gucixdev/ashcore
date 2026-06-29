"""
Benchmark: parse_int and hex_digits throughput.

Uses 4 distinct input strings round-robin to defeat loop-invariant code motion.

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

    var ints  = List[String]()
    ints.append(String("-12345")); ints.append(String("-99999"))
    ints.append(String("-1"));    ints.append(String("-8765432"))
    var uints = List[String]()
    uints.append(String("99999")); uints.append(String("12345"))
    uints.append(String("1"));    uints.append(String("8765432"))
    var hexs = List[String]()
    hexs.append(String("1aFf00")); hexs.append(String("DEADBE"))
    hexs.append(String("ff"));    hexs.append(String("0123456789abcdef"))

    var t0 = perf_counter_ns()
    var acc_i = Int64(0)
    for i in range(N):
        var r = parse_int(Input.from_string(ints[i & 3]))
        acc_i += r.get()
    var int_ns = perf_counter_ns() - t0

    var t1 = perf_counter_ns()
    var acc_u = UInt64(0)
    for i in range(N):
        var r = parse_uint(Input.from_string(uints[i & 3]))
        acc_u += r.get()
    var uint_ns = perf_counter_ns() - t1

    var t2 = perf_counter_ns()
    var acc_h = Int(0)
    for i in range(N):
        var r = hex_digits(Input.from_string(hexs[i & 3]))
        acc_h += r.get().byte_length()
    var hex_ns = perf_counter_ns() - t2

    print("parse_int_ns="   + String(int_ns))
    print("parse_uint_ns="  + String(uint_ns))
    print("hex_ns="         + String(hex_ns))
    print("iters="          + String(N))
    print("parse_int_per_ns="  + String(Int(int_ns)  // N))
    print("parse_uint_per_ns=" + String(Int(uint_ns) // N))
    print("hex_per_ns="        + String(Int(hex_ns)  // N))
    _ = acc_i; _ = acc_u; _ = acc_h
