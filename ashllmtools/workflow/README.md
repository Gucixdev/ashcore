# Workflow

Task-type templates that sequence skills. A workflow owns the top-level
goal and runs until done or blocked. Skills and tools are internal details.

Decision contract gates every action inside a workflow, not just at entry.

---

## Unified Decision Loop

The core execution pattern. Every workflow is an instance of this loop.

```
┌─────────────────────────────────────────────────────┐
│  1. ORIENT   — sync world model to current state    │
│  2. PLAN     — skill: plan (if no plan exists)      │
│  3. SELECT   — pick the next unblocked step         │
│  4. CONTRACT — decision contract evaluation         │
│     ├─ pass  → continue                             │
│     └─ block → surface, await user                  │
│  5. EXECUTE  — run lazytools / skills               │
│  6. REFLECT  — skill: reflect on result             │
│  7. UPDATE   — update world model + memory          │
│  8. CHECK    — goal achieved? blocked? → exit/loop  │
└─────────────────────────────────────────────────────┘
```

Exit conditions:
- **done** — all acceptance criteria met
- **blocked** — contract veto, missing info, or dependency unmet (surface to user)
- **error** — unrecoverable failure (surface + stop)

---

## Goal Management

```
goal_management/
├── capture:    record goal + acceptance criteria + constraints
├── decompose:  skill: decompose → task list
├── prioritize: order by dependency + value
├── track:      mark tasks done as execution proceeds
└── close:      verify all criteria met before declaring done
```

Never declare a goal done unless acceptance criteria are verifiable, not just
assumed.

---

## Task Decomposition

```
input:  vague goal
steps:
  1. identify unknowns (what info is missing?)
  2. split into independent sub-goals (can be parallelized)
  3. split into sequential sub-goals (depend on each other)
  4. assign skill or workflow to each sub-goal
  5. identify the first concrete action
output: flat task list with dependencies marked
```

---

## Language-Specific Task Workflow

For writing / fixing / refactoring code in a specific language.

```
1. ORIENT    — codemap + git status
2. LOCATE    — search_symbol → read_file_range
3. ANALYZE   — skill: analyze
4. CONTRACT  — reversibility guard
5. MODIFY    — skill: refactor or targeted edit
6. VERIFY    — run_tests / check_types
7. REFLECT   — if test failure → goto ANALYZE
8. COMMIT    — git add + commit (if in scope)
```

---

## Search-Specific Task Workflow

For answering questions about the codebase or external knowledge.

```
1. ORIENT     — what is known? what is needed?
2. SEARCH     — search_symbol + search_usage
3. READ       — read_file_range for relevant locations
4. WEB?       — if not in codebase: fetch_url / search_web (guarded)
5. SYNTHESIZE — skill: reason → answer
6. VERIFY     — does answer satisfy the question?
```

---

## Sysadmin-Specific Task Workflow

For infrastructure, process, and environment operations.

```
1. ORIENT    — git_status + check_env + process_list
2. CONTRACT  — blast radius guard (escalate if shared infra)
3. PLAN      — enumerate required changes + rollback plan
4. CONFIRM   — surface plan to user if high/block risk
5. EXECUTE   — ordered shell operations
6. VERIFY    — check_file_exists / check_process / tail_log
7. ROLLBACK  — if verify fails: execute rollback plan
```

---

## Format-Specific Task Workflow

For converting, generating, or transforming structured data.

```
1. READ      — read source file(s)
2. SCHEMA    — identify input + output format
3. MAP       — define field-by-field transformation
4. TRANSFORM — write output
5. VALIDATE  — check output against schema / sample
```
