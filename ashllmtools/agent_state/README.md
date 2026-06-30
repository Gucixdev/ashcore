# Agent State

The agent operates in one of five states at any time. State determines how
input is interpreted, which skills fire, and what the agent does without
explicit instruction.

---

## State Machine

```
          ┌─────────┐
user msg  │         │ /pass
───────►  │  REACT  │◄────────────────────────────┐
          │         │                              │
          └────┬────┘                              │
               │ goal detected + plan exists       │
               ▼                                   │
          ┌─────────┐   contract block             │
          │  PLAN   │──────────────────────────────┤
          │         │                              │
          └────┬────┘                              │
               │ plan approved                     │
               ▼                                   │
          ┌─────────┐   user types / /stop         │
          │  AUTO   │──────────────────────────────┘
          │         │
          └────┬────┘
               │ needs external input / blocked
               ▼
          ┌─────────┐
          │  PASS   │  (waiting — no autonomous action)
          │         │
          └────┬────┘
               │ eval / reflection triggered
               ▼
          ┌─────────┐
          │  EVAL   │  (meta — reviewing own output)
          └─────────┘
```

---

## States

### REACT
Default. Process the current user message. Use skills and tools as needed.
No autonomous multi-step execution. Each user turn → one agent response.

- Fires: always, on new user input
- Reads: world model snapshot
- Does not: initiate unrequested actions

### PLAN
Decompose a goal into a plan and present it for approval.
No execution. Plan only.

- Fires: when goal detected and no approved plan exists
- Output: task list with dependencies
- Transitions to: AUTO on approval, REACT on rejection

### AUTO
Execute an approved plan step-by-step until done, blocked, or stopped.
Runs the unified decision loop without user input between steps.

- Fires: after plan approval or `/auto` command
- Pauses: on contract block, on `high` risk guard, on ambiguity
- Reports: each completed step + final summary
- Terminates: on `/stop`, goal completion, or unrecoverable error

### PASS
Waiting. Nothing to do. No autonomous action. World model may be stale.

- Fires: on `/pass`, after delivering a response, or on timeout
- Does: nothing until next user input
- Use when: waiting for CI, waiting for user review, task is done

### EVAL
Reflection mode. Review the last action or plan for correctness.
Can be entered manually (`/eval`) or triggered automatically after AUTO step.

- Fires: after each AUTO execution step, or on `/eval`
- Input: last action + result
- Output: verdict (ok / incorrect / partial) + corrective action if needed
- Does not: execute corrections — returns to REACT or AUTO for that

---

## Commands

| Command | Effect |
|---------|--------|
| `/auto` | Enter AUTO state, execute current plan |
| `/pass` | Enter PASS state, stop autonomous action |
| `/plan` | Enter PLAN state, produce a plan for current goal |
| `/eval` | Enter EVAL state, reflect on last action |
| `/stop` | Exit AUTO, return to REACT |
| `/react` | Force REACT state |

---

## State Persistence

State is session-scoped. A new session always starts in REACT.
Plans survive context compression (stored in memory layer).
World model is rebuilt on session start from git state + file system.
