"""
Stress: parse 10k CSV rows from a single large string.
Builds the buffer once, then scans line-by-line via Input cursor.
Output: result=OK or result=FAIL
"""
from ashparser.input  import Input
from ashparser.prim   import take_while, byte
from ashparser.comb   import sep_by
from ashparser.result import ParseResult


@parameter
def _not_comma(b: UInt8) -> Bool:
    return b != 44 and b != 10 and b != 13

@parameter
def _not_newline(b: UInt8) -> Bool:
    return b != 10 and b != 13

@parameter
def field(inp: Input) -> ParseResult[String]:
    var r = take_while[_not_comma](inp)
    return r^

@parameter
def comma(inp: Input) -> ParseResult[UInt8]:
    var r = byte[UInt8(44)](inp)
    return r^


def main() raises:
    var N = 10_000

    # Build buffer as List[UInt8]
    var template = String("alpha,bravo,charlie,delta,echo\n")
    var tlen = template.byte_length()
    var buf = List[UInt8](capacity=N * tlen)
    var tp = template.unsafe_ptr()
    for _ in range(N):
        for j in range(tlen):
            buf.append(tp[j])

    var bp = buf.unsafe_ptr()
    var blen = len(buf)

    var parsed_rows = 0
    var total_fields = 0
    var pos = 0

    while pos < blen:
        # find end of line
        var end = pos
        while end < blen and bp[end] != 10 and bp[end] != 13:
            end += 1
        if end == pos:
            pos += 1
            continue

        var line_inp = Input(
            Int(bp) + pos,  # _addr offset into buffer
            0,
            end - pos
        )
        var r = sep_by[String, UInt8, field, comma](line_inp)
        if r.ok:
            parsed_rows += 1
            total_fields += len(r.get())
        pos = end + 1   # skip newline

    var ok = (parsed_rows == N) and (total_fields == N * 5)
    print("rows=" + String(parsed_rows))
    print("fields=" + String(total_fields))
    print("result=" + ("OK" if ok else "FAIL"))
