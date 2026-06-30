# Lazytools / Code

Tools for reading, analyzing, and transforming source code.

---

## codemap

Produce a structural outline of the codebase: files, symbols, call graph.

```
tool:   search / glob + read
params: root=cwd, depth=3, include_symbols=true
output: tree of file paths → [functions, structs, traits]
```

---

## diff_staged

Show what's about to be committed.

```
tool:   bash
cmd:    git diff --cached
output: unified diff, stdout
```

---

## diff_working

Show all unstaged changes.

```
tool:   bash
cmd:    git diff
output: unified diff, stdout
```

---

## search_symbol

Find where a symbol is defined.

```
tool:   grep
params: pattern=<symbol>, output_mode=content, -n=true, context=2
output: file:line matches
```

---

## search_usage

Find all usages of a symbol.

```
tool:   grep
params: pattern=\b<symbol>\b, output_mode=files_with_matches
output: list of files
```

---

## read_file_range

Read a specific line range from a file.

```
tool:   read
params: file_path, offset=<start>, limit=<count>
output: file content with line numbers
```

---

## run_tests

Run the project test suite.

```
tool:   bash
cmd:    project-specific (./test, cargo test, pytest, etc.)
output: test results, exit code
```

---

## check_types

Run the type checker.

```
tool:   bash
cmd:    project-specific (tsc --noEmit, mypy, cargo check, etc.)
output: type errors, exit code
```

---

## list_todos

Find TODO/FIXME/HACK comments.

```
tool:   grep
params: pattern=(TODO|FIXME|HACK|XXX), output_mode=content, -n=true
output: file:line matches
```

---

## show_imports

List all import statements in a file.

```
tool:   grep
params: pattern=^(import|from|use|require|#include), output_mode=content
output: import lines
```
