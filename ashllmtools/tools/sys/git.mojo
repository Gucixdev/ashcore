"""tools.sys.git — lazytools: git state via shell."""

from tools.sys.shell import shell_run, ShellResult


def git_branch_current() -> String:
    """Return the name of the currently checked-out branch."""
    var r = shell_run("git branch --show-current 2>/dev/null")
    if not r.ok:
        return String("(unknown)")
    return _trim(r.stdout)


def git_status() -> String:
    """Return `git status --short` output."""
    var r = shell_run("git status --short 2>/dev/null")
    if not r.ok:
        return String("")
    return r.stdout


def git_diff_staged() -> String:
    """Return `git diff --cached` output."""
    var r = shell_run("git diff --cached 2>/dev/null")
    if not r.ok:
        return String("")
    return r.stdout


def git_log(n: Int) -> String:
    """Return last n commit messages (one per line)."""
    var r = shell_run("git log --oneline -" + String(n) + " 2>/dev/null")
    if not r.ok:
        return String("")
    return r.stdout


def git_is_clean() -> Bool:
    """True iff working tree has no uncommitted changes."""
    var r = shell_run("git status --short 2>/dev/null")
    return r.ok and r.stdout == ""


def _trim(s: String) -> String:
    var end = s.byte_length()
    var ptr = s.unsafe_ptr()
    while end > 0 and (ptr[end - 1] == UInt8(10) or ptr[end - 1] == UInt8(13)
                       or ptr[end - 1] == UInt8(32)):
        end -= 1
    if end == 0:
        return String("")
    return String(StringSlice(ptr=ptr, length=end))
