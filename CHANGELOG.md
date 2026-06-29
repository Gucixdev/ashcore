# Changelog

All notable changes to **ashcore** and **ashparser** are documented here.  
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

---

## [Unreleased]

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
