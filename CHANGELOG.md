# Changelog

All notable changes to **ashcore** and **ashparser** are documented here.  
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

---

## [Unreleased]

### ashparser
#### Added
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
