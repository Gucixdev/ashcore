# task_decomposition

How a goal is broken into tasks and how dependencies are managed.

## Task fields

| Field        | Type   | Description                                 |
|--------------|--------|---------------------------------------------|
| `id`         | Int    | Unique ID within the workflow               |
| `desc`       | String | What this task does                         |
| `skill`      | String | Which skill to invoke                       |
| `status`     | Int    | PENDING / RUNNING / DONE / BLOCKED / SKIPPED|
| `deps`       | List   | IDs of tasks that must be DONE first        |
| `result`     | String | Output from the skill after execution       |

## Dependency resolution

SELECT step picks the first task where:
1. `status == PENDING`
2. all `deps[i].status == DONE`

If no such task exists and not all tasks are DONE → exit `LOOP_BLOCKED`.

## Anti-patterns to avoid

- Circular deps (`A → B → A`) — will deadlock; detect on add_dep()
- Single mega-task — split into atomic skills for better reflection
- Skipping reflect — always add a reflect task after any exec/run_tests

## Example decomposition

Goal: "refactor auth module, run tests, push"

```
task 0: read auth.mojo            (read_file)
task 1: analyze structure         (analyze,  deps=[0])
task 2: plan refactor             (plan,     deps=[1])
task 3: apply refactor            (exec,     deps=[2])
task 4: run tests                 (run_tests, deps=[3])
task 5: reflect on test result    (reflect,  deps=[4])
task 6: push branch               (exec,     deps=[5])
```
