"""ashllmtools.tools.fs — lazytools: filesystem read/write/exist/list."""

from pathlib import Path
from std.memory import UnsafePointer
from ashllmtools.tools.shell import shell_run


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
        return result
    var s = r.stdout
    var ptr = s.unsafe_ptr()
    var start = 0
    for i in range(s.byte_length()):
        if ptr[i] == UInt8(10):  # '\n'
            if i > start:
                var entry = String(StringSlice(ptr=ptr + start, length=i - start))
                result.append(entry)
            start = i + 1
    if start < s.byte_length():
        var entry = String(StringSlice(ptr=ptr + start, length=s.byte_length() - start))
        result.append(entry)
    return result
