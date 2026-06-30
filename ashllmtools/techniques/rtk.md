# RTK — RustTokenKiller

Token-efficient code representation for LLM context injection.

## Problem

Full source files are token-heavy. LLMs need structure, not every line.

## RTK approach

Strip source to its skeleton:
- Keep: function/struct/enum/type signatures, doc comments, public API
- Drop: function bodies, private helpers, inline comments

## Output format

```
// file: src/parser.rs
pub fn parse(input: &str) -> Result<Ast, Error>;
pub struct Parser { ... }
impl Parser {
  pub fn new() -> Self;
  pub fn parse_expr(&mut self) -> Expr;
}
```

## When to use

- Initial codebase orientation (inject RTK output into context_engine)
- Skill `codemap` produces an RTK-like skeleton for .mojo files
- Before `search_symbol` — RTK gives a fast structural overview

## Integration

```mojo
var map = codemap(".", max_depth=2)
# map contains top-level def/struct/alias lines — RTK-style skeleton
```
