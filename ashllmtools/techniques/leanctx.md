# leanctx

Keep context lean: inject only what the LLM actually needs, nothing more.

## Rules

1. **No full files when a slice suffices** — use `read_text` with offset/limit
2. **No repeated context** — if something was injected in step N, don't re-inject in N+1
3. **Compress before inject** — summarize long outputs before adding to context
4. **Priority order**: CRITICAL > HIGH > MEDIUM > LOW (context_engine handles this)
5. **Deduplicate**: same content from two sources → keep highest-authority source

## Context budget heuristic

| Source      | Max tokens | Notes                                  |
|-------------|-----------|----------------------------------------|
| system info | 100       | kernel, hostname, disk                 |
| git status  | 200       | current branch, dirty files            |
| code slice  | 1000      | relevant file section, not full file   |
| skill output| 500       | last skill result                      |
| world model | 300       | active beliefs and assumptions         |
| total       | ~2000     | leave room for response                |

## Anti-patterns

- Injecting entire `git log` — use `git_log(n=5)` max
- Full `file_info` on every step — only on changed files
- Re-including system_info every loop iteration — inject once at ORIENT
