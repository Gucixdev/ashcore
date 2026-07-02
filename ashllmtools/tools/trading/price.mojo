"""tools.trading.price — market price fetching via curl (Yahoo Finance)."""

from tools.sys.shell import shell_run


def _find_json_value(body: String, key: String) -> String:
    """Extract the first numeric value after `"key":` in a JSON body."""
    var bl  = body.byte_length()
    var kl  = key.byte_length()
    var bp  = body.unsafe_ptr()
    var kp  = key.unsafe_ptr()
    for i in range(bl - kl):
        var hit = True
        for j in range(kl):
            if bp[i + j] != kp[j]:
                hit = False
                break
        if hit:
            var k = i + kl
            while k < bl and (bp[k] == 32 or bp[k] == 58):  # space or ':'
                k += 1
            var start = k
            while k < bl and (
                (bp[k] >= 48 and bp[k] <= 57) or bp[k] == 46 or bp[k] == 45
            ):
                k += 1
            if k > start:
                return body[byte=start:k]
            break
    return String("")


def fetch_quote(symbol: String) -> String:
    """Fetch latest quote for symbol from Yahoo Finance.
    Returns 'symbol=X price=Y change_pct=Z' or 'error: ...'."""
    var r = shell_run(
        "curl -sS --max-time 8 "
        + "'https://query1.finance.yahoo.com/v8/finance/chart/"
        + symbol + "?range=1d&interval=1d' 2>/dev/null"
    )
    if not r.ok or r.stdout.byte_length() < 10:
        return "error: fetch failed for " + symbol
    var price  = _find_json_value(r.stdout, '"regularMarketPrice":')
    var change = _find_json_value(r.stdout, '"regularMarketChangePercent":')
    if price == "":
        return "error: could not parse quote for " + symbol
    var out = "symbol=" + symbol + " price=" + price
    if change != "":
        out += " change_pct=" + change
    return out


def fetch_close_csv(symbol: String, days: Int = 60) -> String:
    """Fetch daily close prices for symbol.
    Returns comma-separated floats (oldest→newest) or 'error: ...'."""
    var range_str = "3mo" if days > 30 else "1mo"
    var r = shell_run(
        "curl -sS --max-time 12 "
        + "'https://query1.finance.yahoo.com/v8/finance/chart/"
        + symbol + "?range=" + range_str + "&interval=1d' 2>/dev/null"
    )
    if not r.ok or r.stdout.byte_length() < 10:
        return "error: fetch failed for " + symbol
    # Extract the "close" array from JSON: "close":[n,n,n,...]
    var body = r.stdout
    var bl   = body.byte_length()
    var bp   = body.unsafe_ptr()
    var marker = String('"close":[')
    var ml   = marker.byte_length()
    var mp   = marker.unsafe_ptr()
    for i in range(bl - ml):
        var hit = True
        for j in range(ml):
            if bp[i + j] != mp[j]:
                hit = False
                break
        if hit:
            var k = i + ml
            var csv = String("")
            while k < bl and bp[k] != 93:  # ']'
                if bp[k] != 32 and bp[k] != 10 and bp[k] != 13:
                    csv += String(body[byte=k : k + 1])
                k += 1
            return csv
    return "error: could not parse close prices for " + symbol
