# repomix

Pack an entire repo into a single LLM-ingestible file.

## Use case

When you need the LLM to reason about a whole codebase at once (architecture decisions,
cross-file refactors, dependency analysis).

## repomix output

- Single flat file, all source files concatenated with file-path headers
- Configurable: exclude tests, node_modules, generated files
- XML or plain-text format

## When to use vs RTK

| Need                          | Use         |
|-------------------------------|-------------|
| Single-pass whole-repo view   | repomix     |
| Repeated calls, token budget  | RTK/codemap |
| Find a specific symbol        | search_symbol|
| Understand one file           | read_file   |

## Integration in context_engine

repomix output → `AUTH_FETCHED` chunk in context_engine with `PRI_MEDIUM`.
Compress with `_compress()` before injection if > max_bytes.

## Config (.repomixrc)

```json
{
  "exclude": ["*.lock", "node_modules/**", "target/**", ".git/**"],
  "format": "plain",
  "compress": true
}
```
