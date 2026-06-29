"""
ashparser example: parse a CSV line into fields.

  "Alice,30,Warsaw"  →  3 fields

Uses sep_by with a take_while field parser — the separator is a bare comma.
"""
from ashparser.input  import Input
from ashparser.prim   import take_while, byte
from ashparser.comb   import sep_by
from ashparser.result import ParseResult


@parameter
def _not_comma(b: UInt8) -> Bool:
    return b != 44 and b != 10 and b != 13   # not ',' '\n' '\r'


@parameter
def field(inp: Input) -> ParseResult[String]:
    var r = take_while[_not_comma](inp)
    return r^


@parameter
def comma(inp: Input) -> ParseResult[UInt8]:
    var r = byte[UInt8(44)](inp)
    return r^


def main() raises:
    var lines = List[String]()
    lines.append(String("Alice,30,Warsaw"))
    lines.append(String("Bob,25,Krakow"))
    lines.append(String("single"))
    lines.append(String("a,b,c,d,e"))

    for li in range(len(lines)):
        var line = lines[li]
        var inp = Input.from_string(line)
        var r = sep_by[String, UInt8, field, comma](inp)
        if not r.ok:
            print("  error: " + r.msg)
            continue
        var fields = r.get()
        print(line + "  →  [" + String(len(fields)) + " fields]")
        for i in range(len(fields)):
            print("    [" + String(i) + "] " + fields[i])
