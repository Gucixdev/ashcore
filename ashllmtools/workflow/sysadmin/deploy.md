# sysadmin/deploy

Workflow for deploying or updating a service.

## Decision contract requirements

| Action               | Required risk level | Notes                        |
|----------------------|---------------------|------------------------------|
| `git push --force`   | BLOCK               | never allowed                |
| `rm -rf`             | BLOCK               | never allowed                |
| `systemctl restart`  | HIGH + authorized   | requires explicit auth       |
| `git push origin`    | MEDIUM              | allowed, confirmation logged |

## Steps

| # | Task                    | Skill          | Depends on |
|---|-------------------------|----------------|------------|
| 0 | check git status        | `git_status`   | —          |
| 1 | diff staged changes     | `git_diff`     | 0          |
| 2 | run tests               | `run_tests`    | 1          |
| 3 | push branch             | `exec`         | 2          |
| 4 | verify CI status        | `reflect`      | 3          |

## Acceptance criteria

- All tests pass before push
- No force-push (blocked by contract)
- Branch pushed to feature branch, not main/master directly
