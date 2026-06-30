"""tools.trading.signals — signal detection from price series."""

from tools.trading.indicators import (
    sma, ema, rsi, _parse_csv_floats, _f2s, _list_last,
)


def detect_signal(prices_csv: String,
                  fast: Int = 5, slow: Int = 20, rsi_period: Int = 14) -> String:
    """SMA crossover + RSI overbought/oversold signal.

    Returns: 'signal=BUY|SELL|HOLD rsi=X sma_fast=X sma_slow=X reason=...'
    """
    var prices = _parse_csv_floats(prices_csv)
    var n = len(prices)
    if n < slow + 1:
        return "error: need at least " + String(slow + 1) + " prices for slow SMA"

    var fast_vals = sma(prices, fast)
    var slow_vals = sma(prices, slow)
    var rsi_vals  = rsi(prices, rsi_period)

    var f_cur  = _list_last(fast_vals)
    var s_cur  = _list_last(slow_vals)
    var f_prev = fast_vals[len(fast_vals) - 2] if len(fast_vals) >= 2 else f_cur
    var s_prev = slow_vals[len(slow_vals) - 2] if len(slow_vals) >= 2 else s_cur
    var rsi_val = _list_last(rsi_vals)

    var signal = "HOLD"
    var reason = ""

    # Crossover
    var crossed_up   = f_prev <= s_prev and f_cur > s_cur
    var crossed_down = f_prev >= s_prev and f_cur < s_cur

    if crossed_up:
        signal = "BUY"
        reason = "sma_crossover_up"
    elif crossed_down:
        signal = "SELL"
        reason = "sma_crossover_down"

    # RSI override
    if rsi_val < Float64(30):
        if signal != "BUY":
            signal = "BUY"
        reason = reason + ("+oversold" if reason != "" else "oversold")
    elif rsi_val > Float64(70):
        if signal != "SELL":
            signal = "SELL"
        reason = reason + ("+overbought" if reason != "" else "overbought")

    if reason == "":
        reason = "no_trigger"

    return ("signal=" + signal
            + " rsi=" + _f2s(rsi_val)
            + " sma_fast=" + _f2s(f_cur)
            + " sma_slow=" + _f2s(s_cur)
            + " reason=" + reason)
