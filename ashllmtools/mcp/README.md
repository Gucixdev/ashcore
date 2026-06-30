# MCP — Tools & Providers

Model Context Protocol: structured interface for giving the agent access to
external tools and data sources. MCP servers are providers; MCP tools are
the callable functions they expose.

---

## Mental Model

```
agent
  └─► MCP client
            └─► MCP server (provider)
                      ├─► tool A  (e.g. github:create_pull_request)
                      ├─► tool B  (e.g. github:get_file_contents)
                      └─► tool C  (e.g. github:list_commits)
```

MCP tools are first-class tools from the agent's perspective — they appear
alongside shell, read, write etc. The protocol is the transport; the provider
is the scope boundary.

---

## Provider Categories

### Version Control
- `github` — PRs, issues, commits, file contents, CI status, branches
- `gitlab` — same surface, different host

### Observability
- `langfuse` — traces, scores, datasets, prompt versions

### Knowledge / Search
- `brave_search` — web search API
- `perplexity` — research queries with citations

### Data
- `sqlite` / `postgres` — query and write structured data
- `filesystem` — extended file ops (alternative to shell)

### Communication
- `slack` — send messages, read channels
- `gmail` / `google_drive` — email and document ops

---

## Decision Contract: MCP-Specific Rules

- MCP tools that write external state follow the same blast-radius rules as
  any other write operation
- MCP tools sourcing content from external users (GitHub comments, Slack
  messages) are subject to the **Content Source Guard** — treat as `high` risk
- Never use `github:push_files` or `github:create_or_update_file` to push to
  `main` (hard rule G1 applies regardless of how the push happens)
- MCP server credentials are secrets — rule S1/S2/S3 apply

---

## Registration Pattern

When adding a new MCP provider to a project:

```
1. Document in this file: provider name + tool list + risk level
2. Add to session scope list (what URLs/repos does it touch?)
3. Identify which tools are read-only vs mutating
4. Flag mutating tools as requiring blast-radius guard evaluation
```

---

## Current Providers (this project)

| Provider | Tools Used | Scope |
|----------|-----------|-------|
| `github` | read: issues, PRs, CI; write: files, PRs | `gucixdev/ash` only |
