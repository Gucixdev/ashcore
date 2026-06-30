# Lazytools / Sys

Tools for shell, filesystem, processes, environment, and git plumbing.

---

## git_status

Working tree state.

```
tool:   bash
cmd:    git status --short
output: M/A/D/? lines
```

---

## git_log_branch

Commits on current branch since divergence from main.

```
tool:   bash
cmd:    git log main..HEAD --oneline
output: sha + subject lines
```

---

## git_branch_current

Name of the checked-out branch.

```
tool:   bash
cmd:    git branch --show-current
output: branch name string
```

---

## git_remote_branches

All remote branches.

```
tool:   bash
cmd:    git branch -r --format='%(refname:short)'
output: list of remote/branch names
```

---

## list_files

Glob files matching a pattern.

```
tool:   glob
params: pattern, path=cwd
output: sorted list of file paths
```

---

## check_file_exists

Check if a path exists.

```
tool:   bash
cmd:    test -e <path> && echo exists || echo missing
output: "exists" or "missing"
```

---

## read_env

Read current environment variable values.

```
tool:   bash
cmd:    printenv | grep <pattern>
output: KEY=VALUE lines
```

---

## process_list

Running processes matching a name.

```
tool:   bash
cmd:    pgrep -la <name>
output: pid + name lines
```

---

## disk_usage

Directory size breakdown.

```
tool:   bash
cmd:    du -sh <path>/*
output: size + path lines
```

---

## tail_log

Last N lines of a log file.

```
tool:   read
params: file_path, offset=-N (last N lines via limit)
output: log tail
```
