"""
Stress: parse → reconstruct → re-parse, verify identity.
Parses CSV, reconstructs the line, parses again — must produce identical fields.
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
def field(inp: Input) -> ParseResult[String]:
    var r = take_while[_not_comma](inp)
    return r^

@parameter
def comma(inp: Input) -> ParseResult[UInt8]:
    var r = byte[UInt8(44)](inp)
    return r^


def rejoin(fields: List[String]) -> String:
    var out = String()
    for i in range(len(fields)):
        if i > 0:
            out += String(",")
        out += fields[i]
    return out


def main() raises:
    var lines = List[String]()
    lines.append(String("alpha,bravo,charlie"))
    lines.append(String("a,b,c,d,e,f,g"))
    lines.append(String("one"))
    lines.append(String("x,y"))
    lines.append(String("hello world,foo bar,baz"))

    var failures = 0

    for li in range(len(lines)):
        var original = lines[li]

        # First parse
        var r1 = sep_by[String, UInt8, field, comma](Input.from_string(original))
        if not r1.ok:
            print("FAIL: first parse of: " + original)
            failures += 1
            continue

        # Reconstruct
        var reconstructed = rejoin(r1.get())

        # Second parse
        var r2 = sep_by[String, UInt8, field, comma](Input.from_string(reconstructed))
        if not r2.ok:
            print("FAIL: second parse of: " + reconstructed)
            failures += 1
            continue

        # Compare field counts and values
        if len(r1.get()) != len(r2.get()):
            print("FAIL: field count mismatch for: " + original)
            failures += 1
            continue

        var mismatch = False
        for i in range(len(r1.get())):
            if r1.get()[i] != r2.get()[i]:
                print("FAIL: field[" + String(i) + "] mismatch: "
                    + r1.get()[i] + " != " + r2.get()[i])
                mismatch = True
        if mismatch:
            failures += 1

    if failures == 0:
        print("result=OK")
    else:
        print("result=FAIL")
