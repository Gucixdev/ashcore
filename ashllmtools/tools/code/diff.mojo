"""tools.code.diff — diff helpers: staged, unstaged, file, branch comparisons."""

from tools.sys.shell import shell_run


def diff_staged() -> String:
    """Return `git diff --cached` (staged changes)."""
    var r = shell_run("git diff --cached 2>/dev/null")
    return r.stdout if r.ok else String("")


def diff_unstaged() -> String:
    """Return `git diff` (unstaged working tree changes)."""
    var r = shell_run("git diff 2>/dev/null")
    return r.stdout if r.ok else String("")


def diff_files(a: String, b: String) -> String:
    """Unified diff between two files."""
    var r = shell_run("diff -u " + a + " " + b + " 2>/dev/null")
    return r.stdout


def diff_branch(base: String = "main") -> String:
    """Diff of current branch vs base branch."""
    var r = shell_run("git diff " + base + "...HEAD 2>/dev/null")
    return r.stdout if r.ok else String("")


def diff_stat() -> String:
    """Return `git diff --stat` summary (no line content)."""
    var r = shell_run("git diff --stat 2>/dev/null")
    return r.stdout if r.ok else String("")
