# ashllmtools

8-layer LLM agent framework written in Mojo. Zero external dependencies beyond the Mojo standard library — all I/O goes through thin shell wrappers.

## Architecture

```
Layer 1 — agent_state.mojo       State machine: REACT / PLAN / AUTO / PASS / EVAL
Layer 2 — skills.mojo            Named capabilities (14 built-in skills)
Layer 3 — workflow.mojo          Unified decision loop + task decomposition
Layer 4 — memory.mojo            Note / Episodic / Semantic / LongTerm memory
Layer 5 — context_engine.mojo    Priority + authority-ranked context window
Layer 6 — rag/__init__.mojo      RAG pipeline: retrieve → rank → compress → inject
Layer 7 — decision_contract.mojo Risk-rated firewall — gates every action
Layer 8 — world_model.mojo       Environment snapshot: git state, files, assumptions
```

Tool layer (`tools/`):
- `tools/sys/shell.mojo` — `shell_run`, `ShellResult`
- `tools/sys/fs.mojo`    — `read_text`, `write_text`, `file_exists`, `list_files`, ...
- `tools/sys/git.mojo`   — `git_status`, `git_diff_staged`, `git_log`, `git_is_clean`
- `tools/code/diff.mojo` — `diff_staged`, `diff_unstaged`, `diff_branch`, `diff_stat`
- `tools/code/search.mojo` — `search_symbol`, `search_pattern`, `search_files`, `codemap`
- `tools/web/fetch.mojo` — `fetch_url`, `fetch_json`

## Built-in skills

| Name | Category | Description |
|------|----------|-------------|
| `git_status` | sys | Show working tree status |
| `git_diff` | sys | Show staged changes |
| `read_file` | code | Read file content |
| `run_tests` | code | Run test suite (pixi run test) |
| `search` | code | Grep for a symbol across .mojo files |
| `analyze` | cognitive | Line/byte count + structural metrics |
| `reflect` | cognitive | Evaluate output for ERROR/FAIL patterns |
| `plan` | cognitive | Decompose goal into numbered steps |
| `reason` | cognitive | Structural analysis + reasoning type detection |
| `decide` | cognitive | Extract first option; flag destructive keywords |
| `schedule` | cognitive | Order tasks by dependency keywords |
| `bughunt` | code | Grep for panic/error/FIXME patterns |
| `review` | code | Diff stats + flag suspicious patterns |
| `refactor` | code | File metrics: lines, defs, structs, long lines |
| `stresstest` | code | Search for boundary-access and while-True patterns |

## DSL — relational notation for world model facts

Facts are written as `lhs operator rhs` with an optional trailing `(context)`.
Operators are matched longest-first to avoid prefix ambiguity.

| Operator | Meaning |
|----------|---------|
| `=`   | definicja / przypisanie |
| `>`   | preferencja / rekomendacja |
| `+`   | koniunkcja / złożenie |
| `+-`  | modyfikacja częściowa / zmiana |
| `-`   | negacja / usunięcie |
| `/`   | alternatywa / lub |
| `<=`  | przechowywanie / odpowiedzialność |
| `!`   | uwaga |
| `?`   | sprawdzić |
| `??`  | otwarte pytanie |
| `~`   | przybliżenie / domyślność |
| `&&`  | sekwencja zależna |
| `&`   | współdzielenie / referencja |
| `*`   | wszystkie przypadki |
| `>>`  | prowadzi do / skutkuje |
| `<<`  | pochodzi z / wynika z |
| `$`   | wymóg / koszt / końcówka |
| `%`   | reszta / wycinek / zależny od |
| `^`   | początek / źródło / nadrzędność |
| `@`   | miejsce docelowe / adnotacja |
| `<->` | relacja dwukierunkowa |
| `<>`  | równoważność |
| `!=`  | nierówność / konflikt |
| `==`  | porównanie |

Context annotation — trailing `(...)` on any fact line:

```
env = production (staging)   → lhs="env" op="=" rhs="production" ctx="staging"
cache > db (latency)         → preferencja z kontekstem warunku
```

```mojo
# DSL world model facts
from dsl import DSLStore, parse_fact
from world_model import WorldModel

var wm = WorldModel()
wm.record("env = production (staging)")
wm.record("cache > db (latency)")
wm.record("api_key << vault")
wm.record("! rate_limit")
print(wm.facts_to_string())

# Query facts
var hits = wm.facts.query_lhs("env")   # → [DSLFact(lhs=env op== rhs=production ctx=staging)]
var rhs  = wm.facts.get("cache", ">")  # → "db"
var ok   = wm.facts.has("api_key", "<<", "vault")  # → True
```

## Quick start

```mojo
from workflow import WorkflowEngine, LOOP_DONE
from skills   import SkillRegistry

# Run two tasks in sequence
var w = WorkflowEngine("check repo")
var a = w.add_task("", "git_status")
var b = w.add_task("all clean\n", "reflect")
w.add_dep(b, a)
var r = w.run(max_steps=10)
print(r.reason)   # "goal achieved: check repo"
```

```mojo
# Use SkillRegistry directly
from skills import SkillRegistry

var reg = SkillRegistry()
var r = reg.run("plan", "Step one\nStep two\nStep three")
print(r.output)
# steps:
# 1. Step one
# 2. Step two
# 3. Step three
```

```mojo
# World model snapshot
from world_model import WorldModel

var wm = WorldModel()
wm.sync()
print(wm.describe())   # WorldModel(branch=main, clean=True, syncs=1, facts=0)
wm.set_assumption("env", "production")

# Record world state as DSL facts
wm.record("env = production (staging)")
wm.record("cache > db (latency)")
wm.record("api_key << vault")
print(wm.facts_to_string())
```

## Trading layer

### Tools (`tools/trading/`)

| Module | Functions |
|--------|-----------|
| `price.mojo`      | `fetch_quote(symbol)`, `fetch_close_csv(symbol, days)` |
| `indicators.mojo` | `sma`, `ema`, `rsi`, `macd`, `compute_indicator`, `_parse_csv_floats`, `_f2s` |
| `signals.mojo`    | `detect_signal(prices_csv, fast, slow, rsi_period)` |
| `portfolio.mojo`  | `Portfolio`, `Position`, `parse_portfolio(text)`, `portfolio_summary(text)` |

### Skills (`trading` category)

| Name | Description |
|------|-------------|
| `price_fetch`       | Fetch latest quote — `AAPL` → `price=182.50 change_pct=-0.42` |
| `indicator_calc`    | Compute SMA/EMA/RSI/MACD on price CSV |
| `signal_detect`     | SMA crossover + RSI → `signal=BUY\|SELL\|HOLD` |
| `portfolio_analyze` | P&L breakdown + allocation percentages |
| `backtest`          | SMA crossover backtest → trades count + PnL |

### Workflows (`workflow/trading/`)

| File | Purpose |
|------|---------|
| `scan.md`     | Score a watchlist for signals, record DSL facts |
| `analyze.md`  | Deep-dive single instrument: quote → indicators → decide |
| `strategy.md` | Develop + validate a strategy via iterative backtest |

### Quick start — trading

```mojo
from skills import SkillRegistry

var reg = SkillRegistry()

# Fetch quote
var q = reg.run("price_fetch", "AAPL")
print(q.output)   # symbol=AAPL price=182.50 change_pct=-0.42

# Compute RSI on price series
var r = reg.run("indicator_calc",
    "prices:100,102,101,99,103,105,104,107 indicator:rsi period:5")
print(r.output)   # indicator=rsi period=5 last=68.42 series=...

# Signal from CSV
var s = reg.run("signal_detect", "100,101,99,102,103,101,105,107,106,109,111")
print(s.output)   # signal=BUY rsi=... sma_fast=... sma_slow=... reason=...

# Portfolio analysis
var p = reg.run("portfolio_analyze", "AAPL 100 150.50\nGOOGL 10 2800.00\ncash 5000")
print(p.output)   # positions=2 invested=43050.00 cash=5000.00 ...

# Backtest
var b = reg.run("backtest", "prices:100,101,99,102,103,101,105,107,106,109,111,112 fast:3 slow:5")
print(b.output)   # backtest: fast=3 slow=5 bars=12 trades=2 pnl=...
```

## Tests

```bash
cd ashllmtools
mojo run test_llmtools.mojo
```
