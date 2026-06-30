# Lazytools

Pre-composed tool invocations. Each lazytool calls exactly one underlying tool
with a fixed set of parameters. No branching. No composition. Logic lives in
skills; lazytools are leaves.

**Rule:** a lazytool that calls another lazytool is no longer a lazytool — it's
a skill. Promote it.

---

## Categories

| Folder | Tools |
|--------|-------|
| [`code/`](code/README.md) | linters, formatters, static analysis, codemap, diff |
| [`sys/`](sys/README.md) | shell, process, filesystem, env, git plumbing |
| [`web/`](web/README.md) | HTTP, search, scrape, download |

---

## Naming Convention

```
<verb>_<noun>[_<qualifier>]

read_file
write_file
search_symbol
run_tests
diff_staged
fetch_url
```

Verbs: `read` `write` `run` `search` `fetch` `diff` `list` `delete` `check`  
Nouns: `file` `dir` `symbol` `branch` `url` `env` `process` `log`  
Qualifiers: `staged` `cached` `remote` `current` `all`

---

## Registration

Each lazytool is a single entry in its category README with:
- name
- what it calls
- fixed parameters
- output shape

No prose. No rationale. Just the contract.
