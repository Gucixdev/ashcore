"""
ashparser — Combinators

All parsers passed to combinators MUST be `@parameter def` functions.
Combinators are themselves `@parameter def` — compose at compile time.

Constraint shorthand used throughout:
    P = def(Input) capturing -> ParseResult[T]
    F = def(T) capturing -> U
"""
from ashparser.input  import Input
from ashparser.result import ParseResult


# ── Pair ─────────────────────────────────────────────────────────────────────

struct Pair[A: Copyable & Movable & ImplicitlyDeletable,
            B: Copyable & Movable & ImplicitlyDeletable](
    Copyable, Movable, ImplicitlyDeletable
):
    """Two-element product type for seq combinator."""
    var first:  Self.A
    var second: Self.B

    def __init__(out self, a: Self.A, b: Self.B):
        self.first  = a.copy()
        self.second = b.copy()


# ── opt ───────────────────────────────────────────────────────────────────────

@parameter
def opt[T: Copyable & Movable & ImplicitlyDeletable,
        p: def(Input) capturing -> ParseResult[T]](
    default: T, inp: Input) -> ParseResult[T]:
    """Try p; if it fails return `default` without consuming input."""
    var r = p(inp)
    if r.ok:
        return r^
    var out = ParseResult[T].success(default, inp)
    return out^


# ── many / many1 ─────────────────────────────────────────────────────────────

@parameter
def many[T: Copyable & Movable & ImplicitlyDeletable,
         p: def(Input) capturing -> ParseResult[T]](
    inp: Input) -> ParseResult[List[T]]:
    """Zero-or-more applications of p.  Always succeeds."""
    var results = List[T]()
    var cur = inp
    while True:
        var r = p(cur)
        if not r.ok:
            break
        results.append(r.get())
        cur = r.rest
    var out = ParseResult[List[T]].success(results, cur)
    return out^


@parameter
def many1[T: Copyable & Movable & ImplicitlyDeletable,
          p: def(Input) capturing -> ParseResult[T]](
    inp: Input) -> ParseResult[List[T]]:
    """One-or-more applications of p.  Fails if zero matches."""
    var r0 = p(inp)
    if not r0.ok:
        var out = ParseResult[List[T]].failure(inp, "many1: zero matches at pos " + String(inp.pos))
        return out^
    var results = List[T]()
    results.append(r0.get())
    var cur = r0.rest
    while True:
        var r = p(cur)
        if not r.ok:
            break
        results.append(r.get())
        cur = r.rest
    var out = ParseResult[List[T]].success(results, cur)
    return out^


# ── map ───────────────────────────────────────────────────────────────────────

@parameter
def map[T: Copyable & Movable & ImplicitlyDeletable,
        U: Copyable & Movable & ImplicitlyDeletable,
        p: def(Input) capturing -> ParseResult[T],
        f: def(T) capturing -> U](inp: Input) -> ParseResult[U]:
    """Apply f to the successful result of p."""
    var r = p(inp)
    if not r.ok:
        var out = ParseResult[U].failure(r.rest, r.msg)
        return out^
    var val = f(r.get())
    var out = ParseResult[U].success(val, r.rest)
    return out^


# ── choice ───────────────────────────────────────────────────────────────────

@parameter
def choice[T: Copyable & Movable & ImplicitlyDeletable,
           p: def(Input) capturing -> ParseResult[T],
           q: def(Input) capturing -> ParseResult[T]](inp: Input) -> ParseResult[T]:
    """Try p; if it fails (without consuming) try q on the same input."""
    var r = p(inp)
    if r.ok:
        return r^
    var r2 = q(inp)
    return r2^


# ── seq / skip_left / skip_right / between ────────────────────────────────────

@parameter
def seq[A: Copyable & Movable & ImplicitlyDeletable,
        B: Copyable & Movable & ImplicitlyDeletable,
        p: def(Input) capturing -> ParseResult[A],
        q: def(Input) capturing -> ParseResult[B]](inp: Input) -> ParseResult[Pair[A, B]]:
    """Run p then q; return both results as a Pair."""
    var ra = p(inp)
    if not ra.ok:
        var out = ParseResult[Pair[A, B]].failure(inp, ra.msg)
        return out^
    var rb = q(ra.rest)
    if not rb.ok:
        var out = ParseResult[Pair[A, B]].failure(inp, rb.msg)
        return out^
    var pair = Pair[A, B](ra.get(), rb.get())
    var out = ParseResult[Pair[A, B]].success(pair, rb.rest)
    return out^


@parameter
def skip_left[A: Copyable & Movable & ImplicitlyDeletable,
              B: Copyable & Movable & ImplicitlyDeletable,
              p: def(Input) capturing -> ParseResult[A],
              q: def(Input) capturing -> ParseResult[B]](inp: Input) -> ParseResult[B]:
    """Run p then q; discard p result, return q result."""
    var ra = p(inp)
    if not ra.ok:
        var out = ParseResult[B].failure(inp, ra.msg)
        return out^
    var rb = q(ra.rest)
    return rb^


@parameter
def skip_right[A: Copyable & Movable & ImplicitlyDeletable,
               B: Copyable & Movable & ImplicitlyDeletable,
               p: def(Input) capturing -> ParseResult[A],
               q: def(Input) capturing -> ParseResult[B]](inp: Input) -> ParseResult[A]:
    """Run p then q; discard q result, return p result."""
    var ra = p(inp)
    if not ra.ok:
        var out = ParseResult[A].failure(inp, ra.msg)
        return out^
    var rb = q(ra.rest)
    if not rb.ok:
        var out = ParseResult[A].failure(inp, rb.msg)
        return out^
    var out = ParseResult[A].success(ra.get(), rb.rest)
    return out^


@parameter
def between[L: Copyable & Movable & ImplicitlyDeletable,
            T: Copyable & Movable & ImplicitlyDeletable,
            R: Copyable & Movable & ImplicitlyDeletable,
            lp: def(Input) capturing -> ParseResult[L],
            p:  def(Input) capturing -> ParseResult[T],
            rp: def(Input) capturing -> ParseResult[R]](inp: Input) -> ParseResult[T]:
    """Parse `lp p rp`, return p result (discard delimiters)."""
    var rl = lp(inp)
    if not rl.ok:
        var out = ParseResult[T].failure(inp, rl.msg)
        return out^
    var rm = p(rl.rest)
    if not rm.ok:
        var out = ParseResult[T].failure(inp, rm.msg)
        return out^
    var rr = rp(rm.rest)
    if not rr.ok:
        var out = ParseResult[T].failure(inp, rr.msg)
        return out^
    var out = ParseResult[T].success(rm.get(), rr.rest)
    return out^


# ── sep_by / sep_by1 ─────────────────────────────────────────────────────────

@parameter
def sep_by[T: Copyable & Movable & ImplicitlyDeletable,
           S: Copyable & Movable & ImplicitlyDeletable,
           p: def(Input) capturing -> ParseResult[T],
           s: def(Input) capturing -> ParseResult[S]](inp: Input) -> ParseResult[List[T]]:
    """Zero-or-more p separated by s.  Always succeeds."""
    var results = List[T]()
    var r0 = p(inp)
    if not r0.ok:
        var out = ParseResult[List[T]].success(results, inp)
        return out^
    results.append(r0.get())
    var cur = r0.rest
    while True:
        var rs = s(cur)
        if not rs.ok:
            break
        var rp = p(rs.rest)
        if not rp.ok:
            break
        results.append(rp.get())
        cur = rp.rest
    var out = ParseResult[List[T]].success(results, cur)
    return out^


@parameter
def sep_by1[T: Copyable & Movable & ImplicitlyDeletable,
            S: Copyable & Movable & ImplicitlyDeletable,
            p: def(Input) capturing -> ParseResult[T],
            s: def(Input) capturing -> ParseResult[S]](inp: Input) -> ParseResult[List[T]]:
    """One-or-more p separated by s.  Fails if zero matches."""
    var r0 = p(inp)
    if not r0.ok:
        var out = ParseResult[List[T]].failure(inp, "sep_by1: no match at pos " + String(inp.pos))
        return out^
    var results = List[T]()
    results.append(r0.get())
    var cur = r0.rest
    while True:
        var rs = s(cur)
        if not rs.ok:
            break
        var rp = p(rs.rest)
        if not rp.ok:
            break
        results.append(rp.get())
        cur = rp.rest
    var out = ParseResult[List[T]].success(results, cur)
    return out^


# ── peek / not_followed_by ────────────────────────────────────────────────────

@parameter
def peek[T: Copyable & Movable & ImplicitlyDeletable,
         p: def(Input) capturing -> ParseResult[T]](inp: Input) -> ParseResult[T]:
    """Try p without consuming input.  Succeeds (returning p's value) if p succeeds."""
    var r = p(inp)
    if not r.ok:
        var out = ParseResult[T].failure(inp, r.msg)
        return out^
    var out = ParseResult[T].success(r.get(), inp)
    return out^


@parameter
def not_followed_by[T: Copyable & Movable & ImplicitlyDeletable,
                    p: def(Input) capturing -> ParseResult[T]](inp: Input) -> ParseResult[UInt8]:
    """Succeed (returning 0) only if p would FAIL at current position.  Consumes nothing."""
    var r = p(inp)
    if r.ok:
        var out = ParseResult[UInt8].failure(inp, "not_followed_by: unexpected match at pos " + String(inp.pos))
        return out^
    var out = ParseResult[UInt8].success(0, inp)
    return out^


# ── verify ────────────────────────────────────────────────────────────────────

@parameter
def verify[T: Copyable & Movable & ImplicitlyDeletable,
           p: def(Input) capturing -> ParseResult[T],
           pred: def(T) capturing -> Bool](inp: Input) -> ParseResult[T]:
    """Run p, then apply pred to the value.  Fails if pred returns False."""
    var r = p(inp)
    if not r.ok:
        var out = ParseResult[T].failure(inp, r.msg)
        return out^
    if not pred(r.get()):
        var out = ParseResult[T].failure(inp, "verify: predicate failed at pos " + String(inp.pos))
        return out^
    return r^


# ── skip_many / skip_many1 ────────────────────────────────────────────────────

@parameter
def skip_many[T: Copyable & Movable & ImplicitlyDeletable,
              p: def(Input) capturing -> ParseResult[T]](inp: Input) -> ParseResult[UInt8]:
    """Zero-or-more applications of p, discarding all results.  Always succeeds."""
    var cur = inp
    while True:
        var r = p(cur)
        if not r.ok:
            break
        cur = r.rest
    var out = ParseResult[UInt8].success(0, cur)
    return out^


@parameter
def skip_many1[T: Copyable & Movable & ImplicitlyDeletable,
               p: def(Input) capturing -> ParseResult[T]](inp: Input) -> ParseResult[UInt8]:
    """One-or-more applications of p, discarding all results.  Fails if zero matches."""
    var r0 = p(inp)
    if not r0.ok:
        var out = ParseResult[UInt8].failure(inp, "skip_many1: zero matches at pos " + String(inp.pos))
        return out^
    var cur = r0.rest
    while True:
        var r = p(cur)
        if not r.ok:
            break
        cur = r.rest
    var out = ParseResult[UInt8].success(0, cur)
    return out^


# ── count ─────────────────────────────────────────────────────────────────────

@parameter
def count[T: Copyable & Movable & ImplicitlyDeletable,
          p: def(Input) capturing -> ParseResult[T],
          N: Int](inp: Input) -> ParseResult[List[T]]:
    """Exactly N applications of p.  Fails (backtracking to inp) if any application fails."""
    var results = List[T]()
    var cur = inp
    for _ in range(N):
        var r = p(cur)
        if not r.ok:
            var out = ParseResult[List[T]].failure(inp, "count: failed after " + String(len(results)) + " of " + String(N))
            return out^
        results.append(r.get())
        cur = r.rest
    var out = ParseResult[List[T]].success(results, cur)
    return out^


# ── recognize ─────────────────────────────────────────────────────────────────

@parameter
def recognize[T: Copyable & Movable & ImplicitlyDeletable,
              p: def(Input) capturing -> ParseResult[T]](inp: Input) -> ParseResult[String]:
    """Run p; return the bytes consumed as a String (p's own result is discarded)."""
    var start = inp.pos
    var r = p(inp)
    if not r.ok:
        var out = ParseResult[String].failure(inp, r.msg)
        return out^
    var out = ParseResult[String].success(inp.slice_str(start, r.rest.pos), r.rest)
    return out^
