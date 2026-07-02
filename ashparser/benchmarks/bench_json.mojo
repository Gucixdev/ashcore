"""
Benchmark: JSON array parsing throughput.

Parses the same 6-element JSON array N times via sep_by[value_p, comma_ws].
Output: parse_ns=<ns>  iters=<N>  bytes_parsed=<B>
"""
from std.time import perf_counter_ns
from ashparser.input  import Input
from ashparser.prim   import tag, ws, take_while, digits, byte
from ashparser.comb   import choice, sep_by
from ashparser.result import ParseResult


@parameter
def _not_quote(b: UInt8) -> Bool:
    return b != 34

@parameter
def bool_p(inp: Input) -> ParseResult[String]:
    return choice[String, tag["true"], tag["false"]](inp)^

@parameter
def int_p(inp: Input) -> ParseResult[String]:
    return digits(inp)^

@parameter
def str_p(inp: Input) -> ParseResult[String]:
    var open = byte[UInt8(34)](inp)
    if not open.ok:
        return ParseResult[String].failure(inp, "expected '\"'")^
    var content = take_while[_not_quote](open.rest)
    var close = byte[UInt8(34)](content.rest)
    if not close.ok:
        return ParseResult[String].failure(inp, "expected closing '\"'")^
    return ParseResult[String].success(content.get(), close.rest)^

@parameter
def value_p(inp: Input) -> ParseResult[String]:
    var r1 = tag["null"](inp)
    if r1.ok: return r1^
    var r2 = bool_p(inp)
    if r2.ok: return r2^
    var r3 = int_p(inp)
    if r3.ok: return r3^
    var r4 = str_p(inp)
    if r4.ok: return r4^
    return ParseResult[String].failure(inp, "expected value")^

@parameter
def comma_ws(inp: Input) -> ParseResult[UInt8]:
    var r1 = byte[UInt8(44)](inp)
    if not r1.ok:
        return ParseResult[UInt8].failure(inp, r1.msg)^
    return ParseResult[UInt8].success(r1.get(), ws(r1.rest).rest)^


def main() raises:
    var N = 50_000
    var src = String("""[1, true, null, "hello", 42, false]""")
    var src_bytes = src.byte_length()

    var ok_count = 0
    var t0 = perf_counter_ns()

    for _ in range(N):
        var inp = Input.from_string(src)
        var open = byte[UInt8(91)](inp)
        if not open.ok:
            continue
        var r1 = ws(open.rest)
        var items = sep_by[String, UInt8, value_p, comma_ws](r1.rest)
        if items.ok and len(items.get()) == 6:
            ok_count += 1

    var parse_ns = perf_counter_ns() - t0
    print("parse_ns=" + String(parse_ns))
    print("iters=" + String(ok_count))
    print("bytes_parsed=" + String(ok_count * src_bytes))
    print("correct=" + String(ok_count == N))
