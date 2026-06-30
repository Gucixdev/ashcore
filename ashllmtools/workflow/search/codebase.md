# search/codebase

Workflow for finding something specific in a codebase.

## Steps

| # | Task                        | Skill          | Depends on |
|---|-----------------------------|----------------|------------|
| 0 | codemap — directory tree    | `search`       | —          |
| 1 | symbol search               | `search`       | 0          |
| 2 | pattern grep across files   | `search`       | 0          |
| 3 | read candidate files        | `read_file`    | 1, 2       |
| 4 | analyze + synthesize result | `analyze`      | 3          |

## Tips

- Start with `codemap` to understand structure before grepping
- Narrow glob to language extension (`*.mojo`, `*.py`, `*.ts`)
- Use `search_symbol` for exact names, `search_pattern` for patterns
- `codemap` lists all top-level `def`, `struct`, `alias`, `comptime`
