"""
ashparser example: full JSON parser (RFC 8259).

null | true | false | number (int/float/scientific) | string | array | object
Recursive descent — json_value/json_array/json_object call each other.
Output type is String (re-serialized JSON) — sidesteps recursive value types.
"""
from ashparser.input     import Input
from ashparser.sourcemap import SourceMap
from ashparser.prim   import tag, ws, quoted_string
from ashparser.result import ParseResult


# ── number ────────────────────────────────────────────────────────────────────

def _jnum(inp: Input) -> ParseResult[String]:
    var p = inp.pos
    var e = inp.len
    var ptr = inp._ptr()
    if p < e and ptr[p] == 45:
        p += 1                                          # optional '-'
    if p >= e or ptr[p] < 48 or ptr[p] > 57:
        var r = ParseResult[String].failure(inp, "number: expected digit")
        return r^
    if ptr[p] == 48:
        p += 1                                          # lone '0'
    else:
        while p < e and ptr[p] >= 48 and ptr[p] <= 57:
            p += 1
    if p < e and ptr[p] == 46:                         # '.' fraction
        p += 1
        if p >= e or ptr[p] < 48 or ptr[p] > 57:
            var r = ParseResult[String].failure(inp, "number: bad frac")
            return r^
        while p < e and ptr[p] >= 48 and ptr[p] <= 57:
            p += 1
    if p < e and (ptr[p] == 101 or ptr[p] == 69):     # 'e'/'E' exponent
        p += 1
        if p < e and (ptr[p] == 43 or ptr[p] == 45):
            p += 1
        if p >= e or ptr[p] < 48 or ptr[p] > 57:
            var r = ParseResult[String].failure(inp, "number: bad exp")
            return r^
        while p < e and ptr[p] >= 48 and ptr[p] <= 57:
            p += 1
    var r = ParseResult[String].success(inp.slice_str(inp.pos, p), inp.at(p))
    return r^


# ── value / array / object (mutually recursive) ───────────────────────────────

def json_value(inp: Input) -> ParseResult[String]:
    var c = ws(inp).rest
    var b = c.peek()
    if b == 110: return tag["null"](c)^             # 'n'
    if b == 116: return tag["true"](c)^             # 't'
    if b == 102: return tag["false"](c)^            # 'f'
    if b == 91:  return json_array(c)^              # '['
    if b == 123: return json_object(c)^             # '{'
    if b == 34:                                      # '"'
        var r = quoted_string(c)
        if not r.ok:
            var e = ParseResult[String].failure(inp, r.msg)
            return e^
        var e = ParseResult[String].success('"' + r.get() + '"', r.rest)
        return e^
    if b == 45 or (b >= 48 and b <= 57):            # '-' or digit
        return _jnum(c)^
    var e = ParseResult[String].failure(inp, "json_value: unexpected byte " + String(Int(b)))
    return e^


def json_array(inp: Input) -> ParseResult[String]:
    if inp.peek() != 91:
        var e = ParseResult[String].failure(inp, "expected '['")
        return e^
    var cur = ws(inp.advance(1)).rest
    var out = String("[")
    var need_sep = False
    while True:
        if cur.peek() == 93:                         # ']'
            var e = ParseResult[String].success(out + "]", cur.advance(1))
            return e^
        if need_sep:
            if cur.peek() != 44:
                var e = ParseResult[String].failure(inp, "expected ','")
                return e^
            cur = ws(cur.advance(1)).rest
            out += ", "
        var r = json_value(cur)
        if not r.ok:
            var e = ParseResult[String].failure(inp, r.msg)
            return e^
        out += r.get()
        need_sep = True
        cur = ws(r.rest).rest


def json_object(inp: Input) -> ParseResult[String]:
    if inp.peek() != 123:
        var e = ParseResult[String].failure(inp, "expected '{'")
        return e^
    var cur = ws(inp.advance(1)).rest
    var out = String("{")
    var need_sep = False
    while True:
        if cur.peek() == 125:                        # '}'
            var e = ParseResult[String].success(out + "}", cur.advance(1))
            return e^
        if need_sep:
            if cur.peek() != 44:
                var e = ParseResult[String].failure(inp, "expected ','")
                return e^
            cur = ws(cur.advance(1)).rest
            out += ", "
        var rk = quoted_string(cur)
        if not rk.ok:
            var e = ParseResult[String].failure(inp, "expected key string")
            return e^
        cur = ws(rk.rest).rest
        if cur.peek() != 58:                         # ':'
            var e = ParseResult[String].failure(inp, "expected ':'")
            return e^
        cur = ws(cur.advance(1)).rest
        var rv = json_value(cur)
        if not rv.ok:
            var e = ParseResult[String].failure(inp, rv.msg)
            return e^
        out += '"' + rk.get() + '": ' + rv.get()
        need_sep = True
        cur = ws(rv.rest).rest


# ── main ──────────────────────────────────────────────────────────────────────

def _run(label: String, src: String) raises:
    print("── " + label + " " + String("─") * (50 - len(label)))
    print("in : " + src)
    var inp = Input.from_string(src)
    var r   = json_value(inp)
    if r.ok:
        print("out: " + r.get())
    else:
        print("ERR: " + r.message_ctx_fast(SourceMap(inp)))
    print("")


def main() raises:
    _run("API response", '{"id":42,"name":"ashparser","stable":true,"score":-3.14,'
         '"tags":["mojo","parsing","zero-copy"],"meta":{"author":"drbongo","year":2025}}')
    _run("nested arrays",  '[[1,2,3],[true,null,false],["a","b"]]')
    _run("all number kinds", '[0,-99,3.14,-2.718e+10,1E100]')
    _run("empty containers", '[{},[],{"x":[]}]')
    _run("error: bad value", '{"key":INVALID}')
