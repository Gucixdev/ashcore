"""tools.web.fetch — HTTP fetch via curl. Requires curl in PATH."""

from tools.sys.shell import shell_run


struct FetchResult(Copyable, ImplicitlyCopyable, Movable, ImplicitlyDeletable):
    var body:        String
    var status_code: Int
    var ok:          Bool

    def __init__(out self, body: String, status_code: Int, ok: Bool):
        self.body        = body
        self.status_code = status_code
        self.ok          = ok


def fetch_url(url: String, timeout_s: Int = 10) -> FetchResult:
    """GET a URL with curl. Returns body + HTTP status code.
    Pass only URLs you trust — do NOT pass user-supplied strings directly."""
    var r = shell_run(
        "curl -sS --max-time " + String(timeout_s)
        + " -w '\\n__STATUS__:%{http_code}' '"
        + url + "' 2>/dev/null"
    )
    if not r.ok or r.stdout == "":
        return FetchResult("", 0, False)

    # Split body from status code marker.
    var marker = String("__STATUS__:")
    var ptr    = r.stdout.unsafe_ptr()
    var bl     = r.stdout.byte_length()
    var ml     = marker.byte_length()
    var split  = bl - ml - 3   # 3-digit code before end
    var body   = String(StringSlice(ptr=ptr, length=split if split > 0 else 0))
    var code   = 0
    for i in range(3):
        var idx = bl - 3 + i
        if idx >= 0 and idx < bl:
            code = code * 10 + Int(ptr[idx]) - 48
    return FetchResult(body, code, code >= 200 and code < 300)


def fetch_json(url: String, timeout_s: Int = 10) -> String:
    """GET JSON from url. Returns raw JSON body or empty string on error."""
    var r = fetch_url(url, timeout_s)
    return r.body if r.ok else String("")
