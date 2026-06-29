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
        rest — Remaining input after consuming (valid only when ok == True).
        msg  — Error description (valid only when ok == False).
    """
    var ok:    Bool
    var _val:  Optional[Self.T]
    var rest:  Input
    var msg:   String

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
