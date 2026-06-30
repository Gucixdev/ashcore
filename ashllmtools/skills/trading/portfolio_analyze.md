---
name: portfolio_analyze
category: trading
---

Analyze a portfolio: position count, total invested capital, cash balance,
and percentage allocation per position.

**Input:** one line per position — `SYMBOL  QTY  COST_BASIS`  
  Cash line: `cash  AMOUNT`  
  Lines starting with `#` are skipped.

```
AAPL  100  150.50
GOOGL  10  2800.00
cash   5000
```

**Output:** summary header + per-position breakdown + allocation percentages.

Tip: feed `WorldModel.facts_to_string()` output if positions are stored
as DSL facts (`AAPL_qty = 100`, `AAPL_cost = 150.50`).
