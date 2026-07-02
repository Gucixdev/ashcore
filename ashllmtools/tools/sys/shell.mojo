"""tools.sys.shell — lazytools: shell command execution via popen."""

from std.ffi import external_call
from std.memory import UnsafePointer

alias _FPTR = UnsafePointer[UInt8, MutAnyOrigin]   # opaque FILE*

comptime _BUF: Int = 4096


struct ShellResult(Copyable, ImplicitlyCopyable, Movable, ImplicitlyDeletable):
    """Output of a shell command: stdout string and success flag."""
    var stdout: String
    var ok:     Bool

    def __init__(out self, stdout: String, ok: Bool):
        self.stdout = stdout
        self.ok     = ok


def shell_run(cmd: String) -> ShellResult:
    """Run cmd in a subshell via popen(3); capture stdout."""
    var mode = String("r")
    var fp   = external_call["popen", _FPTR](cmd.unsafe_ptr(), mode.unsafe_ptr())
    if Int(fp) == 0:
        return ShellResult("", False)

    var buf = external_call["malloc", UnsafePointer[UInt8, MutAnyOrigin]](_BUF)
    var acc = List[UInt8]()
    while True:
        var n = external_call["fread", Int](buf, Int(1), Int(_BUF), fp)
        if n <= 0:
            break
        for i in range(n):
            acc.append(buf[i])
    _ = external_call["free", NoneType](buf)
    _ = external_call["pclose", Int32](fp)

    if len(acc) == 0:
        return ShellResult("", True)
    return ShellResult(
        String(StringSlice(ptr=acc.unsafe_ptr(), length=len(acc))), True
    )


def shell_ok(cmd: String) -> Bool:
    """Return True iff cmd exits with code 0."""
    return shell_run(cmd).ok
