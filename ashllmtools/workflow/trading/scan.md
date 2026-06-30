# scan

Market scan workflow — score a watchlist for trading signals.

## Steps

1. **FETCH** — `price_fetch` each symbol in the watchlist
2. **HISTORY** — collect recent close prices per symbol (external or cached)
3. **SIGNAL** — run `signal_detect` on each price series
4. **FILTER** — keep only BUY / SELL signals; drop HOLD
5. **RANK** — sort by RSI distance from 50 (most extreme first)
6. **RECORD** — write signals as DSL facts into WorldModel
7. **REPORT** — `plan` a summary: "X buy signals, Y sell signals found"

## Example

```mojo
var wf = WorkflowEngine("scan watchlist")
var a  = wf.add_task("AAPL", "price_fetch")
var b  = wf.add_task("100,101,99,...", "signal_detect")
var c  = wf.add_task("", "plan")
wf.add_dep(b, a)
wf.add_dep(c, b)
wf.run(max_steps=20)
```

## Exit conditions

| Code    | Condition                                  |
|---------|--------------------------------------------|
| DONE    | all symbols processed, report generated    |
| BLOCKED | network unavailable or watchlist empty     |
