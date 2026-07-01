"""tools.trading — market data, indicators, signals, portfolio, whale detection.

To add a new trading skill:
  1. Create skills/trading/<name>.md with name/category frontmatter
  2. Write _skill_<name>() below
  3. Add one line in dispatch()
"""

from tools.trading.price           import fetch_quote, fetch_close_csv
from tools.trading.indicators      import compute_indicator, _f2s, sma as _sma
from tools.trading.parser          import parse_floats_csv as _parse_csv_floats
from tools.trading.gpu_indicators  import gpu_sma_csv, gpu_whalecheck
from tools.trading.signals         import detect_signal
from tools.trading.portfolio       import portfolio_summary
from decision_contract import _contains
from skill_types import SkillResult


# ── Skill implementations ─────────────────────────────────────────────────────

def _skill_price_fetch(inp: String) -> SkillResult:
    var symbol = inp
    var n = inp.byte_length(); var ptr = inp.unsafe_ptr(); var lo = 0; var hi = n
    while lo < n and (ptr[lo] == 32 or ptr[lo] == 9): lo += 1
    while hi > lo and (ptr[hi-1] == 32 or ptr[hi-1] == 9): hi -= 1
    symbol = inp[lo:hi]
    if symbol == "": return SkillResult.failure("price_fetch: no symbol provided")
    var result = fetch_quote(symbol)
    if _contains(result, "error:"): return SkillResult.failure(result)
    return SkillResult.success(result)


def _skill_indicator_calc(inp: String) -> SkillResult:
    if inp == "": return SkillResult.failure("indicator_calc: no input")
    # GPU fast path: if input is bare CSV + indicator==sma, use GPU SMA
    if not _contains(inp, "indicator:") or _contains(inp, "indicator: sma"):
        var csv = inp
        if _contains(inp, "prices:"):
            # extract just the csv part for GPU
            var pk = String("prices:"); var pkl = pk.byte_length(); var pkp = pk.unsafe_ptr()
            var inp_n = inp.byte_length(); var inp_p = inp.unsafe_ptr()
            for i in range(inp_n - pkl + 1):
                var hit = True
                for j in range(pkl):
                    if inp_p[i+j] != pkp[j]: hit = False; break
                if hit:
                    var k = i + pkl
                    while k < inp_n and inp_p[k] == 32: k += 1
                    var end = k
                    while end < inp_n and inp_p[end] != 32: end += 1
                    csv = inp[k:end]; break
        var r = gpu_sma_csv(csv, 10)
        if not _contains(r, "error:"): return SkillResult.success(r)
        # fall through to full CPU path
    var prices_csv = inp; var indicator = String("sma"); var period = 10
    var inp_n = inp.byte_length(); var inp_p = inp.unsafe_ptr()
    if _contains(inp, "prices:"):
        var key = String("prices:"); var kl = key.byte_length(); var kp = key.unsafe_ptr()
        for i in range(inp_n - kl + 1):
            var hit = True
            for j in range(kl):
                if inp_p[i+j] != kp[j]: hit = False; break
            if hit:
                var k = i + kl
                while k < inp_n and inp_p[k] == 32: k += 1
                var end = k
                while end < inp_n and inp_p[end] != 32: end += 1
                prices_csv = inp[k:end]; break
        var key2 = String(" indicator:"); var k2l = key2.byte_length(); var k2p = key2.unsafe_ptr()
        for i in range(inp_n - k2l + 1):
            var hit = True
            for j in range(k2l):
                if inp_p[i+j] != k2p[j]: hit = False; break
            if hit:
                var k = i + k2l
                while k < inp_n and inp_p[k] == 32: k += 1
                var end = k
                while end < inp_n and inp_p[end] != 32: end += 1
                indicator = inp[k:end]; break
        var key3 = String(" period:"); var k3l = key3.byte_length(); var k3p = key3.unsafe_ptr()
        for i in range(inp_n - k3l + 1):
            var hit = True
            for j in range(k3l):
                if inp_p[i+j] != k3p[j]: hit = False; break
            if hit:
                var k = i + k3l
                while k < inp_n and inp_p[k] == 32: k += 1
                var end = k
                while end < inp_n and inp_p[end] != 32: end += 1
                var tok = inp[k:end]; var pp = tok.unsafe_ptr(); var pv = 0
                for ci in range(tok.byte_length()):
                    if pp[ci] >= 48 and pp[ci] <= 57: pv = pv * 10 + Int(pp[ci]) - 48
                if pv > 0: period = pv; break
    var result = compute_indicator(prices_csv, indicator, period)
    if _contains(result, "error:"): return SkillResult.failure(result)
    return SkillResult.success(result)


def _skill_signal_detect(inp: String) -> SkillResult:
    if inp == "": return SkillResult.failure("signal_detect: no price data provided")
    var result = detect_signal(inp)
    if _contains(result, "error:"): return SkillResult.failure(result)
    return SkillResult.success(result)


def _skill_portfolio_analyze(inp: String) -> SkillResult:
    if inp == "": return SkillResult.failure("portfolio_analyze: no portfolio data provided")
    var result = portfolio_summary(inp)
    if _contains(result, "error:"): return SkillResult.failure(result)
    return SkillResult.success(result)


def _skill_backtest(inp: String) -> SkillResult:
    if inp == "": return SkillResult.failure("backtest: no input provided")
    var prices_csv = inp; var fast_p = 5; var slow_p = 20
    var inp_n = inp.byte_length(); var inp_ptr = inp.unsafe_ptr()
    var pk = String("prices:"); var pkl = pk.byte_length(); var pkp = pk.unsafe_ptr()
    for i in range(inp_n - pkl + 1):
        var hit = True
        for j in range(pkl):
            if inp_ptr[i+j] != pkp[j]: hit = False; break
        if hit:
            var k = i + pkl; var end = k
            while end < inp_n and inp_ptr[end] != 32: end += 1
            prices_csv = inp[k:end]; break
    # fast:
    var fk = String("fast:"); var fkl = fk.byte_length(); var fkp = fk.unsafe_ptr()
    for i in range(inp_n - fkl + 1):
        var hit = True
        for j in range(fkl):
            if inp_ptr[i+j] != fkp[j]: hit = False; break
        if hit:
            var k = i + fkl; var end = k
            while end < inp_n and inp_ptr[end] != 32: end += 1
            var tok = inp[k:end]; var tp = tok.unsafe_ptr(); var tv = 0
            for ci in range(tok.byte_length()):
                if tp[ci] >= 48 and tp[ci] <= 57: tv = tv * 10 + Int(tp[ci]) - 48
            if tv > 0: fast_p = tv; break
    # slow:
    var sk = String("slow:"); var skl = sk.byte_length(); var skp = sk.unsafe_ptr()
    for i in range(inp_n - skl + 1):
        var hit = True
        for j in range(skl):
            if inp_ptr[i+j] != skp[j]: hit = False; break
        if hit:
            var k = i + skl; var end = k
            while end < inp_n and inp_ptr[end] != 32: end += 1
            var tok = inp[k:end]; var tp = tok.unsafe_ptr(); var tv = 0
            for ci in range(tok.byte_length()):
                if tp[ci] >= 48 and tp[ci] <= 57: tv = tv * 10 + Int(tp[ci]) - 48
            if tv > 0: slow_p = tv; break
    var prices = _parse_csv_floats(prices_csv); var n = len(prices)
    if n < slow_p + 2:
        return SkillResult.failure("backtest: need at least " + String(slow_p + 2) + " prices")
    var fast_vals = _sma(prices, fast_p); var slow_vals = _sma(prices, slow_p)
    var fast_len = len(fast_vals); var slow_len = len(slow_vals); var offset = fast_len - slow_len
    var trades = 0; var position = False; var entry = Float64(0); var pnl = Float64(0)
    for i in range(1, slow_len):
        var f_prev = fast_vals[offset + i - 1]; var s_prev = slow_vals[i - 1]
        var f_cur  = fast_vals[offset + i];     var s_cur  = slow_vals[i]
        if not position and f_prev <= s_prev and f_cur > s_cur:
            position = True; entry = prices[i + slow_p - 1]; trades += 1
        elif position and f_prev >= s_prev and f_cur < s_cur:
            position = False; pnl += prices[i + slow_p - 1] - entry; entry = Float64(0)
    if position: pnl += prices[n - 1] - entry
    return SkillResult.success(
        "backtest: fast=" + String(fast_p) + " slow=" + String(slow_p)
        + " bars=" + String(n) + " trades=" + String(trades)
        + " pnl=" + _f2s(pnl) + (" (open_position)" if position else "")
    )


def _skill_whalecheck(inp: String) -> SkillResult:
    """Detect anomalous price moves (>2.5σ) indicative of large-order whale activity.

    abs-diff computation runs on GPU when DeviceContext is available;
    statistical aggregation (mean/std) runs on CPU.
    """
    if inp == "": return SkillResult.failure("whalecheck: no price data provided")
    var prices = _parse_csv_floats(inp)
    var out = gpu_whalecheck(prices)
    if _contains(out, "error:"): return SkillResult.failure(out)
    return SkillResult.success(out)


def _skill_chart(inp: String) -> SkillResult:
    """Render an ASCII price chart (60×10) from comma-separated close prices."""
    if inp == "": return SkillResult.failure("chart: no price data provided")
    var prices = _parse_csv_floats(inp); var n = len(prices)
    if n < 2: return SkillResult.failure("chart: need at least 2 prices")
    alias WIDTH  = 60
    alias HEIGHT = 10
    # Range
    var lo = prices[0]; var hi = prices[0]
    for i in range(n):
        if prices[i] < lo: lo = prices[i]
        if prices[i] > hi: hi = prices[i]
    var rng = hi - lo
    if rng == Float64(0): rng = Float64(1)
    # Sample WIDTH columns (linear interpolation)
    var cols = List[Float64]()
    for c in range(WIDTH):
        var idx_f = Float64(c) * Float64(n - 1) / Float64(WIDTH - 1)
        var i0 = Int(idx_f)
        if i0 >= n - 1: i0 = n - 2
        var frac = idx_f - Float64(i0)
        cols.append(prices[i0] * (Float64(1) - frac) + prices[i0 + 1] * frac)
    # Render (row 0 = top = hi)
    var out = String("")
    for row in range(HEIGHT):
        var thresh = hi - (Float64(row) / Float64(HEIGHT - 1)) * rng
        var line = String("|")
        for c in range(WIDTH):
            line += ("*" if cols[c] >= thresh else " ")
        out += line + "|\n"
    # Bottom border
    var sep = String("+")
    for _ in range(WIDTH): sep += "-"
    out += sep + "+\n"
    out += "lo=" + _f2s(lo) + " hi=" + _f2s(hi) + " bars=" + String(n)
    return SkillResult.success(out)


# ── Dispatch ──────────────────────────────────────────────────────────────────

def dispatch(name: String, inp: String) -> SkillResult:
    if name == "price_fetch":        return _skill_price_fetch(inp)
    if name == "indicator_calc":     return _skill_indicator_calc(inp)
    if name == "signal_detect":      return _skill_signal_detect(inp)
    if name == "portfolio_analyze":  return _skill_portfolio_analyze(inp)
    if name == "backtest":           return _skill_backtest(inp)
    if name == "whalecheck":         return _skill_whalecheck(inp)
    if name == "chart":              return _skill_chart(inp)
    return SkillResult.failure("unknown trading skill: " + name)
