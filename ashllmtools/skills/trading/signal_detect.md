---
name: signal_detect
category: trading
---

Detect a directional trading signal from a price series using SMA crossover
and RSI overbought/oversold rules.

**Input:** comma-separated close prices (minimum slow+1 values, default slow=20)  
  `100.5,101.2,99.8,102.3,101.5,...`

**Output:** `signal=BUY|SELL|HOLD  rsi=X  sma_fast=X  sma_slow=X  reason=...`

**Reasons:** `sma_crossover_up`, `sma_crossover_down`, `oversold`, `overbought`,
  combined with `+` when multiple triggers fire, `no_trigger` when flat.
