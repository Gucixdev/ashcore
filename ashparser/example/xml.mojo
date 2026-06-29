"""
ashparser example: parse a self-closing XML element with attributes.

  <node id="1" name="root" active="true"/>

Prints: tag name + each attribute key-value pair.
No nesting, no text content, no CDATA.
"""
from ashparser.input  import Input
from ashparser.prim   import ident, ws, take_while, byte
from ashparser.result import ParseResult


@parameter
def _not_quote(b: UInt8) -> Bool:
    return b != 34   # not '"'


def main() raises:
    var srcs = List[String]()
    srcs.append(String("""<node id="1" name="root" active="true"/>"""))
    srcs.append(String("""<link href="https://example.com" rel="noopener"/>"""))
    srcs.append(String("""<br/>"""))

    for si in range(len(srcs)):
        var src = srcs[si]
        print("input: " + src)
        var inp = Input.from_string(src)

        var open = byte[UInt8(60)](inp)   # '<'
        if not open.ok:
            print("  error: expected '<'"); continue

        var rname = ident(open.rest)
        if not rname.ok:
            print("  error: expected tag name"); continue

        print("  tag: " + rname.get())

        var cur = rname.rest
        while True:
            var rws = ws(cur)
            var c = rws.rest
            if c.is_empty():
                break
            var b = c.peek()
            if b == 47 or b == 62:   # '/' or '>'
                break

            var rk = ident(c)
            if not rk.ok:
                break

            var eq = byte[UInt8(61)](rk.rest)   # '='
            if not eq.ok:
                break

            var open_q = byte[UInt8(34)](eq.rest)   # '"'
            if not open_q.ok:
                break

            var content = take_while[_not_quote](open_q.rest)
            var close_q = byte[UInt8(34)](content.rest)   # '"'
            if not close_q.ok:
                break

            print("  attr: " + rk.get() + " = \"" + content.get() + "\"")
            cur = close_q.rest

        var rws2 = ws(cur)
        var slash = byte[UInt8(47)](rws2.rest)
        var end_r = slash.rest if slash.ok else rws2.rest
        var gt = byte[UInt8(62)](end_r)
        if gt.ok:
            print("  (well-formed)")
        print()
