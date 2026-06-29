"""
ashparser example: zero-copy HTTP/1.1 request-line + header parsing.

Parses the following wire format (CRLF terminated) from a byte buffer:

    METHOD SP request-target SP HTTP/1.1 CRLF
    field-name ":" OWS field-value OWS CRLF
    ...
    CRLF                              ← end of headers

All returned strings are slices over the original buffer — no heap copies.
Bytes past the header block are left unconsumed in `rest` for the body reader.

Example input (\\r\\n shown explicitly):
    GET /api/v1/users HTTP/1.1\\r\\n
    Host: example.com\\r\\n
    Content-Type: application/json\\r\\n
    Content-Length: 42\\r\\n
    \\r\\n
"""
from ashparser.input  import Input
from ashparser.prim   import tag, take_while, take_while1, byte, satisfy
from ashparser.result import ParseResult


# ── byte predicates ───────────────────────────────────────────────────────────

@parameter
def _is_token(b: UInt8) -> Bool:
    """RFC 9110 token char: visible ASCII except delimiters."""
    if b <= 32 or b == 127:
        return False
    # delimiters: ( ) < > @ , ; : \ " / [ ] ? = { }
    alias DELIMS = String("()<>@,;:\\\"/[]?={}")
    var ptr = DELIMS.unsafe_ptr()
    for i in range(len(DELIMS)):
        if ptr[i] == b:
            return False
    return True


@parameter
def _is_field_value(b: UInt8) -> Bool:
    """Visible ASCII or horizontal tab — field-value content."""
    return b >= 32 and b != 127


@parameter
def _is_ows(b: UInt8) -> Bool:
    return b == 32 or b == 9   # SP or HTAB


@parameter
def _not_cr(b: UInt8) -> Bool:
    return b != 13   # stop at CR


# ── CR LF ─────────────────────────────────────────────────────────────────────

@parameter
def crlf(inp: Input) -> ParseResult[UInt8]:
    var r1 = byte[UInt8(13)](inp)   # CR
    if not r1.ok:
        var out = ParseResult[UInt8].failure(inp, "expected CR"); return out^
    var r2 = byte[UInt8(10)](r1.rest)   # LF
    if not r2.ok:
        var out = ParseResult[UInt8].failure(inp, "expected LF"); return out^
    var out = ParseResult[UInt8].success(UInt8(10), r2.rest); return out^


# ── optional whitespace ────────────────────────────────────────────────────────

@parameter
def ows(inp: Input) -> ParseResult[String]:
    var r = take_while[_is_ows](inp); return r^


# ── request line ──────────────────────────────────────────────────────────────

struct RequestLine(Copyable, Movable, ImplicitlyDeletable):
    var method:  String
    var target:  String
    var version: String


@parameter
def request_line(inp: Input) -> ParseResult[RequestLine]:
    # METHOD
    var rm = take_while1[_is_token](inp)
    if not rm.ok:
        var out = ParseResult[RequestLine].failure(inp, "expected method"); return out^

    var sp1 = byte[UInt8(32)](rm.rest)   # SP
    if not sp1.ok:
        var out = ParseResult[RequestLine].failure(inp, "expected SP after method"); return out^

    # request-target (everything up to next SP)
    var rt = take_while1[_not_cr](sp1.rest)
    if not rt.ok:
        var out = ParseResult[RequestLine].failure(inp, "expected request-target"); return out^

    # Trim trailing SP to split off HTTP version
    var raw = rt.get()
    var sp_pos = -1
    for i in range(len(raw) - 1, -1, -1):
        if raw.unsafe_ptr()[i] == 32:
            sp_pos = i
            break
    if sp_pos < 0:
        var out = ParseResult[RequestLine].failure(inp, "expected HTTP version"); return out^

    var target  = raw[:sp_pos]
    var version = raw[sp_pos + 1:]

    var rl = ParseResult[RequestLine]
    var cr = crlf(rt.rest)
    if not cr.ok:
        var out = ParseResult[RequestLine].failure(inp, cr.msg); return out^

    var val = RequestLine(method=rm.get(), target=target, version=version)
    var out = ParseResult[RequestLine].success(val^, cr.rest); return out^


# ── single header field ───────────────────────────────────────────────────────

struct Header(Copyable, Movable, ImplicitlyDeletable):
    var name:  String
    var value: String


@parameter
def header_field(inp: Input) -> ParseResult[Header]:
    # field-name
    var rn = take_while1[_is_token](inp)
    if not rn.ok:
        var out = ParseResult[Header].failure(inp, "expected header name"); return out^

    var colon = byte[UInt8(58)](rn.rest)   # ':'
    if not colon.ok:
        var out = ParseResult[Header].failure(inp, "expected ':'"); return out^

    # optional whitespace, value, optional whitespace
    var lo  = ows(colon.rest)
    var rv  = take_while[_is_field_value](lo.rest)
    var ro  = ows(rv.rest)
    var cr  = crlf(ro.rest)
    if not cr.ok:
        var out = ParseResult[Header].failure(inp, "expected CRLF after header"); return out^

    var h   = Header(name=rn.get(), value=rv.get())
    var out = ParseResult[Header].success(h^, cr.rest); return out^


# ── header block ─────────────────────────────────────────────────────────────

struct HttpRequest(Copyable, Movable, ImplicitlyDeletable):
    var line:    RequestLine
    var headers: List[Header]


@parameter
def parse_request(inp: Input) -> ParseResult[HttpRequest]:
    var rl = request_line(inp)
    if not rl.ok:
        var out = ParseResult[HttpRequest].failure(inp, rl.msg); return out^

    var hdrs = List[Header]()
    var cur  = rl.rest

    while True:
        # Empty line (CRLF) signals end of headers
        var end = crlf(cur)
        if end.ok:
            var req = HttpRequest(line=rl.get(), headers=hdrs^)
            var out = ParseResult[HttpRequest].success(req^, end.rest)
            return out^
        # Try to parse one header
        var hf = header_field(cur)
        if not hf.ok:
            var out = ParseResult[HttpRequest].failure(inp, hf.msg); return out^
        hdrs.append(hf.get())
        cur = hf.rest


# ── main ──────────────────────────────────────────────────────────────────────

def main() raises:
    var raw = String(
        "POST /api/v1/upload HTTP/1.1\r\n"
        "Host: api.example.com\r\n"
        "Content-Type: application/octet-stream\r\n"
        "Content-Length: 1048576\r\n"
        "Authorization: Bearer eyJhbGciOiJSUzI1NiJ9\r\n"
        "X-Request-Id: 3f2a1b9c-dead-beef-cafe-000000000042\r\n"
        "\r\n"
    )

    print("── Raw input (" + String(len(raw)) + " bytes) ─────────────────────")
    print(raw)

    var inp = Input.from_string(raw)
    var r   = parse_request(inp)

    if not r.ok:
        print("Parse error: " + r.message_ctx(inp))
        return

    var req = r.get()
    print("── Request line ───────────────────────────────────────────────")
    print("  method  : " + req.line.method)
    print("  target  : " + req.line.target)
    print("  version : " + req.line.version)

    print("── Headers (" + String(len(req.headers)) + ") ──────────────────────────────────────")
    for i in range(len(req.headers)):
        print("  " + req.headers[i].name + ": " + req.headers[i].value)

    print("── Body starts at byte " + String(r.rest.pos) + " ─────────────────────")
    print("  (remaining: " + String(r.rest.remaining()) + " bytes)")
