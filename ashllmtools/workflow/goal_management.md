# goal_management

How goals are tracked and resolved across the decision loop.

## Goal lifecycle

```
RECEIVED → CLARIFIED → DECOMPOSED → IN_PROGRESS → DONE
                                  ↘ BLOCKED → ESCALATED
```

## Goal fields

| Field         | Type    | Description                                      |
|---------------|---------|--------------------------------------------------|
| `goal`        | String  | Original goal statement from user/caller         |
| `acceptance`  | String  | Criteria for "done" — must be checkable          |
| `max_steps`   | Int     | Safety limit; LOOP_ERROR if exceeded             |
| `tasks`       | List    | Decomposed tasks (see task_decomposition.md)     |
| `step_count`  | Int     | Current iteration count                          |

## World model integration

The world model (`world_model.mojo`) tracks active beliefs about the system.
Before each ORIENT step, beliefs are refreshed via `git_status`, `file_info`, etc.
Stale assumptions (confidence < 50) are flagged for re-verification.

## When to escalate

Escalate to the user when:
- 2+ consecutive tasks blocked by decision contract
- World model assumption confidence < 30
- Goal is ambiguous (acceptance criteria unspecifiable)
- `max_steps` reached without DONE
