"""
ashparser example: parse a flat TOML-like config.

  # comment
  name = "ashcore"
  version = 1
  debug = false

Parses key = value lines; value is a quoted string, integer, or bare word.
Skips comment and blank lines.
"""
from ashparser.input  import Input
from ashparser.prim   import ident, ws, take_while, digits, byte
from ashparser.result import ParseResult


@parameter
def _not_newline(b: UInt8) -> Bool:
    return b != 10 and b != 13

@parameter
def _not_quote(b: UInt8) -> Bool:
    return b != 34   # not '"'


def consume_newline(inp: Input) -> Input:
    if inp.is_empty():
        return inp
    var b = inp.peek()
    if b == 13:
        var n = inp.advance(1)
        if not n.is_empty() and n.peek() == 10:
            return n.advance(1)
        return n
    if b == 10:
        return inp.advance(1)
    return inp


def skip_line(inp: Input) -> Input:
    var r = take_while[_not_newline](inp)
    return r.rest


# Parse one value; returns ParseResult[String] with rest pointing past the value.
def parse_value(inp: Input) -> ParseResult[String]:
    # quoted string
    var open = byte[UInt8(34)](inp)
    if open.ok:
        var content = take_while[_not_quote](open.rest)
        var close = byte[UInt8(34)](content.rest)
        if close.ok:
            var out = ParseResult[String].success(content.get(), close.rest)
            return out^
    # integer digits
    var ri = digits(inp)
    if ri.ok:
        return ri^
    # bare word (true / false / anything up to end of line)
    var rw = take_while[_not_newline](inp)
    return rw^


def main() raises:
    var src = String(
        "# ashcore config\n"
        "name = \"ashcore\"\n"
        "version = 1\n"
        "debug = false\n"
        "author = \"drbongo\"\n"
    )
    print("input:")
    print(src)
    print("parsed key-value pairs:")

    var inp = Input.from_string(src)
    while not inp.is_empty():
        var rws = ws(inp)
        var cur = rws.rest
        if cur.is_empty():
            break
        var b = cur.peek()
        if b == 10 or b == 13:
            inp = consume_newline(cur); continue
        if b == 35:   # '#'
            inp = consume_newline(skip_line(cur)); continue

        var rk = ident(cur)
        if not rk.ok:
            inp = consume_newline(skip_line(cur)); continue

        var rws2 = ws(rk.rest)
        var eq = byte[UInt8(61)](rws2.rest)   # '='
        if not eq.ok:
            inp = consume_newline(skip_line(cur)); continue

        var rws3 = ws(eq.rest)
        var rv = parse_value(rws3.rest)
        if rv.ok:
            print("  " + rk.get() + " = " + rv.get())
            inp = consume_newline(rv.rest)
        else:
            inp = consume_newline(skip_line(cur))
