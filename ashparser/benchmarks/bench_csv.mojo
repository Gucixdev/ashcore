"""
Benchmark: CSV parsing throughput.

Parses the same 5-field CSV row N times via sep_by[field, comma].
Output: parse_ns=<ns>  rows=<N>  bytes_parsed=<B>
"""
from std.time import perf_counter_ns
from ashparser.input  import Input
from ashparser.prim   import take_while, byte
from ashparser.comb   import sep_by
from ashparser.result import ParseResult


@parameter
def _not_comma(b: UInt8) -> Bool:
    return b != 44 and b != 10 and b != 13

@parameter
def field(inp: Input) -> ParseResult[String]:
    var r = take_while[_not_comma](inp)
    return r^

@parameter
def comma(inp: Input) -> ParseResult[UInt8]:
    var r = byte[UInt8(44)](inp)
    return r^


def main() raises:
    var N = 200_000
    var row = String("alpha,bravo,charlie,delta,echo")
    var row_bytes = row.byte_length()

    var ok_count = 0
    var t0 = perf_counter_ns()

    for _ in range(N):
        var inp = Input.from_string(row)
        var r = sep_by[String, UInt8, field, comma](inp)
        if r.ok and len(r.get()) == 5:
            ok_count += 1

    var parse_ns = perf_counter_ns() - t0
    print("parse_ns=" + String(parse_ns))
    print("rows=" + String(ok_count))
    print("bytes_parsed=" + String(ok_count * row_bytes))
    print("correct=" + String(ok_count == N))
