---
name: price_fetch
category: trading
---

Fetch the latest market quote for a symbol via Yahoo Finance.

**Input:** ticker symbol — `AAPL`, `BTC-USD`, `ETH-USD`, `SPY`  
**Output:** `symbol=X price=Y change_pct=Z`

Falls back to `error: ...` if the network is unavailable.
