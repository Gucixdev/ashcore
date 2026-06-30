# format/lint

Workflow for formatting and linting a codebase.

## Steps

| # | Task                       | Skill          | Depends on |
|---|----------------------------|----------------|------------|
| 0 | list files to format       | `search`       | —          |
| 1 | run linter/formatter       | `exec`         | 0          |
| 2 | check diff (what changed)  | `exec`         | 1          |
| 3 | run tests (no regressions) | `run_tests`    | 2          |
| 4 | reflect on results         | `reflect`      | 3          |

## Common commands

| Lang   | Format                      | Lint                     |
|--------|-----------------------------|--------------------------|
| Python | `black .` / `ruff format .` | `ruff check .`           |
| JS/TS  | `prettier --write .`        | `eslint .`               |
| Rust   | `cargo fmt`                 | `cargo clippy`           |
| Mojo   | (no official formatter yet) | manual review            |
