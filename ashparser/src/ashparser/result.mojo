"""
ashparser — ParseResult[T]

Represents the outcome of a parser: either success (value + remaining input)
or failure (error message + original input for backtracking).
"""
from ashparser.input import Input


struct ParseResult[T: Copyable & Movable & ImplicitlyDeletable](
    Copyable, Movable, ImplicitlyDeletable
):
    """
    Parser output.  Always check `.ok` before calling `.get()`.

    Fields:
        ok   — True on success.
        rest — Remaining input after consuming (valid when ok == True).
               On failure, rest == the input position where failure occurred.
        msg  — Error description (valid when ok == False).

    Use `.message_ctx(original)` for line:col-annotated error strings.
    """
    var ok:   Bool
    var _val: Optional[Self.T]
    var rest: Input
    var msg:  String

    def __init__(out self, ok: Bool, val: Optional[Self.T], rest: Input, msg: String):
        self.ok   = ok
        self._val = val.copy()
        self.rest = rest.copy()
        self.msg  = msg

    @staticmethod
    def success(v: Self.T, r: Input) -> Self:
        return Self(True, Optional(v.copy()), r, "")

    @staticmethod
    def failure(inp: Input, msg: String) -> Self:
        return Self(False, Optional[Self.T](), inp, msg)

    @always_inline
    def get(self) -> Self.T:
        """Unwrap the parsed value.  Only call when ok == True."""
        return self._val.value().copy()

    def message_ctx(self, original: Input) -> String:
        """Format 'msg at L:C (byte N)' using line/col from original input."""
        var pos = self.rest.pos
        var ptr = original._ptr()
        var line = 1
        var col = 1
        for i in range(pos):
            if i < original.len and ptr[i] == 10:
                line += 1
                col = 1
            else:
                col += 1
        return (self.msg + " at " + String(line) + ":" + String(col)
                + " (byte " + String(pos) + ")")
