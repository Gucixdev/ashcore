"""
ashparser example: parse a flat YAML block mapping.

  name: ashparser
  version: 1
  author: drbongo

Parses "key: value" lines; value is the rest of the line (trimmed).
Skips comment and blank lines.
"""
from ashparser.input  import Input
from ashparser.prim   import ident, ws, take_while, byte
from ashparser.result import ParseResult


@parameter
def _not_newline(b: UInt8) -> Bool:
    return b != 10 and b != 13


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


# Return trimmed length (drop trailing spaces/tabs).
def rtrim_len(s: String) -> Int:
    var n = s.byte_length()
    while n > 0:
        var b = s.unsafe_ptr()[n - 1]
        if b == 32 or b == 9:
            n -= 1
        else:
            break
    return n


def main() raises:
    var src = String(
        "# ashparser config\n"
        "name: ashparser\n"
        "version: 1\n"
        "author: drbongo\n"
        "license: MIT\n"
        "\n"
        "# build settings\n"
        "debug: false\n"
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

        var colon = byte[UInt8(58)](rk.rest)   # ':'
        if not colon.ok:
            inp = consume_newline(skip_line(cur)); continue

        var rws2 = ws(colon.rest)
        var rval = take_while[_not_newline](rws2.rest)
        var raw = rval.get()

        # trim trailing spaces via StringSlice
        var vlen = rtrim_len(raw)
        var vptr = UnsafePointer[UInt8, ImmutAnyOrigin](
            unsafe_from_address=Int(raw.unsafe_ptr())
        )
        var value = String(StringSlice(ptr=vptr, length=vlen))

        print("  " + rk.get() + ": " + value)
        inp = consume_newline(rval.rest)
