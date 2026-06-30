# Hard Rules

These are unconditional. No skill, workflow, or user instruction overrides them.
Any agent or tool that would violate a hard rule must stop and surface the conflict.

---

## Git / Version Control

| # | Rule | Trigger |
|---|------|---------|
| G1 | Never push to `main`/`master` | push target = protected branch |
| G2 | Never force-push any branch | `--force` or `--force-with-lease` without explicit session grant |
| G3 | Never amend a published commit | `--amend` on a commit that exists on remote |
| G4 | Never skip pre-commit hooks | `--no-verify` flag present |
| G5 | Never commit `.env`, `*_key`, `*_secret`, `*_token` | file path or content pattern match |
| G6 | Never delete a branch that is not local-only | remote tracking ref exists |

---

## Filesystem / Destructive Ops

| # | Rule | Trigger |
|---|------|---------|
| F1 | Never `rm -rf` without explicit confirmation token | recursive delete |
| F2 | Never overwrite an uncommitted file without reading it first | write to modified file |
| F3 | Never delete a file that was not created in this session without confirmation | path not in session-created set |
| F4 | Never truncate a file to zero without reading its content first | write empty / `> file` |

---

## Execution / Shell

| # | Rule | Trigger |
|---|------|---------|
| E1 | Never eval / exec user-supplied strings as shell | input source = user-provided |
| E2 | Never run commands that spawn background processes without surfacing the PID | `&`, `nohup`, `disown` |
| E3 | Never install packages globally without explicit confirmation | `pip install -g`, `npm -g`, `cargo install` system-wide |
| E4 | Never modify `/etc`, `/usr`, `/bin` without explicit scope grant | path prefix check |

---

## Network / External

| # | Rule | Trigger |
|---|------|---------|
| N1 | Never send data to a URL not in session scope | outbound request to unlisted host |
| N2 | Never POST/PUT/DELETE to an API without showing payload first | mutating HTTP method |
| N3 | Never use credentials found in repo as live credentials | secret detected in source |
| N4 | Never cache or store external responses containing PII | response content analysis |

---

## Secrets / PII

| # | Rule | Trigger |
|---|------|---------|
| S1 | Never log, print, or commit values matching secret patterns | `sk-*`, `ghp_*`, `AKIA*`, UUID-like tokens |
| S2 | Never pass secrets as CLI arguments (visible in process list) | flag contains secret pattern |
| S3 | Never include secrets in error messages or diagnostics | exception / debug output |

---

## Rule Conflict Resolution

If two rules conflict, the more restrictive one wins.  
If a user instruction conflicts with a rule, surface the conflict and ask.  
Rules cannot be suspended by a workflow or skill — only by explicit, named,
per-session user authorization recorded in the session log.
