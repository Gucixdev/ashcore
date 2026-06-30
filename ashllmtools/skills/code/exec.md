---
name: exec
category: code
---

Execute a shell command and return its output.

**Input:** shell command string
**Output:** stdout + exit code

Decision contract is evaluated BEFORE execution.
`RISK_BLOCK` commands (rm -rf, DROP TABLE, force-push to main) are rejected.
`RISK_HIGH` commands require `authorized=True` on the action.
