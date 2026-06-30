# claudecode

Patterns specific to working with Claude Code (the CLI agent).

## Key behaviors

- **File reads are lazy** — always read before editing; don't assume content
- **Tool calls are sequential** — no true parallelism within a turn
- **Context is shared** — `Read` outputs stay in context; use wisely
- **Hooks fire on events** — PreToolUse, PostToolUse, Stop; use for guardrails
- **CLAUDE.md is authoritative** — project-level instructions override defaults

## Effective prompting for Claude Code

- Give file paths and line numbers, not vague descriptions
- Say "edit X at line N to do Y" not "improve the code"
- Use `/code-review --fix` to apply review findings automatically
- Use `/simplify` for cleanup after a feature lands

## Decision contract interaction

Claude Code's own permission system (allow/deny per tool) is Layer 0.
The decision_contract in ashllmtools is Layer 1 — fires inside the agent loop,
after the tool call is already permitted by Claude Code's own system.

## Skill mapping

| Claude Code slash command | ashllmtools skill |
|---------------------------|-------------------|
| `/code-review`            | `review`          |
| `/simplify`               | `refactor`        |
| `/run`                    | `run_tests`       |
| `/verify`                 | `reflect`         |
