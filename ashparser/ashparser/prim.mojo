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
        return ParseResult[UInt8].failure(inp, "satisfy: unexpected EOF")^
    var b = inp.peek()
    if not pred(b):
        return ParseResult[UInt8].failure(inp, "satisfy: predicate failed")^
    return ParseResult[UInt8].success(b, inp.advance(1))^


# ── byte ──────────────────────────────────────────────────────────────────────

@parameter
def byte[B: UInt8](inp: Input) -> ParseResult[UInt8]:
    """Consume exactly byte B."""
    if inp.is_empty():
        return ParseResult[UInt8].failure(inp, "byte: unexpected EOF")^
    if inp.peek() != B:
        return ParseResult[UInt8].failure(inp, "byte: no match")^
    return ParseResult[UInt8].success(B, inp.advance(1))^


# ── tag ───────────────────────────────────────────────────────────────────────

@parameter
def tag[s: StringLiteral](inp: Input) -> ParseResult[String]:
    """Consume the exact byte sequence of string literal `s`."""
    var n = s.byte_length()
    if inp.remaining() < n:
        return ParseResult[String].failure(inp, "tag: unexpected EOF")^
    var inp_ptr = inp._ptr()
    var s_ptr = s.unsafe_ptr()
    for i in range(n):
        if inp_ptr[inp.pos + i] != s_ptr[i]:
            return ParseResult[String].failure(inp, "tag: no match")^
    return ParseResult[String].success(String(s), inp.at(inp.pos + n))^


# ── take_while / take_while1 ──────────────────────────────────────────────────

@parameter
def take_while[pred: def(UInt8) capturing -> Bool](inp: Input) -> ParseResult[String]:
    """Consume bytes while pred holds.  Always succeeds (may return empty string)."""
    var pos = inp.pos
    var end = inp.len
    var ptr = inp._ptr()
    while pos < end:
        if not pred(ptr[pos]):
            break
        pos += 1
    return ParseResult[String].success(inp.slice_str(inp.pos, pos), inp.at(pos))^


@parameter
def take_while1[pred: def(UInt8) capturing -> Bool](inp: Input) -> ParseResult[String]:
    """Like take_while but fails if zero bytes matched."""
    var r = take_while[pred](inp)
    if r.rest.pos == inp.pos:
        return ParseResult[String].failure(inp, "take_while1: no bytes matched")^
    return r^


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
    return satisfy[_is_digit](inp)^

@parameter
def alpha(inp: Input) -> ParseResult[UInt8]:
    """Consume an ASCII letter a-z or A-Z."""
    return satisfy[_is_alpha](inp)^

@parameter
def alphanum(inp: Input) -> ParseResult[UInt8]:
    """Consume an ASCII letter or digit."""
    return satisfy[_is_alphanum](inp)^

@parameter
def ws(inp: Input) -> ParseResult[String]:
    """Consume zero or more whitespace bytes (space, tab, LF, CR).  Always succeeds."""
    return take_while[_is_ws](inp)^

@parameter
def digits(inp: Input) -> ParseResult[String]:
    """Consume one or more ASCII digits as a String."""
    return take_while1[_is_digit](inp)^

@parameter
def ident(inp: Input) -> ParseResult[String]:
    """Consume an identifier: alpha (alphanum | _)*.  Fails if no leading alpha."""
    if inp.is_empty() or not _is_alpha(inp.peek()):
        return ParseResult[String].failure(inp, "ident: expected letter")^
    var pos = inp.pos + 1
    var end = inp.len
    var ptr = inp._ptr()
    while pos < end:
        var b = ptr[pos]
        if not (_is_alphanum(b) or b == 95):   # 95 = '_'
            break
        pos += 1
    return ParseResult[String].success(inp.slice_str(inp.pos, pos), inp.at(pos))^


# ── eof ───────────────────────────────────────────────────────────────────────

@parameter
def eof(inp: Input) -> ParseResult[UInt8]:
    """Succeeds only at end of input.  Returns 0."""
    if not inp.is_empty():
        return ParseResult[UInt8].failure(inp, "eof: expected end of input")^
    return ParseResult[UInt8].success(0, inp)^


# ── one_of / none_of ──────────────────────────────────────────────────────────

@parameter
def one_of[chars: StringLiteral](inp: Input) -> ParseResult[UInt8]:
    """Consume current byte if it appears in `chars`."""
    if inp.is_empty():
        return ParseResult[UInt8].failure(inp, "one_of: unexpected EOF")^
    var b = inp.peek()
    var n = chars.byte_length()
    var cp = chars.unsafe_ptr()
    for i in range(n):
        if cp[i] == b:
            return ParseResult[UInt8].success(b, inp.advance(1))^
    return ParseResult[UInt8].failure(inp, "one_of: no match")^


@parameter
def none_of[chars: StringLiteral](inp: Input) -> ParseResult[UInt8]:
    """Consume current byte if it does NOT appear in `chars`."""
    if inp.is_empty():
        return ParseResult[UInt8].failure(inp, "none_of: unexpected EOF")^
    var b = inp.peek()
    var n = chars.byte_length()
    var cp = chars.unsafe_ptr()
    for i in range(n):
        if cp[i] == b:
            return ParseResult[UInt8].failure(inp, "none_of: excluded byte")^
    return ParseResult[UInt8].success(b, inp.advance(1))^


# ── line_ending / rest_of_line ────────────────────────────────────────────────

@parameter
def line_ending(inp: Input) -> ParseResult[String]:
    """Consume \\r\\n or \\n.  Returns \"\\n\"."""
    if inp.is_empty():
        return ParseResult[String].failure(inp, "line_ending: unexpected EOF")^
    if inp.peek() == 13 and inp.remaining() >= 2 and inp.peek_at(1) == 10:
        return ParseResult[String].success(String("\n"), inp.advance(2))^
    if inp.peek() == 10:
        return ParseResult[String].success(String("\n"), inp.advance(1))^
    return ParseResult[String].failure(inp, "line_ending: expected newline")^


@parameter
def rest_of_line(inp: Input) -> ParseResult[String]:
    """Consume bytes up to (not including) \\n or \\r\\n, then consume the newline.
    Returns the line content without the newline.  Always succeeds (empty at EOF)."""
    var pos = inp.pos
    var end = inp.len
    var ptr = inp._ptr()
    while pos < end and ptr[pos] != 10 and ptr[pos] != 13:
        pos += 1
    var val = inp.slice_str(inp.pos, pos)
    if pos < end and ptr[pos] == 13 and pos + 1 < end and ptr[pos + 1] == 10:
        pos += 2
    elif pos < end and ptr[pos] == 10:
        pos += 1
    return ParseResult[String].success(val, inp.at(pos))^


# ── hex_digit / hex_digits ────────────────────────────────────────────────────

@parameter
def _is_hex(b: UInt8) -> Bool:
    return (b >= 48 and b <= 57) or (b >= 65 and b <= 70) or (b >= 97 and b <= 102)


@parameter
def hex_digit(inp: Input) -> ParseResult[UInt8]:
    """Consume one hex digit 0-9 A-F a-f."""
    return satisfy[_is_hex](inp)^


@parameter
def hex_digits(inp: Input) -> ParseResult[String]:
    """Consume one or more hex digits."""
    var pos = inp.pos
    var end = inp.len
    var ptr = inp._ptr()
    while pos < end and _is_hex(ptr[pos]):
        pos += 1
    if pos == inp.pos:
        return ParseResult[String].failure(inp, "hex_digits: no hex digits")^
    return ParseResult[String].success(inp.slice_str(inp.pos, pos), inp.at(pos))^


# ── parse_uint / parse_int ────────────────────────────────────────────────────

@parameter
def parse_uint(inp: Input) -> ParseResult[UInt64]:
    """Consume one or more ASCII digits, parse as UInt64."""
    var pos = inp.pos
    var end = inp.len
    var ptr = inp._ptr()
    if pos >= end or not _is_digit(ptr[pos]):
        return ParseResult[UInt64].failure(inp, "parse_uint: no digits")^
    var val = UInt64(0)
    while pos < end and _is_digit(ptr[pos]):
        val = val * 10 + UInt64(ptr[pos]) - 48
        pos += 1
    return ParseResult[UInt64].success(val, inp.at(pos))^


@parameter
def parse_int(inp: Input) -> ParseResult[Int64]:
    """Consume optional '-' then digits, parse as Int64."""
    var pos = inp.pos
    var end = inp.len
    var ptr = inp._ptr()
    var neg = False
    if pos < end and ptr[pos] == 45:  # '-'
        neg = True
        pos += 1
    if pos >= end or not _is_digit(ptr[pos]):
        return ParseResult[Int64].failure(inp, "parse_int: expected digits")^
    var val = Int64(0)
    while pos < end and _is_digit(ptr[pos]):
        val = val * 10 + Int64(ptr[pos]) - 48
        pos += 1
    if neg:
        val = -val
    return ParseResult[Int64].success(val, inp.at(pos))^


# ── quoted_string ─────────────────────────────────────────────────────────────

@parameter
def _escape(nxt: UInt8) -> UInt8:
    if nxt == 110: return 10   # \n
    if nxt == 116: return 9    # \t
    if nxt == 114: return 13   # \r
    return nxt                 # \", \\, or pass-through


@parameter
def quoted_string(inp: Input) -> ParseResult[String]:
    """Parse a double-quoted string with \\\" and \\\\ escapes.
    Returns the content without surrounding quotes."""
    if inp.is_empty() or inp.peek() != 34:  # '"'
        return ParseResult[String].failure(inp, "quoted_string: expected '\"'")^
    var pos = inp.pos + 1
    var end = inp.len
    var ptr = inp._ptr()
    var buf = List[UInt8]()
    while pos < end:
        var b = ptr[pos]
        if b == 34:  # closing '"'
            buf.append(0)
            var s = String(StringSlice(ptr=buf.unsafe_ptr(), length=len(buf) - 1))
            return ParseResult[String].success(s, inp.at(pos + 1))^
        if b == 92 and pos + 1 < end:  # backslash
            buf.append(_escape(ptr[pos + 1])); pos += 2
        else:
            buf.append(b); pos += 1
    return ParseResult[String].failure(inp, "quoted_string: unterminated string")^
