"""
ashparser example: evaluate left-to-right integer arithmetic.

  "3 + 10 * 2 - 5"  →  21
  "100 / 4 + 7"     →  32

Parses: ws? uint (ws op ws uint)* — no precedence, strictly left-to-right.
"""
from ashparser.input  import Input
from ashparser.prim   import digits, ws, satisfy
from ashparser.result import ParseResult


@parameter
def _is_op(b: UInt8) -> Bool:
    return b == 43 or b == 45 or b == 42 or b == 47   # + - * /


@parameter
def op_p(inp: Input) -> ParseResult[UInt8]:
    var r = satisfy[_is_op](inp)
    return r^


# Skip optional ws, consume op, skip optional ws; returns the op byte.
@parameter
def ws_op_ws(inp: Input) -> ParseResult[UInt8]:
    var r1 = ws(inp)
    var r2 = op_p(r1.rest)
    if not r2.ok:
        var out = ParseResult[UInt8].failure(inp, r2.msg)
        return out^
    var r3 = ws(r2.rest)
    var out = ParseResult[UInt8].success(r2.get(), r3.rest)
    return out^


def parse_uint(inp: Input) -> ParseResult[Int]:
    var r = digits(ws(inp).rest)
    if not r.ok:
        var out = ParseResult[Int].failure(inp, r.msg)
        return out^
    var s = r.get()
    var n = 0
    for i in range(s.byte_length()):
        n = n * 10 + Int(s.unsafe_ptr()[i]) - 48
    var out = ParseResult[Int].success(n, r.rest)
    return out^


def eval_expr(src: String) raises -> Int:
    var inp = Input.from_string(src)
    var r0 = parse_uint(inp)
    if not r0.ok:
        raise Error("expected number: " + r0.msg)
    var acc = r0.get()
    var cur = r0.rest
    while True:
        var rop = ws_op_ws(cur)
        if not rop.ok:
            break
        var rhs = parse_uint(rop.rest)
        if not rhs.ok:
            break
        var o = Int(rop.get())
        var v = rhs.get()
        cur = rhs.rest
        if o == 43:
            acc = acc + v
        elif o == 45:
            acc = acc - v
        elif o == 42:
            acc = acc * v
        elif o == 47:
            if v == 0:
                raise Error("division by zero")
            acc = acc // v
    return acc


def main() raises:
    var exprs = List[String]()
    exprs.append(String("3 + 10 * 2 - 5"))
    exprs.append(String("100 / 4 + 7"))
    exprs.append(String("1 + 2 + 3 + 4 + 5"))
    exprs.append(String("  42  "))

    for i in range(len(exprs)):
        var result = eval_expr(exprs[i])
        print(exprs[i] + "  =>  " + String(result))
