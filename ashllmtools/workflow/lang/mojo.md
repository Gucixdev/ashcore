# lang/mojo

Mojo-specific coding task workflow.

## Steps

| # | Task                        | Skill          | Depends on |
|---|-----------------------------|----------------|------------|
| 0 | read target file(s)         | `read_file`    | —          |
| 1 | codemap — structural overview| `search`       | —          |
| 2 | analyze code / find issue   | `analyze`      | 0, 1       |
| 3 | plan change                 | `plan`         | 2          |
| 4 | apply change                | `exec`         | 3          |
| 5 | run tests                   | `run_tests`    | 4          |
| 6 | reflect on test result      | `reflect`      | 5          |

## Mojo-specific notes

- All parsers are `@parameter def` — must be compile-time
- No `in` operator on String — use explicit byte search
- `String[start:end]` slicing may not work — use `StringSlice(ptr=..., length=...)`
- Move semantics: use `^` to transfer ownership out of functions
- Traits: `Copyable & Movable & ImplicitlyDeletable` on struct params
