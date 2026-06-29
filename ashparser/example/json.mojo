"""
ashparser example: parse a JSON array of scalars.

  [1, true, null, "hello"]  →  4 elements

Supported value types: null, bool (true/false), integer, quoted string.
No floats, no nested objects.
"""
from ashparser.input  import Input
from ashparser.prim   import tag, ws, take_while, digits, byte
from ashparser.comb   import choice, sep_by
from ashparser.result import ParseResult


# ── predicates ───────────────────────────────────────────────────────────────

@parameter
def _not_quote(b: UInt8) -> Bool:
    return b != 34   # not '"'


# ── atomic value parsers (all return ParseResult[String]) ────────────────────

@parameter
def null_p(inp: Input) -> ParseResult[String]:
    var r = tag["null"](inp)
    if not r.ok:
        var out = ParseResult[String].failure(inp, r.msg); return out^
    var out = ParseResult[String].success(String("null"), r.rest); return out^


@parameter
def true_p(inp: Input) -> ParseResult[String]:
    var r = tag["true"](inp)
    if not r.ok:
        var out = ParseResult[String].failure(inp, r.msg); return out^
    var out = ParseResult[String].success(String("true"), r.rest); return out^


@parameter
def false_p(inp: Input) -> ParseResult[String]:
    var r = tag["false"](inp)
    if not r.ok:
        var out = ParseResult[String].failure(inp, r.msg); return out^
    var out = ParseResult[String].success(String("false"), r.rest); return out^


@parameter
def bool_p(inp: Input) -> ParseResult[String]:
    var r = choice[String, true_p, false_p](inp); return r^


@parameter
def int_p(inp: Input) -> ParseResult[String]:
    var r = digits(inp); return r^


@parameter
def str_p(inp: Input) -> ParseResult[String]:
    var open = byte[UInt8(34)](inp)   # '"'
    if not open.ok:
        var out = ParseResult[String].failure(inp, "expected '\"'"); return out^
    var content = take_while[_not_quote](open.rest)
    var close = byte[UInt8(34)](content.rest)   # '"'
    if not close.ok:
        var out = ParseResult[String].failure(inp, "expected closing '\"'"); return out^
    var out = ParseResult[String].success(content.get(), close.rest); return out^


# ── combined value parser ─────────────────────────────────────────────────────

@parameter
def value_p(inp: Input) -> ParseResult[String]:
    var r1 = null_p(inp)
    if r1.ok:
        return r1^
    var r2 = bool_p(inp)
    if r2.ok:
        return r2^
    var r3 = int_p(inp)
    if r3.ok:
        return r3^
    var r4 = str_p(inp)
    if r4.ok:
        return r4^
    var out = ParseResult[String].failure(inp, "expected value")
    return out^


# ── comma separator (with trailing whitespace) ─────────────────────────────

@parameter
def comma_ws(inp: Input) -> ParseResult[UInt8]:
    var r1 = byte[UInt8(44)](inp)   # ','
    if not r1.ok:
        var out = ParseResult[UInt8].failure(inp, r1.msg); return out^
    var r2 = ws(r1.rest)
    var out = ParseResult[UInt8].success(r1.get(), r2.rest); return out^


# ── main ──────────────────────────────────────────────────────────────────────

def main() raises:
    var src = String("""[1, true, null, "hello", 42, false]""")
    print("input: " + src)

    var inp = Input.from_string(src)

    var open = byte[UInt8(91)](inp)   # '['
    if not open.ok:
        print("error: expected '['"); return

    var r1 = ws(open.rest)
    var items = sep_by[String, UInt8, value_p, comma_ws](r1.rest)
    if not items.ok:
        print("error: " + items.msg); return

    var r2 = ws(items.rest)
    var close = byte[UInt8(93)](r2.rest)  # ']'
    if not close.ok:
        print("error: expected ']'"); return

    var vals = items.get()
    print("parsed " + String(len(vals)) + " values:")
    for i in range(len(vals)):
        print("  [" + String(i) + "] " + vals[i])
