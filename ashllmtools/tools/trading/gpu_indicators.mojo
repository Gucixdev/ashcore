"""tools.trading.gpu_indicators — GPU-accelerated indicator computation.

Uses ashcore.gpu (DeviceContext + kernels) to parallelize SMA and whale-move
detection over large price series. Falls back to CPU implementations from
tools.trading.indicators when no GPU is available at runtime.

Usage:
    from tools.trading.gpu_indicators import gpu_sma, gpu_whalecheck
"""

from tools.trading.parser     import parse_floats_csv
from tools.trading.indicators import _f2s, sma as _cpu_sma
from ashcore.gpu import gpu_map_f64, gpu_abs_diffs, has_gpu


# ── GPU SMA ───────────────────────────────────────────────────────────────────

def gpu_sma(prices: List[Float64], period: Int) -> List[Float64]:
    """SMA via GPU (falls back to CPU if no GPU detected at runtime)."""
    try:
        return gpu_map_f64(prices, period)
    except:
        return _cpu_sma(prices, period)


def gpu_sma_csv(prices_csv: String, period: Int) -> String:
    """Compute SMA from CSV prices, return CSV of SMA values.

    Input:  '100.5,101.2,99.8,...'
    Output: 'sma(period=N): v0,v1,v2,...'  or  'error: ...'
    """
    var prices = parse_floats_csv(prices_csv)
    if len(prices) < period:
        return "error: need at least " + String(period) + " prices for SMA"
    var vals = gpu_sma(prices, period)
    if len(vals) == 0:
        return "error: SMA computation returned empty"
    var out = String("sma(period=") + String(period) + "): "
    for i in range(len(vals)):
        if i > 0: out += ","
        out += _f2s(vals[i])
    return out


# ── GPU whalecheck ────────────────────────────────────────────────────────────

def gpu_whalecheck(prices: List[Float64]) -> String:
    """Detect whale moves (>2.5σ absolute change) using GPU abs-diff computation.

    Returns the same format as tools.trading.__init__._skill_whalecheck.
    Falls back to CPU if no GPU.
    """
    var n = len(prices)
    if n < 3:
        return "error: whalecheck needs at least 3 prices"

    # GPU-accelerated abs diffs
    var changes = List[Float64]()
    try:
        changes = gpu_abs_diffs(prices)
    except:
        for i in range(1, n):
            var d = prices[i] - prices[i-1]
            changes.append(d if d >= Float64(0) else -d)

    var m = len(changes)

    # Mean (still CPU — reduction kernel is future work)
    var mean = Float64(0)
    for i in range(m): mean += changes[i]
    mean /= Float64(m)

    # Std dev
    var variance = Float64(0)
    for i in range(m):
        var d = changes[i] - mean
        variance += d * d
    variance /= Float64(m)
    var std = variance
    if std > Float64(0):
        var x = std
        for _ in range(20): x = (x + variance / x) * Float64(0.5)
        std = x

    var threshold  = mean + Float64(2.5) * std
    var whale_bars = 0; var max_move = Float64(0); var max_price = Float64(0)
    for i in range(m):
        if changes[i] > threshold: whale_bars += 1
        if changes[i] > max_move: max_move = changes[i]; max_price = prices[i + 1]

    var backend = String("")
    try:
        backend = " backend=" + ("gpu" if has_gpu() else "cpu")
    except:
        pass

    var out = ("whale_analysis: bars=" + String(n)
               + " mean_move=" + _f2s(mean)
               + " std_move="  + _f2s(std)
               + " threshold=" + _f2s(threshold)
               + backend
               + "\nwhale_bars=" + String(whale_bars)
               + " max_move="  + _f2s(max_move)
               + " at_price="  + _f2s(max_price))
    if whale_bars > 0:
        out += "\nalert: " + String(whale_bars) + " whale move(s) detected (>2.5σ)"
    else:
        out += "\nno whale activity detected"
    return out
