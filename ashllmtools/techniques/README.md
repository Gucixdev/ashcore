# Techniques

Field-tested patterns from real projects. Each technique solves a specific,
recurring problem in LLM-augmented development. Use the decision contract to
decide when each applies.

---

## caveman

**Problem:** The agent over-engineers solutions when a simpler approach exists.

**Technique:** Before generating code, ask: *what is the dumbest thing that
could work?* Then ask: *does the dumb thing actually fail?* If not, use it.

```
caveman rule:
  if (simple version passes tests) use simple version
  if (no version exists) write the simplest possible version first
  if (complex version is proposed) ask: what test fails with simple version?
```

Prevents premature abstraction. Prevents adding error handling for impossible
states. Prevents refactoring-by-default.

---

## leanctx

**Problem:** Context fills up with redundant, low-signal content (full file
reads, verbose tool outputs, repeated summaries).

**Technique:** Compress aggressively at each layer boundary.

```
leanctx rules:
  read only the lines you need (offset + limit, not full file)
  never repeat content already in context — reference it
  summarize tool output > 50 lines before injecting
  drop conversation turns that are fully resolved
  in RAG: chunks are 200-400 tokens max; prefer symbol-level over file-level
```

Pairs with the context engine (layer 5). Leanctx is the discipline;
the context engine is the mechanism.

---

## claudecode

**Problem:** Claude Code sessions diverge from best practices (verbose
comments, unnecessary abstractions, security bypasses).

**Technique:** Establish session-level constraints in the first message and
enforce them via decision contract.

Key claudecode patterns:
- No comments unless WHY is non-obvious
- No `--no-verify`, no `--force` without explicit request
- No new files unless no existing file fits
- Edits over rewrites
- Run tests before claiming a fix works
- One concern per commit

These are not guidelines — they're contract rules for the session.

---

## RTK — Rust Token Killer

**Problem:** Rust verbosity (lifetimes, generics, where clauses) bloats
context fast, leaving less room for actual problem-solving.

**Technique:** Aggressive pre-processing of Rust code before injecting into
context.

```
RTK pipeline:
  1. strip doc comments (keep inline only if critical)
  2. collapse where-clause boilerplate to one line
  3. replace generic bounds with <T: Trait> shorthand
  4. drop dead code / #[allow(unused)] blocks
  5. summarize impl blocks as "impl Foo { N methods }" unless method is relevant
```

Result: 40-60% token reduction on typical Rust files without losing semantics.

---

## repomix

**Problem:** Sharing a whole repo as context is too large; sharing individual
files loses the cross-file structure.

**Technique:** Generate a single, structured, token-efficient representation of
the repo at a configurable depth.

```
repomix output format:
  <file path="src/lib.rs" tokens="320">
    <symbols>Foo, Bar, impl Foo</symbols>
    <content>... compressed content ...</content>
  </file>
```

Use for: onboarding a new agent session, sending repo to an external LLM,
generating a codebase snapshot for issue reports.

Key config: `--depth`, `--exclude`, `--symbol-only`, `--max-tokens-per-file`.

---

## langfuse

**Problem:** No visibility into what the agent actually sent/received, which
makes debugging wrong outputs impossible.

**Technique:** Trace every agent turn with full prompt + completion + tool
calls. Score outputs. Build datasets from failures.

```
langfuse integration points:
  - trace_id per session
  - span per skill / tool call
  - score on: correctness, contract violation, context efficiency
  - dataset: capture failing turns for regression testing
```

Use langfuse to answer: *why did the agent do that?* and *did this change
make outputs better or worse?*

---

## freshdocs

**Problem:** RAG retrieves docs that were accurate 6 months ago but are now
wrong. Agent confidently gives stale answers.

**Technique:** Attach a retrieval timestamp to every injected document chunk.
Before answering, compare timestamp to staleness threshold for the topic.

```
freshdocs rules:
  - mark each chunk: source, url, retrieved_at
  - for API/versioned docs: stale after 7 days
  - for changelog/release notes: stale after 1 hour if active development
  - for architecture docs in-repo: always fresh (read from disk each time)
  - if stale: re-fetch before answering, or label answer as "as of <date>"
```

Prevents the most common RAG failure mode: confident wrong answers from
outdated context.
