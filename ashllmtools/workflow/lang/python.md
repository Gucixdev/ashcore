# lang/python

Python-specific coding task workflow.

## Steps

| # | Task                       | Skill          | Depends on |
|---|----------------------------|----------------|------------|
| 0 | read target file(s)        | `read_file`    | —          |
| 1 | search imports/deps        | `search`       | 0          |
| 2 | analyze code               | `analyze`      | 0          |
| 3 | plan change                | `plan`         | 2          |
| 4 | apply change               | `exec`         | 3          |
| 5 | run tests (pytest/unittest)| `run_tests`    | 4          |
| 6 | reflect                    | `reflect`      | 5          |

## Python-specific notes

- Type hints preferred: `def fn(x: int) -> str`
- Use `pathlib.Path` over `os.path`
- Tests via `pytest` — run with `pixi run test` or `python -m pytest`
- Virtual env: check `pyproject.toml` or `requirements.txt` for deps
