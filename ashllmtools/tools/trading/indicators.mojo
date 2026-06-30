"""tools.trading.indicators — SMA, EMA, RSI, MACD computed in pure Mojo."""


# ── Helpers ───────────────────────────────────────────────────────────────────

def _parse_float_str(s: String) -> Float64:
    """Parse a decimal string into Float64."""
    var n   = s.byte_length()
    var ptr = s.unsafe_ptr()
    var i   = 0
    var sign = Float64(1)
    if i < n and ptr[i] == 45:   # '-'
        sign = Float64(-1)
        i += 1
    var ip = Float64(0)
    while i < n and ptr[i] >= 48 and ptr[i] <= 57:
        ip = ip * Float64(10) + Float64(Int(ptr[i]) - 48)
        i += 1
    var fp  = Float64(0)
    var fdv = Float64(1)
    if i < n and ptr[i] == 46:   # '.'
        i += 1
        while i < n and ptr[i] >= 48 and ptr[i] <= 57:
            fp  = fp * Float64(10) + Float64(Int(ptr[i]) - 48)
            fdv = fdv * Float64(10)
            i += 1
    return sign * (ip + fp / fdv)


def _parse_csv_floats(csv: String) -> List[Float64]:
    """Parse comma-separated floats (spaces around commas are OK)."""
    var result = List[Float64]()
    var n   = csv.byte_length()
    var ptr = csv.unsafe_ptr()
    var i   = 0
    while i < n:
        while i < n and (ptr[i] == 32 or ptr[i] == 9): i += 1
        var start = i
        while i < n and ptr[i] != 44:  # ','
            i += 1
        if i > start:
            var tok = csv[start:i]
            if tok.byte_length() > 0:
                result.append(_parse_float_str(tok))
        i += 1   # skip comma
    return result


def _f2s(f: Float64) -> String:
    """Float64 → string with 2 decimal places."""
    var sign = String("")
    var v = f
    if v < Float64(0):
        sign = "-"
        v = -v
    var ip = Int(v)
    var fp = Int((v - Float64(ip)) * Float64(100) + Float64(0.5))
    if fp >= 100:
        ip += 1
        fp -= 100
    var fs = String(fp)
    if fp < 10:
        fs = "0" + fs
    return sign + String(ip) + "." + fs


def _list_last(lst: List[Float64]) -> Float64:
    """Return last element or 0.0 if empty."""
    if len(lst) == 0:
        return Float64(0)
    return lst[len(lst) - 1]


# ── Indicators ────────────────────────────────────────────────────────────────

def sma(prices: List[Float64], period: Int) -> List[Float64]:
    """Simple moving average — returns len(prices)-period+1 values."""
    var result = List[Float64]()
    var n = len(prices)
    if period <= 0 or period > n:
        return result
    for i in range(period - 1, n):
        var s = Float64(0)
        for j in range(period):
            s += prices[i - period + 1 + j]
        result.append(s / Float64(period))
    return result


def ema(prices: List[Float64], period: Int) -> List[Float64]:
    """Exponential moving average."""
    var result = List[Float64]()
    var n = len(prices)
    if period <= 0 or period > n:
        return result
    var seed = Float64(0)
    for i in range(period):
        seed += prices[i]
    seed /= Float64(period)
    result.append(seed)
    var k = Float64(2) / Float64(period + 1)
    for i in range(period, n):
        seed = prices[i] * k + seed * (Float64(1) - k)
        result.append(seed)
    return result


def rsi(prices: List[Float64], period: Int = 14) -> List[Float64]:
    """Relative Strength Index (Wilder smoothing)."""
    var result = List[Float64]()
    var n = len(prices)
    if n <= period:
        return result
    var avg_gain = Float64(0)
    var avg_loss = Float64(0)
    for i in range(1, period + 1):
        var delta = prices[i] - prices[i - 1]
        if delta > Float64(0):
            avg_gain += delta
        else:
            avg_loss -= delta
    avg_gain /= Float64(period)
    avg_loss /= Float64(period)
    var rs = avg_gain / avg_loss if avg_loss > Float64(0) else Float64(100)
    result.append(Float64(100) - Float64(100) / (Float64(1) + rs))
    for i in range(period + 1, n):
        var delta = prices[i] - prices[i - 1]
        var gain  = delta if delta > Float64(0) else Float64(0)
        var loss  = -delta if delta < Float64(0) else Float64(0)
        avg_gain = (avg_gain * Float64(period - 1) + gain) / Float64(period)
        avg_loss = (avg_loss * Float64(period - 1) + loss) / Float64(period)
        rs = avg_gain / avg_loss if avg_loss > Float64(0) else Float64(100)
        result.append(Float64(100) - Float64(100) / (Float64(1) + rs))
    return result


def macd(prices: List[Float64],
         fast: Int = 12, slow: Int = 26, signal_period: Int = 9) -> String:
    """MACD line, signal line, and histogram.
    Returns 'macd=X signal=Y hist=Z' using last values."""
    var fast_ema   = ema(prices, fast)
    var slow_ema   = ema(prices, slow)
    var fast_n = len(fast_ema)
    var slow_n = len(slow_ema)
    if fast_n == 0 or slow_n == 0:
        return "error: not enough data for MACD"
    # Align: fast_ema is longer; trim to slow_ema length
    var macd_line = List[Float64]()
    var offset = fast_n - slow_n
    for i in range(slow_n):
        macd_line.append(fast_ema[offset + i] - slow_ema[i])
    var sig_line = ema(macd_line, signal_period)
    var ml = _list_last(macd_line)
    var sl = _list_last(sig_line)
    return ("macd=" + _f2s(ml)
            + " signal=" + _f2s(sl)
            + " hist=" + _f2s(ml - sl))


def compute_indicator(prices_csv: String, indicator: String, period: Int) -> String:
    """Unified entry point for skills.
    indicator: 'sma' | 'ema' | 'rsi' | 'macd'
    Returns last computed value or full series as 'last=X series=a,b,c'."""
    var prices = _parse_csv_floats(prices_csv)
    if len(prices) < 2:
        return "error: need at least 2 prices"
    if indicator == "macd":
        return macd(prices)
    var values = List[Float64]()
    if indicator == "sma":
        values = sma(prices, period)
    elif indicator == "ema":
        values = ema(prices, period)
    elif indicator == "rsi":
        values = rsi(prices, period)
    else:
        return "error: unknown indicator: " + indicator
    if len(values) == 0:
        return "error: not enough data for " + indicator + " period=" + String(period)
    var last = _list_last(values)
    var series = String("")
    for i in range(len(values)):
        if i > 0:
            series += ","
        series += _f2s(values[i])
    return ("indicator=" + indicator
            + " period=" + String(period)
            + " last=" + _f2s(last)
            + " series=" + series)
