"""
ashparser — Primitive parsers

All parsers have signature: (Input) -> ParseResult[T]

@parameter parsers take predicates or literal values as compile-time parameters.
Use `^` to move results out (ParseResult is not ImplicitlyCopyable).
"""
from ashparser.input  import Input
from ashparser.result import ParseResult


# ── satisfy ───────────────────────────────────────────────────────────────────

@parameter
def satisfy[pred: def(UInt8) capturing -> Bool](inp: Input) -> ParseResult[UInt8]:
    """Consume current byte if pred(byte) == True."""
    if inp.is_empty():
        var r = ParseResult[UInt8].failure(inp, "satisfy: unexpected EOF")
        return r^
    var b = inp.peek()
    var ok = pred(b)
    if not ok:
        var r = ParseResult[UInt8].failure(inp, "satisfy: predicate failed at pos " + String(inp.pos))
        return r^
    var r = ParseResult[UInt8].success(b, inp.advance(1))
    return r^


# ── byte ──────────────────────────────────────────────────────────────────────

@parameter
def byte[B: UInt8](inp: Input) -> ParseResult[UInt8]:
    """Consume exactly byte B."""
    if inp.is_empty():
        var r = ParseResult[UInt8].failure(inp, "byte: unexpected EOF")
        return r^
    if inp.peek() != B:
        var r = ParseResult[UInt8].failure(
            inp, "byte: expected " + String(B) + " got " + String(inp.peek())
        )
        return r^
    var r = ParseResult[UInt8].success(B, inp.advance(1))
    return r^


# ── tag ───────────────────────────────────────────────────────────────────────

@parameter
def tag[s: StringLiteral](inp: Input) -> ParseResult[String]:
    """Consume the exact byte sequence of string literal `s`."""
    var n = s.byte_length()
    if inp.remaining() < n:
        var r = ParseResult[String].failure(inp, "tag: expected '" + s + "'")
        return r^
    for i in range(n):
        if inp.peek_at(i) != UInt8(ord(s[i])):
            var r = ParseResult[String].failure(inp, "tag: expected '" + s + "'")
            return r^
    var val = String(s)
    var r = ParseResult[String].success(val, inp.advance(n))
    return r^


# ── take_while / take_while1 ──────────────────────────────────────────────────

@parameter
def take_while[pred: def(UInt8) capturing -> Bool](inp: Input) -> ParseResult[String]:
    """Consume bytes while pred holds.  Always succeeds (may return empty string)."""
    var start = inp.pos
    var cur = inp
    while not cur.is_empty():
        var ok = pred(cur.peek())
        if not ok:
            break
        cur = cur.advance(1)
    var val = inp.slice_str(start, cur.pos)
    var r = ParseResult[String].success(val, cur)
    return r^


@parameter
def take_while1[pred: def(UInt8) capturing -> Bool](inp: Input) -> ParseResult[String]:
    """Like take_while but fails if zero bytes matched."""
    var r0 = take_while[pred](inp)
    if r0.get().byte_length() == 0:
        var r = ParseResult[String].failure(inp, "take_while1: no bytes matched at pos " + String(inp.pos))
        return r^
    return r0^


# ── digit / alpha / alphanum ──────────────────────────────────────────────────

@parameter
def _is_digit(b: UInt8) -> Bool:
    return b >= 48 and b <= 57   # '0'..'9'

@parameter
def _is_alpha(b: UInt8) -> Bool:
    return (b >= 65 and b <= 90) or (b >= 97 and b <= 122)  # A-Z a-z

@parameter
def _is_alphanum(b: UInt8) -> Bool:
    return _is_digit(b) or _is_alpha(b)

@parameter
def _is_ws(b: UInt8) -> Bool:
    return b == 32 or b == 9 or b == 10 or b == 13  # space tab LF CR


@parameter
def digit(inp: Input) -> ParseResult[UInt8]:
    """Consume an ASCII digit '0'-'9'."""
    var r = satisfy[_is_digit](inp)
    return r^

@parameter
def alpha(inp: Input) -> ParseResult[UInt8]:
    """Consume an ASCII letter a-z or A-Z."""
    var r = satisfy[_is_alpha](inp)
    return r^

@parameter
def alphanum(inp: Input) -> ParseResult[UInt8]:
    """Consume an ASCII letter or digit."""
    var r = satisfy[_is_alphanum](inp)
    return r^

@parameter
def ws(inp: Input) -> ParseResult[String]:
    """Consume zero or more whitespace bytes (space, tab, LF, CR).  Always succeeds."""
    var r = take_while[_is_ws](inp)
    return r^

@parameter
def digits(inp: Input) -> ParseResult[String]:
    """Consume one or more ASCII digits as a String."""
    var r = take_while1[_is_digit](inp)
    return r^

@parameter
def ident(inp: Input) -> ParseResult[String]:
    """Consume an identifier: alpha (alphanum | _)*.  Fails if no leading alpha."""
    if inp.is_empty() or not _is_alpha(inp.peek()):
        var r = ParseResult[String].failure(inp, "ident: expected letter at pos " + String(inp.pos))
        return r^
    var start = inp.pos
    var cur = inp.advance(1)
    while not cur.is_empty():
        var b = cur.peek()
        if not (_is_alphanum(b) or b == 95):   # 95 = '_'
            break
        cur = cur.advance(1)
    var val = inp.slice_str(start, cur.pos)
    var r = ParseResult[String].success(val, cur)
    return r^


# ── eof ───────────────────────────────────────────────────────────────────────

@parameter
def eof(inp: Input) -> ParseResult[UInt8]:
    """Succeeds only at end of input.  Returns 0."""
    if not inp.is_empty():
        var r = ParseResult[UInt8].failure(
            inp, "eof: expected end, got " + String(inp.peek()) + " at pos " + String(inp.pos)
        )
        return r^
    var r = ParseResult[UInt8].success(0, inp)
    return r^


# ── one_of / none_of ──────────────────────────────────────────────────────────

@parameter
def one_of[chars: StringLiteral](inp: Input) -> ParseResult[UInt8]:
    """Consume current byte if it appears in `chars`."""
    if inp.is_empty():
        var r = ParseResult[UInt8].failure(inp, "one_of: unexpected EOF")
        return r^
    var b = inp.peek()
    var n = chars.byte_length()
    for i in range(n):
        if UInt8(ord(chars[i])) == b:
            var r = ParseResult[UInt8].success(b, inp.advance(1))
            return r^
    var r = ParseResult[UInt8].failure(inp, "one_of: no match at pos " + String(inp.pos))
    return r^


@parameter
def none_of[chars: StringLiteral](inp: Input) -> ParseResult[UInt8]:
    """Consume current byte if it does NOT appear in `chars`."""
    if inp.is_empty():
        var r = ParseResult[UInt8].failure(inp, "none_of: unexpected EOF")
        return r^
    var b = inp.peek()
    var n = chars.byte_length()
    for i in range(n):
        if UInt8(ord(chars[i])) == b:
            var r = ParseResult[UInt8].failure(inp, "none_of: excluded byte at pos " + String(inp.pos))
            return r^
    var r = ParseResult[UInt8].success(b, inp.advance(1))
    return r^


# ── line_ending / rest_of_line ────────────────────────────────────────────────

@parameter
def line_ending(inp: Input) -> ParseResult[String]:
    """Consume \\r\\n or \\n.  Returns \"\\n\"."""
    if inp.is_empty():
        var r = ParseResult[String].failure(inp, "line_ending: unexpected EOF")
        return r^
    if inp.peek() == 13 and inp.remaining() >= 2 and inp.peek_at(1) == 10:
        var r = ParseResult[String].success(String("\n"), inp.advance(2))
        return r^
    if inp.peek() == 10:
        var r = ParseResult[String].success(String("\n"), inp.advance(1))
        return r^
    var r = ParseResult[String].failure(inp, "line_ending: expected newline at pos " + String(inp.pos))
    return r^


@parameter
def rest_of_line(inp: Input) -> ParseResult[String]:
    """Consume bytes up to (not including) \\n or \\r\\n, then consume the newline.
    Returns the line content without the newline.  Always succeeds (empty at EOF)."""
    var cur = inp
    while not cur.is_empty() and cur.peek() != 10 and cur.peek() != 13:
        cur = cur.advance(1)
    var val = inp.slice_str(inp.pos, cur.pos)
    if not cur.is_empty() and cur.peek() == 13 and cur.remaining() >= 2 and cur.peek_at(1) == 10:
        cur = cur.advance(2)
    elif not cur.is_empty() and cur.peek() == 10:
        cur = cur.advance(1)
    var r = ParseResult[String].success(val, cur)
    return r^


# ── hex_digit / hex_digits ────────────────────────────────────────────────────

@parameter
def _is_hex(b: UInt8) -> Bool:
    return (b >= 48 and b <= 57) or (b >= 65 and b <= 70) or (b >= 97 and b <= 102)


@parameter
def hex_digit(inp: Input) -> ParseResult[UInt8]:
    """Consume one hex digit 0-9 A-F a-f."""
    var r = satisfy[_is_hex](inp)
    return r^


@parameter
def hex_digits(inp: Input) -> ParseResult[String]:
    """Consume one or more hex digits."""
    var r = take_while1[_is_hex](inp)
    return r^


# ── parse_uint / parse_int ────────────────────────────────────────────────────

@parameter
def parse_uint(inp: Input) -> ParseResult[UInt64]:
    """Consume one or more ASCII digits, parse as UInt64."""
    var r = digits(inp)
    if not r.ok:
        var out = ParseResult[UInt64].failure(inp, "parse_uint: no digits at pos " + String(inp.pos))
        return out^
    var s = r.get()
    var val = UInt64(0)
    var n = s.byte_length()
    var p = s.unsafe_ptr()
    for i in range(n):
        val = val * 10 + UInt64(Int(p[i]) - 48)
    _ = s
    var out = ParseResult[UInt64].success(val, r.rest)
    return out^


@parameter
def parse_int(inp: Input) -> ParseResult[Int64]:
    """Consume optional '-' then digits, parse as Int64."""
    var neg = False
    var cur = inp
    if not cur.is_empty() and cur.peek() == 45:
        neg = True
        cur = cur.advance(1)
    var r = digits(cur)
    if not r.ok:
        var out = ParseResult[Int64].failure(inp, "parse_int: expected digits at pos " + String(inp.pos))
        return out^
    var s = r.get()
    var val = Int64(0)
    var n = s.byte_length()
    var p = s.unsafe_ptr()
    for i in range(n):
        val = val * 10 + Int64(Int(p[i]) - 48)
    _ = s
    if neg:
        val = -val
    var out = ParseResult[Int64].success(val, r.rest)
    return out^


# ── quoted_string ─────────────────────────────────────────────────────────────

@parameter
def quoted_string(inp: Input) -> ParseResult[String]:
    """Parse a double-quoted string with \\\" and \\\\ escapes.
    Returns the content without surrounding quotes."""
    if inp.is_empty() or inp.peek() != 34:
        var r = ParseResult[String].failure(inp, "quoted_string: expected '\"' at pos " + String(inp.pos))
        return r^
    var cur = inp.advance(1)
    var val = String("")
    while not cur.is_empty():
        var b = cur.peek()
        if b == 34:
            var r = ParseResult[String].success(val, cur.advance(1))
            return r^
        if b == 92 and cur.remaining() >= 2:
            var nxt = cur.peek_at(1)
            if nxt == 34:
                val += String("\"")
                cur = cur.advance(2)
            elif nxt == 92:
                val += String("\\")
                cur = cur.advance(2)
            elif nxt == 110:
                val += String("\n")
                cur = cur.advance(2)
            elif nxt == 116:
                val += String("\t")
                cur = cur.advance(2)
            elif nxt == 114:
                val += String("\r")
                cur = cur.advance(2)
            else:
                val += inp.slice_str(cur.pos + 1, cur.pos + 2)
                cur = cur.advance(2)
        else:
            val += inp.slice_str(cur.pos, cur.pos + 1)
            cur = cur.advance(1)
    var r = ParseResult[String].failure(inp, "quoted_string: unterminated string")
    return r^
