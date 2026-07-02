"""
ashparser — Fluent parser wrapper P[T, run]

P[T, run] is a zero-size compile-time struct that wraps any
`(Input) -> ParseResult[T]` parser.  All composition methods return new
P values — zero runtime overhead vs calling the underlying combinators.

Quick start:
    # pre-built alias + method chain
    var r = PDigit().p_many1().p_recognize().parse("123abc")
    # r.ok == True, r.get() == "123"

    # factory + sequential composition
    var tag_p  = p_tag["hello"]()
    var r2 = tag_p.p_skip(PWs()).parse("hello   rest")
    # r2.ok == True, r2.get() == "hello"

    # | operator for choice
    var da = PDigit() | PAlpha()
    chk("| alpha", da.parse("a").ok and da.parse("a").get() == 97)
"""
from ashparser.input  import Input
from ashparser.result import ParseResult
from ashparser.prim   import (
    satisfy, byte, tag,
    digit, alpha, alphanum, ws, digits, ident, eof,
    one_of, none_of,
    line_ending, rest_of_line,
    hex_digit, hex_digits,
    parse_uint, parse_int, parse_float,
    quoted_string, any_byte, take, is_a, is_not,
)
from ashparser.comb   import (
    many, many1, map, attempt, choice,
    skip_left, skip_right, between,
    sep_by, sep_by1,
    peek, verify, skip_many, skip_many1,
    count, recognize, flat_map,
)


struct P[T: Copyable & Movable & ImplicitlyDeletable,
         run: def(Input) capturing -> ParseResult[T]](
    Copyable, Movable, ImplicitlyDeletable
):
    """
    Zero-size compile-time parser wrapper.

    `run` is the underlying parser — a compile-time type parameter.
    `T`   is the value type it produces.

    All methods return a new `P` parameterized on a composed parser.
    No fields.  No heap allocations.  Zero runtime overhead.

    Direct call:
        p(inp)           — returns ParseResult[T]
        p.parse("text")  — creates Input from a String, returns ParseResult[T]
    """
    def __init__(out self): pass
    def __copyinit__(out self, other: Self): pass
    def __moveinit__(out self, owned other: Self): pass

    # ── Call / convenience ────────────────────────────────────────────────────

    @always_inline
    def __call__(self, inp: Input) -> ParseResult[Self.T]:
        return Self.run(inp)^

    @always_inline
    def parse(self, s: String) -> ParseResult[Self.T]:
        """Parse a String directly — creates Input internally."""
        return Self.run(Input.from_string(s))^

    # ── Repetition ────────────────────────────────────────────────────────────

    @always_inline
    def p_many(self) -> P[List[Self.T], many[Self.T, Self.run]]:
        """Zero-or-more; always succeeds."""
        return P[List[Self.T], many[Self.T, Self.run]]()

    @always_inline
    def p_many1(self) -> P[List[Self.T], many1[Self.T, Self.run]]:
        """One-or-more; fails on zero matches."""
        return P[List[Self.T], many1[Self.T, Self.run]]()

    @always_inline
    def p_skip_many(self) -> P[UInt8, skip_many[Self.T, Self.run]]:
        """Zero-or-more, discarding results; always succeeds."""
        return P[UInt8, skip_many[Self.T, Self.run]]()

    @always_inline
    def p_skip_many1(self) -> P[UInt8, skip_many1[Self.T, Self.run]]:
        """One-or-more, discarding results; fails on zero matches."""
        return P[UInt8, skip_many1[Self.T, Self.run]]()

    @always_inline
    def p_count[N: Int](self) -> P[List[Self.T], count[Self.T, Self.run, N]]:
        """Exactly N repetitions; backtracks on failure."""
        return P[List[Self.T], count[Self.T, Self.run, N]]()

    # ── Transformation ────────────────────────────────────────────────────────

    @always_inline
    def p_map[U: Copyable & Movable & ImplicitlyDeletable,
              f: def(Self.T) capturing -> U](self) -> P[U, map[Self.T, U, Self.run, f]]:
        """Apply f to the parsed value."""
        return P[U, map[Self.T, U, Self.run, f]]()

    @always_inline
    def p_verify[pred: def(Self.T) capturing -> Bool](
        self
    ) -> P[Self.T, verify[Self.T, Self.run, pred]]:
        """Fail if pred(value) is False after a successful parse."""
        return P[Self.T, verify[Self.T, Self.run, pred]]()

    @always_inline
    def p_flat_map[U: Copyable & Movable & ImplicitlyDeletable,
                   f: def(Self.T, Input) capturing -> ParseResult[U]](
        self
    ) -> P[U, flat_map[Self.T, U, Self.run, f]]:
        """Dependent sequencing: parse self, then pass (value, rest) to f."""
        return P[U, flat_map[Self.T, U, Self.run, f]]()

    @always_inline
    def p_recognize(self) -> P[String, recognize[Self.T, Self.run]]:
        """Return the bytes consumed by self as a String (self's own result is discarded)."""
        return P[String, recognize[Self.T, Self.run]]()

    # ── Control flow ──────────────────────────────────────────────────────────

    @always_inline
    def p_attempt(self) -> P[Self.T, attempt[Self.T, Self.run]]:
        """Backtrack to the original position on failure."""
        return P[Self.T, attempt[Self.T, Self.run]]()

    @always_inline
    def p_peek(self) -> P[Self.T, peek[Self.T, Self.run]]:
        """Match without consuming input (non-destructive lookahead)."""
        return P[Self.T, peek[Self.T, Self.run]]()

    # ── Sequential composition ────────────────────────────────────────────────

    @always_inline
    def p_then[B: Copyable & Movable & ImplicitlyDeletable,
               q: def(Input) capturing -> ParseResult[B]](
        self, other: P[B, q]
    ) -> P[B, skip_left[Self.T, B, Self.run, q]]:
        """Run self then other; return other's result (discard self's)."""
        return P[B, skip_left[Self.T, B, Self.run, q]]()

    @always_inline
    def p_skip[B: Copyable & Movable & ImplicitlyDeletable,
               q: def(Input) capturing -> ParseResult[B]](
        self, other: P[B, q]
    ) -> P[Self.T, skip_right[Self.T, B, Self.run, q]]:
        """Run self then other; return self's result (discard other's)."""
        return P[Self.T, skip_right[Self.T, B, Self.run, q]]()

    @always_inline
    def p_between[L: Copyable & Movable & ImplicitlyDeletable,
                  R: Copyable & Movable & ImplicitlyDeletable,
                  lp: def(Input) capturing -> ParseResult[L],
                  rp: def(Input) capturing -> ParseResult[R]](
        self, left: P[L, lp], right: P[R, rp]
    ) -> P[Self.T, between[L, Self.T, R, lp, Self.run, rp]]:
        """Parse left self right; return self's result (discard delimiters)."""
        return P[Self.T, between[L, Self.T, R, lp, Self.run, rp]]()

    @always_inline
    def p_sep_by[S: Copyable & Movable & ImplicitlyDeletable,
                 sep: def(Input) capturing -> ParseResult[S]](
        self, separator: P[S, sep]
    ) -> P[List[Self.T], sep_by[Self.T, S, Self.run, sep]]:
        """Zero-or-more self separated by separator; always succeeds."""
        return P[List[Self.T], sep_by[Self.T, S, Self.run, sep]]()

    @always_inline
    def p_sep_by1[S: Copyable & Movable & ImplicitlyDeletable,
                  sep: def(Input) capturing -> ParseResult[S]](
        self, separator: P[S, sep]
    ) -> P[List[Self.T], sep_by1[Self.T, S, Self.run, sep]]:
        """One-or-more self separated by separator; fails on zero matches."""
        return P[List[Self.T], sep_by1[Self.T, S, Self.run, sep]]()

    # ── Choice ────────────────────────────────────────────────────────────────

    @always_inline
    def __or__[q: def(Input) capturing -> ParseResult[Self.T]](
        self, other: P[Self.T, q]
    ) -> P[Self.T, choice[Self.T, Self.run, q]]:
        """Try self; on failure try other on the same input."""
        return P[Self.T, choice[Self.T, Self.run, q]]()


# ── Factory functions ─────────────────────────────────────────────────────────

@always_inline
def p_byte[B: UInt8]() -> P[UInt8, byte[B]]:
    """Parser for exact byte B."""
    return P[UInt8, byte[B]]()

@always_inline
def p_tag[s: StringLiteral]() -> P[String, tag[s]]:
    """Parser for exact string literal s."""
    return P[String, tag[s]]()

@always_inline
def p_satisfy[pred: def(UInt8) capturing -> Bool]() -> P[UInt8, satisfy[pred]]:
    """Parser consuming one byte satisfying pred."""
    return P[UInt8, satisfy[pred]]()

@always_inline
def p_one_of[chars: StringLiteral]() -> P[UInt8, one_of[chars]]:
    """Parser consuming a byte that appears in chars."""
    return P[UInt8, one_of[chars]]()

@always_inline
def p_none_of[chars: StringLiteral]() -> P[UInt8, none_of[chars]]:
    """Parser consuming a byte not in chars."""
    return P[UInt8, none_of[chars]]()

@always_inline
def p_take[N: Int]() -> P[String, take[N]]:
    """Parser consuming exactly N bytes as a String."""
    return P[String, take[N]]()

@always_inline
def p_is_a[chars: StringLiteral]() -> P[String, is_a[chars]]:
    """Parser consuming one or more bytes each present in chars."""
    return P[String, is_a[chars]]()

@always_inline
def p_is_not[chars: StringLiteral]() -> P[String, is_not[chars]]:
    """Parser consuming one or more bytes each absent from chars."""
    return P[String, is_not[chars]]()


# ── Pre-built parser type aliases ─────────────────────────────────────────────
# Instantiate with `PDigit()`, `PInt()`, etc.

alias PDigit     = P[UInt8,   digit]
alias PAlpha     = P[UInt8,   alpha]
alias PAlphanum  = P[UInt8,   alphanum]
alias PWs        = P[String,  ws]
alias PDigits    = P[String,  digits]
alias PIdent     = P[String,  ident]
alias PEof       = P[UInt8,   eof]
alias PAny       = P[UInt8,   any_byte]
alias PHexDigit  = P[UInt8,   hex_digit]
alias PHexDigits = P[String,  hex_digits]
alias PUint      = P[UInt64,  parse_uint]
alias PInt       = P[Int64,   parse_int]
alias PFloat     = P[Float64, parse_float]
alias PQuoted    = P[String,  quoted_string]
alias PLineEnd   = P[String,  line_ending]
alias PRestLine  = P[String,  rest_of_line]
