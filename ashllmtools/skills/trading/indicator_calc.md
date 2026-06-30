---
name: indicator_calc
category: trading
---

Compute a technical indicator on a price series.

**Input:** `prices:100.5,101,99.8,102  indicator:sma  period:5`  
  — or bare comma-separated CSV (defaults: sma, period 10)

**Indicators:** `sma` · `ema` · `rsi` · `macd`

**Output:** `indicator=sma period=5 last=101.46 series=100.86,...`
