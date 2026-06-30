---
name: backtest
category: trading
---

Run a simple SMA crossover backtest on a price series.

**Input:** `prices:100,101,99,...  fast:5  slow:20`  
  — bare CSV also accepted (default fast=5, slow=20)

**Output:** `backtest: fast=5 slow=20 bars=N trades=K pnl=X.XX`  
  Appends `(open_position)` if the last trade is still open at bar N.

**Strategy:** enter long on fast-SMA crossing above slow-SMA;
exit on fast-SMA crossing below slow-SMA. No short selling.
Open positions are marked-to-market at the last bar.
