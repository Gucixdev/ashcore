# freshdocs

Always fetch authoritative, up-to-date documentation before using an API.

## Problem

LLMs have a knowledge cutoff. APIs change. Using cached/trained knowledge for
current API usage → wrong code, deprecated methods, broken calls.

## freshdocs rule

Before using any external API, library, or service:
1. Fetch official docs via `fetch_url`
2. Inject as `AUTH_FETCHED` chunk in context_engine
3. Expire after `FRESH_FETCHED` seconds (3600s default)

## Priority in context_engine

| Source          | Freshness   | Authority      |
|-----------------|-------------|----------------|
| freshdocs fetch | FRESH_FETCHED (1h) | AUTH_FETCHED |
| repo-local docs | FRESH_REPO (always) | AUTH_REPO |
| trained knowledge | stale      | don't use alone |

## Integration

```mojo
var doc = fetch_json("https://docs.modular.com/mojo/stdlib/builtins/string/")
var chunk = ContextChunk(
    key="mojo_string_api",
    content=doc,
    priority=PRI_HIGH,
    authority=AUTH_FETCHED,
    freshness=FRESH_FETCHED,
)
ctx_engine.add(chunk)
```

## Which docs to freshdocs

- Mojo stdlib: docs.modular.com/mojo
- MAX API: docs.modular.com/max
- Any MCP server's tool schema before calling it
- pixi.toml package versions before pinning deps
