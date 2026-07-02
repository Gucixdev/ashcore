"""tools.sys.fs — lazytools: filesystem read/write/exist/list/tree/info/scan_log."""

from std.pathlib import Path
from std.memory import UnsafePointer
from tools.sys.shell import shell_run


def file_exists(path: String) -> Bool:
    """True iff the path exists on disk."""
    return Path(path).exists()


def read_text(path: String) -> String:
    """Read entire file as a String. Returns "" on error."""
    try:
        return Path(path).read_text()
    except:
        return String("")


def write_text(path: String, content: String) raises:
    """Write content to path (creates or overwrites)."""
    Path(path).write_text(content)


def list_dir(path: String) -> List[String]:
    """List immediate children of a directory. Empty list on error."""
    var r = shell_run("ls -1 " + path + " 2>/dev/null")
    var result = List[String]()
    if not r.ok or r.stdout == "":
        return result^
    var s = r.stdout
    var ptr = s.unsafe_ptr()
    var start = 0
    for i in range(s.byte_length()):
        if ptr[i] == UInt8(10):
            if i > start:
                result.append(String(StringSlice(ptr=ptr + start, length=i - start)))
            start = i + 1
    if start < s.byte_length():
        result.append(String(StringSlice(ptr=ptr + start, length=s.byte_length() - start)))
    return result^


def show_tree(path: String, max_depth: Int = 3) -> String:
    """
    Return a directory tree rooted at path.
    Uses tree(1) if available; falls back to find with depth limit.
    """
    var r = shell_run(
        "tree -L " + String(max_depth) + " --noreport " + path + " 2>/dev/null"
    )
    if r.ok and r.stdout != "":
        return r.stdout
    var fb = shell_run(
        "find " + path + " -maxdepth " + String(max_depth) + " 2>/dev/null | sort"
    )
    if not fb.ok or fb.stdout == "":
        return path + " (empty or not found)"
    return fb.stdout


def file_info(path: String) -> String:
    """
    File/dir metadata: type, size, permissions, mtime, line count, disk usage.
    """
    var stat_r = shell_run(
        "stat --printf='type=%F\\nsize=%s bytes\\nperm=%A\\nmtime=%y\\n' "
        + path + " 2>/dev/null"
    )
    if not stat_r.ok or stat_r.stdout == "":
        return "file_info: not found: " + path

    var out = stat_r.stdout

    var wc_r = shell_run("wc -l < " + path + " 2>/dev/null")
    if wc_r.ok and wc_r.stdout != "":
        var lc = _trim(wc_r.stdout)
        if lc != "":
            out = out + "lines=" + lc + "\n"

    var du_r = shell_run("du -sh " + path + " 2>/dev/null")
    if du_r.ok and du_r.stdout != "":
        var parts = _split_tab(du_r.stdout)
        if len(parts) >= 1:
            out = out + "disk_usage=" + parts[0] + "\n"

    return out^


def system_info() -> String:
    """
    System snapshot: OS, hostname, CPU, RAM, disk, load average, uptime.
    """
    var out = String("")

    var uname = shell_run("uname -srm 2>/dev/null")
    if uname.ok:
        out = out + "kernel=" + _trim(uname.stdout) + "\n"

    var host = shell_run("hostname 2>/dev/null")
    if host.ok:
        out = out + "hostname=" + _trim(host.stdout) + "\n"

    var cpu = shell_run("grep -c '^processor' /proc/cpuinfo 2>/dev/null")
    if cpu.ok and cpu.stdout != "":
        out = out + "cpu_cores=" + _trim(cpu.stdout) + "\n"

    var cpu_model = shell_run(
        "grep 'model name' /proc/cpuinfo 2>/dev/null | head -1 | cut -d: -f2"
    )
    if cpu_model.ok and cpu_model.stdout != "":
        out = out + "cpu_model=" + _trim(cpu_model.stdout) + "\n"

    var mem = shell_run(
        "free -h 2>/dev/null | awk '/^Mem:/ {print $2\" total, \"$3\" used, \"$7\" available\"}'"
    )
    if mem.ok and mem.stdout != "":
        out = out + "ram=" + _trim(mem.stdout) + "\n"

    var disk = shell_run(
        "df -h . 2>/dev/null | awk 'NR==2 {print $2\" total, \"$3\" used, \"$4\" free, \"$5\" use%\"}'"
    )
    if disk.ok and disk.stdout != "":
        out = out + "disk=" + _trim(disk.stdout) + "\n"

    var load = shell_run("cat /proc/loadavg 2>/dev/null | cut -d' ' -f1-3")
    if load.ok and load.stdout != "":
        out = out + "load_avg=" + _trim(load.stdout) + "\n"

    var up = shell_run("uptime -p 2>/dev/null")
    if up.ok and up.stdout != "":
        out = out + "uptime=" + _trim(up.stdout) + "\n"

    return out if out != "" else String("system_info: unavailable")


def scan_log(path: String,
             pattern: String = "",
             last_n:  Int    = 50,
             level:   String = "") -> String:
    """
    Scan a log file and return relevant lines.

    path    — log file path
    pattern — grep pattern to filter (empty = all lines)
    last_n  — return at most this many lines (tail after filter)
    level   — shorthand filter: "error", "warn", "debug", "info"
               (appended to pattern with OR if both given)

    Examples:
        scan_log("/var/log/syslog", last_n=20)
        scan_log("app.log", pattern="timeout")
        scan_log("app.log", level="error")
        scan_log("app.log", level="error", pattern="database", last_n=10)
    """
    if not file_exists(path):
        return "scan_log: file not found: " + path

    # Build the level pattern
    var lvl_pat = String("")
    if level == "error":
        lvl_pat = "ERROR\\|error\\|FATAL\\|fatal\\|CRIT\\|crit"
    elif level == "warn":
        lvl_pat = "WARN\\|warn\\|WARNING\\|warning"
    elif level == "debug":
        lvl_pat = "DEBUG\\|debug"
    elif level == "info":
        lvl_pat = "INFO\\|info"

    # Combine patterns
    var combined = String("")
    if pattern != "" and lvl_pat != "":
        combined = "(" + pattern + ")\\|(" + lvl_pat + ")"
    elif pattern != "":
        combined = pattern
    elif lvl_pat != "":
        combined = lvl_pat

    # Build pipeline: optional grep | tail
    var cmd = String("")
    if combined != "":
        cmd = "grep -E '" + combined + "' " + path + " 2>/dev/null | tail -n " + String(last_n)
    else:
        cmd = "tail -n " + String(last_n) + " " + path + " 2>/dev/null"

    var r = shell_run(cmd)
    if not r.ok or r.stdout == "":
        return "scan_log: no matches in " + path
    return r.stdout


# ── private helpers ───────────────────────────────────────────────────────────

def _trim(s: String) -> String:
    """Strip leading and trailing whitespace/newlines."""
    var ptr = s.unsafe_ptr()
    var bl  = s.byte_length()
    var lo  = 0
    var hi  = bl
    while lo < hi and (ptr[lo] == UInt8(32) or ptr[lo] == UInt8(9)
                       or ptr[lo] == UInt8(10) or ptr[lo] == UInt8(13)):
        lo += 1
    while hi > lo and (ptr[hi - 1] == UInt8(32) or ptr[hi - 1] == UInt8(9)
                       or ptr[hi - 1] == UInt8(10) or ptr[hi - 1] == UInt8(13)):
        hi -= 1
    if lo >= hi:
        return String("")
    return String(StringSlice(ptr=ptr + lo, length=hi - lo))


def _split_tab(s: String) -> List[String]:
    """Split on tab character."""
    var result = List[String]()
    var ptr    = s.unsafe_ptr()
    var bl     = s.byte_length()
    var start  = 0
    for i in range(bl):
        if ptr[i] == UInt8(9):
            if i > start:
                result.append(String(StringSlice(ptr=ptr + start, length=i - start)))
            start = i + 1
    if start < bl:
        result.append(String(StringSlice(ptr=ptr + start, length=bl - start)))
    return result^
