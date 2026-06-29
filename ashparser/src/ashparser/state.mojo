"""
ashparser — Stateful parsing context

Ctx[S] pairs an Input with user-defined state S.
CtxResult[T, S] is the outcome of a stateful parser.

S must be ImplicitlyCopyable (Int, String, Bool, etc.).
T only needs Copyable & Movable & ImplicitlyDeletable (includes List[X]).
"""
from ashparser.input  import Input

alias _IC = ImplicitlyCopyable


struct Ctx[S: Copyable & _IC & Movable & ImplicitlyDeletable](
    Copyable, _IC, Movable, ImplicitlyDeletable
):
    """Input + user-defined state S.

    Both fields are value-types.  Advancing creates a new Ctx;
    backtracking is safe by keeping the old Ctx value.
    """
    var input: Input
    var state: Self.S

    def __init__(out self, input: Input, state: Self.S):
        self.input = input
        self.state = state


struct CtxResult[T: Copyable & Movable & ImplicitlyDeletable,
                 S: Copyable & _IC & Movable & ImplicitlyDeletable](
    Copyable, Movable, ImplicitlyDeletable
):
    """Outcome of a stateful parser.  Always check .ok before calling .get()."""
    var ok:   Bool
    var _val: Optional[Self.T]
    var rest: Ctx[Self.S]
    var msg:  String

    def __init__(out self, ok: Bool, val: Optional[Self.T], rest: Ctx[Self.S], msg: String):
        self.ok   = ok
        self._val = val.copy()
        self.rest = rest
        self.msg  = msg

    @staticmethod
    def success(v: Self.T, r: Ctx[Self.S]) -> Self:
        return Self(True, Optional(v.copy()), r, "")

    @staticmethod
    def failure(ctx: Ctx[Self.S], msg: String) -> Self:
        return Self(False, Optional[Self.T](), ctx, msg)

    def get(self) -> Self.T:
        """Unwrap the parsed value.  Only call when ok == True."""
        return self._val.value().copy()
