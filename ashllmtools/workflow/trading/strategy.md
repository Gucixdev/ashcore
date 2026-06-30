# strategy

Strategy development and validation workflow.

## Steps

1. **LOAD** — `read_file` historical price CSV or fetch via `price_fetch`
2. **INDICATOR** — `indicator_calc` for candidate indicator(s)
3. **BACKTEST** — `backtest` with chosen fast/slow periods
4. **REFLECT** — `reflect` on backtest output (check pnl > 0, trades > 2)
5. **REASON** — `reason` to identify weaknesses (drawdown, few trades)
6. **REFINE** — adjust parameters, re-run `backtest` (loop max 3×)
7. **PLAN** — `plan` deployment steps if backtest is satisfactory
8. **RECORD** — write strategy spec as DSL facts into WorldModel

## DSL facts produced

```
strategy = sma_crossover (fast=5,slow=20)
backtest_pnl = 12.40
backtest_trades = 8
strategy >> deploy (after_validation)
```

## Acceptance criteria

- `pnl > 0`
- `trades >= 3`
- `reflect` verdict = `ok`

## Exit conditions

| Code    | Condition                                         |
|---------|---------------------------------------------------|
| DONE    | strategy validated and recorded as DSL facts      |
| BLOCKED | negative PnL after 3 refinement attempts          |
