# analyze

Deep-dive workflow for a single position or candidate instrument.

## Steps

1. **QUOTE** — `price_fetch` for current price
2. **INDICATORS** — `indicator_calc` for SMA(20), EMA(12), RSI(14), MACD
3. **SIGNAL** — `signal_detect` on recent close series
4. **PORTFOLIO** — `portfolio_analyze` to check existing exposure
5. **REASON** — `reason` on indicator output to detect trend direction
6. **DECIDE** — `decide` between hold / add / reduce / exit
7. **RECORD** — write decision as DSL fact: `AAPL >> add (RSI=28,oversold)`

## DSL facts produced

```
AAPL = 182.50            # current price
AAPL >> add (oversold)   # decision + reason
rsi_AAPL ~ 28            # RSI approximation
```

## Exit conditions

| Code    | Condition                                      |
|---------|------------------------------------------------|
| DONE    | decision recorded, DSL facts updated           |
| BLOCKED | fetch failed or insufficient price history     |
