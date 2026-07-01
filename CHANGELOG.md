# Changelog

All notable changes to **ashcore** and **ashparser** are documented here.  
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

---

## [Unreleased]

### ashllmtools
#### Added
- **GPU acceleration** — `ashcore/gpu.mojo` now implements real GPU kernels via
  Mojo's `DeviceContext` (stable since MAX 26.x / Mojo 1.0.0b2, confirmed by
  the `ehsanmok/json` library using the same API):
  - `has_gpu() -> Bool` — runtime GPU detection via try/except DeviceContext
  - `_gpu_sma_kernel` — GPU kernel: each thread computes one SMA output value
    (`output[tid] = mean(prices[tid : tid+period])`); launched with
    `ctx.enqueue_function` + `grid_dim=ceil(out_n/256)`, `block_dim=256`
  - `_gpu_abs_diff_kernel` — GPU kernel: each thread computes one absolute
    bar-to-bar change (`|prices[tid+1] - prices[tid]|`), used by whalecheck
  - `gpu_map_f64(prices, period)` — host-side launcher: allocates pinned host
    buffer → H→D copy → SMA kernel → D→H copy → returns `List[Float64]`;
    falls back to `_cpu_sma` on any exception (no GPU, wrong driver, etc.)
  - `gpu_abs_diffs(prices)` — same pattern for abs-diff computation
  - `gpu_parallel_for` kept CPU-only by design (GPU kernels cannot capture
    arbitrary closures; explanation added to docstring)
- `ashllmtools/tools/trading/gpu_indicators.mojo` — trading-layer GPU bridge:
  - `gpu_sma(prices, period)` — delegates to `gpu_map_f64`, CPU fallback
  - `gpu_sma_csv(prices_csv, period)` — CSV-in / CSV-out entry point for the skill
  - `gpu_whalecheck(prices)` — GPU abs-diffs + CPU mean/std/threshold;
    output includes `backend=gpu|cpu` field
- `tools/trading/__init__.mojo` — `indicator_calc` skill tries GPU SMA first
  (bare CSV or `indicator: sma` path); `whalecheck` skill delegates entirely to
  `gpu_whalecheck` so abs-diff loop runs on GPU when available
- **ashparser integration** — `ashllmtools/ashparser` symlink wires the ashparser
  combinator library into ashllmtools without touching `pixi.toml`:
  - `tools/trading/parser.mojo` — new module; `parse_floats_csv` uses
    `P[Float64, parse_float].p_sep_by(P[UInt8, byte[',']])` (ashparser sep_by +
    overflow-safe parse_float); `parse_portfolio_line` uses `take_while1` +
    `parse_float` combinators to replace hand-rolled token extraction;
    `PortfolioLine` result struct
  - `tools/trading/indicators.mojo` — `_parse_float_str` (27 lines) and the old
    `_parse_csv_floats` (17 lines) deleted; replaced by `from tools.trading.parser
    import parse_floats_csv as _parse_csv_floats`; ashparser's `parse_float` now
    handles leading `+`, leading `.`, exponent capping, and overflow detection
  - `tools/trading/portfolio.mojo` — `_read_token`, `_token_end`, `_parse_float_str`
    helpers deleted; `parse_portfolio` rewritten to call `parse_portfolio_line` per
    line (ashparser combinator stack: `_PSym → _PWS → _PFlt → _PWS → _PFlt`)
  - `dsl.mojo` — `parse_facts` now uses ashparser `rest_of_line` + `line_ending`
    for clean line iteration (was manual byte-by-byte newline scan); `parse_fact`
    itself kept hand-rolled because the 24-operator leftmost-match logic is
    non-left-to-right
- Auto-discovery architecture: `SkillRegistry` now scans `skills/` folder for `.md` files with
  YAML frontmatter (`name:`, `category:`) at startup — no more `_register_builtins()` hardcoding;
  `skills.mojo` reduced to a thin router that dispatches by category to `tools/<cat>/__init__.mojo`
- `skill_types.mojo` — shared `SkillResult` and `Skill` structs imported by all category modules,
  eliminating circular dependency between `skills.mojo` and `tools/<cat>/`
- `tools/cognitive/__init__.mojo` — owns all cognitive skill implementations (`reflect`, `analyze`,
  `plan`, `reason`, `decide`, `schedule`, `evaluate`) + `dispatch()` function
- `tools/code/__init__.mojo` — owns all code skill implementations (`bughunt`, `review`, `refactor`,
  `stresstest`, `exec`) + `dispatch()` function
- `tools/sys/__init__.mojo` — owns all sys skill implementations (`git_status`, `git_diff`,
  `read_file`, `run_tests`, `search`) + `dispatch()` function
- `tools/trading/__init__.mojo` — owns all trading skill implementations (`price_fetch`,
  `indicator_calc`, `signal_detect`, `portfolio_analyze`, `backtest`, `whalecheck`, `chart`) +
  `dispatch()` function
- `tools/trading/` — 2 new trading skills:
  - `whalecheck` — statistical outlier detection (>2.5σ absolute bar-to-bar move) to identify
    large-order whale activity; reports `whale_bars`, `max_move`, `threshold`, alert string
  - `chart` — ASCII price chart renderer (60×10 grid); linearly interpolates N bars into 60
    display columns, maps price to HEIGHT rows, outputs `|*  ...|` lines with lo/hi labels
- `skills/trading/whalecheck.md`, `skills/trading/chart.md` — skill spec docs
- `workflow/trading/whale_strategy.md` — 6-step workflow: fetch → whalecheck → chart →
  filtered signal → backtest → DSL facts; includes acceptance criteria table
- `workflow.mojo` — `load_workflow(name)` reads `workflow/**/<name>.md` by name;
  `list_workflows()` returns all workflow document stems sorted; imports updated to use
  `from skill_types import SkillResult`
- `dsl.mojo` — compact 24-operator relational notation for world model facts:
  operators cover definition (`=`), preference (`>`), sequence (`&&`), leads-to
  (`>>`), bidirectional (`<->`), equivalence (`<>`), negation (`-`), query (`?`),
  approximation (`~`), source (`^`), destination (`@`), and more; optional
  trailing `(ctx)` annotation on any fact line; `DSLFact` struct, `parse_fact`,
  `parse_facts`, and `DSLStore` collection with `query_lhs`, `query_op`,
  `query_rhs`, `get`, `has`, `add_text`, `clear`, `to_string`
- `tools/trading/` — new trading tool layer (4 modules):
  - `price.mojo` — `fetch_quote`, `fetch_close_csv` via Yahoo Finance / curl
  - `indicators.mojo` — `sma`, `ema`, `rsi`, `macd`, `compute_indicator`;
    helpers `_parse_csv_floats`, `_f2s`, `_list_last`
  - `signals.mojo` — `detect_signal`: SMA crossover + RSI overbought/oversold
  - `portfolio.mojo` — `Position`, `Portfolio`, `parse_portfolio`,
    `portfolio_summary`; `Portfolio.to_dsl()` serializes to DSL facts
- `skills.mojo` — 5 new trading skills: `price_fetch`, `indicator_calc`,
  `signal_detect`, `portfolio_analyze`, `backtest` (SMA crossover);
  registered under `"trading"` category
- `skills/trading/` — 5 skill spec docs: `price_fetch.md`, `indicator_calc.md`,
  `signal_detect.md`, `portfolio_analyze.md`, `backtest.md`
- `workflow/trading/` — 3 workflow docs: `scan.md` (watchlist signal scoring),
  `analyze.md` (single instrument deep dive), `strategy.md` (iterative backtest
  refinement with DSL fact recording and acceptance criteria)
- `dsl.mojo` — `DSLStore.update(lhs, op, rhs)` upserts a fact (preserving
  existing `ctx`); `DSLStore.remove(lhs, op)` deletes all matching facts
- `world_model.mojo` — `WorldModel` now embeds a `DSLStore` as `facts` field;
  new `record(line)` and `record_text(text)` methods let the agent write world
  state as DSL facts; `describe()` now includes `facts=N`; `facts_to_string()`
  renders the full fact set; `sync()` auto-records `branch`, `clean`, `remote`
  as DSL facts on every call; `set_assumption()` mirrors every write to the
  DSL fact store via `update()` — assumptions and facts are now a single source
- `context_engine.mojo` — `add_facts(store, priority, source)` converts a
  `DSLStore` into a `ContextChunk` and injects it into the context window;
  empty stores are silently skipped
- New library: 8-layer LLM agent framework in Mojo
- `agent_state.mojo` — finite state machine (REACT / PLAN / AUTO / PASS / EVAL)
- `decision_contract.mojo` — risk-rated firewall that gates every action before execution
- `skills.mojo` — `SkillRegistry` with 14 named skills (cognitive + code + sys + web)
- `workflow.mojo` — `WorkflowEngine`: unified 8-step decision loop with task decomposition,
  dependency ordering, and `SkillRegistry` dispatch (replaced stub executor)
- `memory.mojo` — `NoteMemory`, `EpisodicMemory`, `SemanticMemory`, `LongTermMemory`
- `context_engine.mojo` — priority + authority-ranked `ContextEngine`
- `rag/__init__.mojo` — RAG pipeline: retrieve → rank → compress → inject
- `world_model.mojo` — environment snapshot with git state, file tracking, and
  confidence-degrading assumptions; tested in `test_llmtools.mojo`
- `skills.mojo` — 8 previously-registered-but-unimplemented skills now fully dispatched:
  `plan` (numbered step decomposition), `reason` (sentence + keyword analysis),
  `decide` (first-option extraction + destructive-keyword guard), `schedule` (dependency
  keyword ordering), `bughunt` (grep error/panic/FIXME patterns), `review` (diff stats +
  flag unsafe_ptr/external_call/TODO), `refactor` (file metrics: lines/defs/structs/long
  lines), `stresstest` (boundary-access and while-True pattern search)
- `ashllmtools/__init__.mojo` — package-level entry point (enables package imports)
- `ashllmtools/README.md` — architecture overview, skill table, quick-start examples
- `tools/sys/` — `shell.mojo`, `fs.mojo`, `git.mojo` (system tool layer)
- `tools/code/` — `diff.mojo`, `search.mojo`
- `tools/web/` — `fetch.mojo`

### ashparser
#### Added
- `p.mojo` — fluent `P[T, run]` combinator wrapper with full method-chaining API:
  `p_then`, `p_skip`, `p_between`, `p_sep_by`, `p_sep_by1`, `p_many`, `p_many1`,
  `p_map`, `p_flat_map`, `p_verify`, `p_recognize`, `p_attempt`, `p_peek`,
  `p_skip_many`, `p_skip_many1`, `p_count`, `__or__` (choice operator)
- `p.mojo` — pre-built aliases: `PDigit`, `PAlpha`, `PAlphanum`, `PWs`, `PDigits`,
  `PIdent`, `PEof`, `PAny`, `PHexDigit`, `PHexDigits`, `PUint`, `PInt`, `PFloat`,
  `PQuoted`, `PLineEnd`, `PRestLine`; factory functions `p_byte`, `p_tag`, `p_satisfy`,
  `p_one_of`, `p_none_of`, `p_take`, `p_is_a`, `p_is_not`
- Example files rewritten to use the fluent P API: `calc.mojo`, `csv.mojo`, `demo.mojo`,
  `stream_csv.mojo`, `toml.mojo`, `xml.mojo`, `yaml.mojo`
- `fileio.mojo` — `read_file(path)` for whole-file parsing (RAM-bounded by file size);
  `StreamingInput` for chunked streaming (RAM = chunk_size, default 1 MB, file size unlimited).
  No changes to existing combinators — `StreamingInput` produces regular `Input` values.
- `example/stream_csv.mojo` — streaming CSV example (1M rows with O(1 MB) RAM)
- `prim.mojo` — new primitives: `any_byte`, `take[N]`, `is_a[chars]`, `is_not[chars]`,
  `take_while_m_n[MIN, MAX, pred]`, `parse_float` (full IEEE-style decimal with exponent)
- `comb.mojo` — new combinators: `flat_map` (dependent/monadic sequencing),
  `value` (map match to constant), `fold_many0` / `fold_many1` (accumulating loops),
  `cond` (predicate-gated parsing)
- `statecomb.mojo` — complete stateful API parity: `sseq`, `sbetween`, `scount`,
  `srecognize`, `svalue`, `sflat_map`, `sfold_many0`, `sfold_many1`, `scond`;
  mirrors every stateless combinator that was missing a stateful equivalent
- `example/calc.mojo` — guard against division by zero (`raise Error`)

#### Fixed
- `arena.mojo` — `reset()` now scans the full slab list (not just from the end)
  so that oversized slabs sandwiched between normal slabs are freed instead of
  leaking until `free_all()`
- `fileio.mojo` — `rewind(n)` with `n ≤ 0` is now a no-op; previously negative
  `n` advanced `_buf_pos` forward potentially past `_buf_len`
- `fileio.mojo` — `next_chunk()` now resets `_last_truncated` to `False`; the
  flag from a prior `next_line()` truncation was leaking into chunk reads
- `prim.mojo` — `parse_float` now accepts a leading `+` sign (`+1.5`) and a
  leading dot without an integer part (`.75`); was silently rejected before
- `sourcemap.mojo` — `line_col(pos)` clamps negative `pos` to 0 instead of
  returning a col ≤ 0 which violated the 1-based invariant

#### Fixed
- `fileio.mojo` — `StreamingInput._fill()`: replaced O(n) byte-by-byte leftover shift
  with a single `memmove` syscall; read() returning -1 (I/O error) now sets `has_error()`
  instead of being silently treated as EOF; `from_file()` validates `chunk_size > 0`
- `fileio.mojo` — `StreamingInput.from_file()` now opens with `O_RDONLY | O_CLOEXEC`
  (was `O_RDONLY` only) to prevent fd inheritance by child processes after `fork`/`exec`
- `fileio.mojo` — `StreamingInput.next_line()` now sets `last_line_truncated() → True`
  when a line exceeds `chunk_size`; previously the truncation was silent and undetectable
- `prim.mojo` — `parse_float` exponent accumulation is now capped at 400 (beyond Float64
  max ~1e308), preventing signed-integer overflow on inputs like `"1e9999999999999999999"`;
  exponent scaling replaced with O(log n) fast exponentiation (was O(exp_val) loop, a DoS
  vector for inputs like `"1e100000"`)
- `prim.mojo` — `parse_uint` / `parse_int` detect overflow during digit accumulation and
  return a `failure` result; previously very long digit strings caused silent UInt64/Int64
  wrap-around
- `prim.mojo` — `quoted_string` / `_escape` now reject unrecognized escape sequences
  (e.g. `"\x41"`) with a parse failure; previously the backslash was silently dropped
- `input.mojo` — `peek_at(offset)` now guards against negative computed indices
  (`pos + offset < 0`) which caused out-of-bounds reads before the buffer start
- `comb.mojo` — `many`, `many1`, `skip_many`, `skip_many1`, `fold_many0`, `fold_many1`
  all have a zero-progress guard: if the inner parser succeeds without advancing the
  input position the loop exits, preventing infinite loops on zero-width parsers
- `statecomb.mojo` — same zero-progress guard applied to `smany` and `smany1`

### ashcore
#### Fixed
- `arena.mojo` — `alloc()` now checks for integer overflow before computing
  `aligned + size`; pathological allocations can no longer wrap the bump pointer
  into valid-looking but wrong memory
- `debug.mojo` — `dbg_unreachable()` now emits `llvm.trap` (SIGILL) in release
  builds; previously the release path was a silent no-op, letting execution continue
  past supposedly unreachable code

---

## [0.1.0] — 2026-06-29

Initial public release of both libraries.

---

### ashcore

#### Added
- `arena.mojo` — bump-pointer allocator; O(1) reset, auto-growing regions, SIMD-aligned slots
- `shared_arena.mojo` — thread-safe `Arena` wrapped with `TicketLock`
- `sync.mojo` — `TicketLock` (FIFO spinlock), `RWLock`, `Semaphore`, `Once`
- `threadpool.mojo` — `ThreadPool` (fixed workers, chunk-64 work-sharing via atomic counter)
- `taskgraph.mojo` — `TaskGraph`: static DAG with topological-level barriers; Kahn's algorithm
- `reactivegraph.mojo` — `ReactiveGraph`: barrier-free DAG; jobs enqueue dependents atomically on completion
- `parallel.mojo` — `parallel_for` / `parallel_for_range` convenience wrappers
- `queue.mojo` — `SPSCQueue` (wait-free ring buffer), `EventQueue`, `pack_event` / `event_tag` helpers
- `debug.mojo` — comptime `DEBUG` flag; `dbg_assert`, `dbg_bounds`, `dbg_positive`, `dbg_eq`, `dbg_unreachable`
- `gpu.mojo` — CPU-fallback stub for `gpu_parallel_for`; GPU path ready when `DeviceContext` stabilises
- Examples: `dag_pipeline.mojo`, `parallel_reduce.mojo`, `arena_scratch.mojo`
- Benchmarks: pool, arena, sync, reduce, sweep; stress tests for DAG, lock, queue, respawn

#### Changed
- Source layout flattened: `ashcore/src/ashcore/` → `ashcore/ashcore/`
- `jobs.mojo` split into four focused modules: threadpool / taskgraph / reactivegraph / parallel

---

### ashparser

#### Added
- `input.mojo` — zero-copy `Input` view (address + pos, no allocation on advance)
- `result.mojo` — `ParseResult[T]` with `success` / `failure` constructors and `message_ctx`
- `sourcemap.mojo` — `SourceMap` (O(n) build, O(log n) `line_col` lookup) + `LineCol`
- `prim.mojo` — `satisfy`, `byte`, `tag`, `take_while`/`take_while1`, `digit`, `alpha`,
  `alphanum`, `ws`, `digits`, `ident`, `eof`, `one_of`, `none_of`, `line_ending`,
  `rest_of_line`, `hex_digit`, `hex_digits`, `parse_uint`, `parse_int`, `quoted_string`
- `comb.mojo` — `opt`, `many`, `many1`, `map`, `attempt`, `choice`, `seq`,
  `skip_left`, `skip_right`, `between`, `sep_by`, `sep_by1`,
  `peek`, `not_followed_by`, `verify`, `skip_many`, `skip_many1`, `count`, `recognize`
- `state.mojo` — `Ctx[S]`, `CtxResult[T, S]` for stateful parsing
- `statecomb.mojo` — `slift`, `sget`, `smodify`, `smap`, `sattempt`, `schoice`,
  `smany`, `smany1`, `sskip_left`, `sskip_right`, `ssep_by`, `ssep_by1`
- Examples: `csv.mojo` (RFC 4180), `json.mojo` (RFC 8259), `http_headers.mojo` (RFC 9110),
  `calc.mojo`, `toml.mojo`, `xml.mojo`, `yaml.mojo`
- Benchmarks: json, prim, int, arena, pool comparisons vs Python

#### Changed
- Source layout flattened: `ashparser/src/ashparser/` → `ashparser/ashparser/`
- `prim.mojo`, `comb.mojo`, `statecomb.mojo` — collapsed `var r = …; return r^` bloat
- `quoted_string` — handles `\n`, `\t`, `\r` escape sequences via `_escape` helper
- `result.mojo` — imports `SourceMap` from `ashparser.sourcemap`
- `__init__.mojo` — re-exports `SourceMap`, `LineCol`

#### Fixed
- `ReactiveGraph` busy-wait spin replaced with `Semaphore`-gated sleep (975d1ff)
- `SourceMap` / `LineCol` extracted to own module; `result.mojo` imports cleanly
