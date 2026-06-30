"""
ashparser — Stateful combinators

Stateful parsers: (Ctx[S]) -> CtxResult[T, S]
State threads as an immutable value (State monad style).

slift        — promote a stateless parser to stateful (state unchanged)
sget         — read current state (no input consumed)
smodify      — transform state via @parameter def, no input consumed
smap         — apply function to successful result
sattempt     — run p; on failure reset to original ctx (input + state)
schoice      — ordered choice (try p, fallback to q on same ctx)
smany        — zero-or-more
smany1       — one-or-more
sskip_left   — run p then q, return q
sskip_right  — run p then q, return p
ssep_by      — zero-or-more separated by sep
ssep_by1     — one-or-more separated by sep
sseq         — run p then q, return Pair of both results
sbetween     — parse lp p rp, return p (discard delimiters)
scount       — exactly N applications of p
srecognize   — run p; return bytes consumed as String
svalue       — run p; on success return a constant instead
sflat_map    — dependent stateful sequencing (monadic bind)
sfold_many0  — fold zero-or-more results into an accumulator
sfold_many1  — fold one-or-more results into an accumulator
scond        — predicate-gated parsing
"""
from ashparser.input  import Input
from ashparser.result import ParseResult
from ashparser.state  import Ctx, CtxResult
from ashparser.comb   import Pair

alias IC = ImplicitlyCopyable


# ── slift ─────────────────────────────────────────────────────────────────────

@parameter
def slift[T: Copyable & IC & Movable & ImplicitlyDeletable,
          S: Copyable & IC & Movable & ImplicitlyDeletable,
          p: def(Input) capturing -> ParseResult[T]](
    ctx: Ctx[S]) -> CtxResult[T, S]:
    """Promote a stateless parser into a stateful one.  State passes through."""
    var r = p(ctx.input)
    if not r.ok:
        return CtxResult[T, S].failure(ctx, r.msg)^
    return CtxResult[T, S].success(r.get(), Ctx[S](r.rest, ctx.state))^


# ── sget / smodify ────────────────────────────────────────────────────────────

@parameter
def sget[S: Copyable & IC & Movable & ImplicitlyDeletable](
    ctx: Ctx[S]) -> CtxResult[S, S]:
    """Return the current state value; consume no input.  Always succeeds."""
    return CtxResult[S, S].success(ctx.state, ctx)^


@parameter
def smodify[S: Copyable & IC & Movable & ImplicitlyDeletable,
            f: def(S) capturing -> S](
    ctx: Ctx[S]) -> CtxResult[UInt8, S]:
    """Apply f to the current state; consume no input.  Returns 0."""
    return CtxResult[UInt8, S].success(0, Ctx[S](ctx.input, f(ctx.state)))^


# ── smap ──────────────────────────────────────────────────────────────────────

@parameter
def smap[T: Copyable & IC & Movable & ImplicitlyDeletable,
         U: Copyable & IC & Movable & ImplicitlyDeletable,
         S: Copyable & IC & Movable & ImplicitlyDeletable,
         p: def(Ctx[S]) capturing -> CtxResult[T, S],
         f: def(T) capturing -> U](
    ctx: Ctx[S]) -> CtxResult[U, S]:
    """Apply f to the successful result of stateful parser p."""
    var r = p(ctx)
    if not r.ok:
        return CtxResult[U, S].failure(ctx, r.msg)^
    return CtxResult[U, S].success(f(r.get()), r.rest)^


# ── sattempt ─────────────────────────────────────────────────────────────────

@parameter
def sattempt[T: Copyable & IC & Movable & ImplicitlyDeletable,
             S: Copyable & IC & Movable & ImplicitlyDeletable,
             p: def(Ctx[S]) capturing -> CtxResult[T, S]](
    ctx: Ctx[S]) -> CtxResult[T, S]:
    """
    Run p; on failure reset to the original ctx (input position AND state).

    Without sattempt, a stateful parser that partially mutates state before
    failing leaves the caller with inconsistent state.  sattempt guarantees
    the original ctx is restored on any failure, making it safe to use as a
    backtracking primitive in alternatives (schoice, smany, …).

    Example — try a two-step stateful parse, fully backtrack on failure:
        var r = sattempt[String, Int, my_parser](ctx)
    """
    var r = p(ctx)
    if not r.ok:
        return CtxResult[T, S].failure(ctx, r.msg)^
    return r^


# ── schoice ───────────────────────────────────────────────────────────────────

@parameter
def schoice[T: Copyable & IC & Movable & ImplicitlyDeletable,
            S: Copyable & IC & Movable & ImplicitlyDeletable,
            p: def(Ctx[S]) capturing -> CtxResult[T, S],
            q: def(Ctx[S]) capturing -> CtxResult[T, S]](
    ctx: Ctx[S]) -> CtxResult[T, S]:
    """Try p; if it fails try q on the same context (full backtrack)."""
    var r = p(ctx)
    if r.ok:
        return r^
    return q(ctx)^


# ── smany / smany1 ────────────────────────────────────────────────────────────

@parameter
def smany[T: Copyable & IC & Movable & ImplicitlyDeletable,
          S: Copyable & IC & Movable & ImplicitlyDeletable,
          p: def(Ctx[S]) capturing -> CtxResult[T, S]](
    ctx: Ctx[S]) -> CtxResult[List[T], S]:
    """Zero-or-more applications of p.  State accumulates across iterations."""
    var results = List[T]()
    var cur = ctx
    while True:
        var r = p(cur)
        if not r.ok:
            break
        if r.rest.input.pos == cur.input.pos:   # zero-progress guard
            break
        results.append(r.get())
        cur = r.rest
    return CtxResult[List[T], S].success(results, cur)^


@parameter
def smany1[T: Copyable & IC & Movable & ImplicitlyDeletable,
           S: Copyable & IC & Movable & ImplicitlyDeletable,
           p: def(Ctx[S]) capturing -> CtxResult[T, S]](
    ctx: Ctx[S]) -> CtxResult[List[T], S]:
    """One-or-more applications of p.  Fails if zero matches."""
    var r0 = p(ctx)
    if not r0.ok:
        return CtxResult[List[T], S].failure(ctx, "smany1: zero matches")^
    var results = List[T]()
    results.append(r0.get())
    var cur = r0.rest
    while True:
        var r = p(cur)
        if not r.ok:
            break
        if r.rest.input.pos == cur.input.pos:   # zero-progress guard
            break
        results.append(r.get())
        cur = r.rest
    return CtxResult[List[T], S].success(results, cur)^


# ── sskip_left / sskip_right ──────────────────────────────────────────────────

@parameter
def sskip_left[A: Copyable & IC & Movable & ImplicitlyDeletable,
               B: Copyable & IC & Movable & ImplicitlyDeletable,
               S: Copyable & IC & Movable & ImplicitlyDeletable,
               p: def(Ctx[S]) capturing -> CtxResult[A, S],
               q: def(Ctx[S]) capturing -> CtxResult[B, S]](
    ctx: Ctx[S]) -> CtxResult[B, S]:
    """Run p then q; discard p's result, return q's (with latest state)."""
    var ra = p(ctx)
    if not ra.ok:
        return CtxResult[B, S].failure(ctx, ra.msg)^
    return q(ra.rest)^


@parameter
def sskip_right[A: Copyable & IC & Movable & ImplicitlyDeletable,
                B: Copyable & IC & Movable & ImplicitlyDeletable,
                S: Copyable & IC & Movable & ImplicitlyDeletable,
                p: def(Ctx[S]) capturing -> CtxResult[A, S],
                q: def(Ctx[S]) capturing -> CtxResult[B, S]](
    ctx: Ctx[S]) -> CtxResult[A, S]:
    """Run p then q; discard q's result, return p's (with latest state)."""
    var ra = p(ctx)
    if not ra.ok:
        return CtxResult[A, S].failure(ctx, ra.msg)^
    var rb = q(ra.rest)
    if not rb.ok:
        return CtxResult[A, S].failure(ctx, rb.msg)^
    return CtxResult[A, S].success(ra.get(), rb.rest)^


# ── ssep_by / ssep_by1 ────────────────────────────────────────────────────────

@parameter
def ssep_by[T: Copyable & IC & Movable & ImplicitlyDeletable,
            Sep: Copyable & IC & Movable & ImplicitlyDeletable,
            S: Copyable & IC & Movable & ImplicitlyDeletable,
            p: def(Ctx[S]) capturing -> CtxResult[T, S],
            sep: def(Ctx[S]) capturing -> CtxResult[Sep, S]](
    ctx: Ctx[S]) -> CtxResult[List[T], S]:
    """Zero-or-more p separated by sep, state threads through both.  Always succeeds."""
    var results = List[T]()
    var r0 = p(ctx)
    if not r0.ok:
        return CtxResult[List[T], S].success(results, ctx)^
    results.append(r0.get())
    var cur = r0.rest
    while True:
        var rs = sep(cur)
        if not rs.ok:
            break
        var rp = p(rs.rest)
        if not rp.ok:
            break
        results.append(rp.get())
        cur = rp.rest
    return CtxResult[List[T], S].success(results, cur)^


# ── ssep_by1 ─────────────────────────────────────────────────────────────────

@parameter
def ssep_by1[T: Copyable & IC & Movable & ImplicitlyDeletable,
             Sep: Copyable & IC & Movable & ImplicitlyDeletable,
             S: Copyable & IC & Movable & ImplicitlyDeletable,
             p: def(Ctx[S]) capturing -> CtxResult[T, S],
             sep: def(Ctx[S]) capturing -> CtxResult[Sep, S]](
    ctx: Ctx[S]) -> CtxResult[List[T], S]:
    """One-or-more p separated by sep.  Fails if zero matches."""
    var r0 = p(ctx)
    if not r0.ok:
        return CtxResult[List[T], S].failure(ctx, "ssep_by1: no match")^
    var results = List[T]()
    results.append(r0.get())
    var cur = r0.rest
    while True:
        var rs = sep(cur)
        if not rs.ok:
            break
        var rp = p(rs.rest)
        if not rp.ok:
            break
        results.append(rp.get())
        cur = rp.rest
    return CtxResult[List[T], S].success(results, cur)^


# ── sseq ──────────────────────────────────────────────────────────────────────

@parameter
def sseq[A: Copyable & IC & Movable & ImplicitlyDeletable,
         B: Copyable & IC & Movable & ImplicitlyDeletable,
         S: Copyable & IC & Movable & ImplicitlyDeletable,
         p: def(Ctx[S]) capturing -> CtxResult[A, S],
         q: def(Ctx[S]) capturing -> CtxResult[B, S]](
    ctx: Ctx[S]) -> CtxResult[Pair[A, B], S]:
    """Run p then q threading state; return both results as a Pair."""
    var ra = p(ctx)
    if not ra.ok:
        return CtxResult[Pair[A, B], S].failure(ctx, ra.msg)^
    var rb = q(ra.rest)
    if not rb.ok:
        return CtxResult[Pair[A, B], S].failure(ctx, rb.msg)^
    return CtxResult[Pair[A, B], S].success(Pair[A, B](ra.get(), rb.get()), rb.rest)^


# ── sbetween ──────────────────────────────────────────────────────────────────

@parameter
def sbetween[L: Copyable & IC & Movable & ImplicitlyDeletable,
             T: Copyable & IC & Movable & ImplicitlyDeletable,
             R: Copyable & IC & Movable & ImplicitlyDeletable,
             S: Copyable & IC & Movable & ImplicitlyDeletable,
             lp: def(Ctx[S]) capturing -> CtxResult[L, S],
             p:  def(Ctx[S]) capturing -> CtxResult[T, S],
             rp: def(Ctx[S]) capturing -> CtxResult[R, S]](
    ctx: Ctx[S]) -> CtxResult[T, S]:
    """Parse lp p rp, return p's result; state threads through all three."""
    var rl = lp(ctx)
    if not rl.ok:
        return CtxResult[T, S].failure(ctx, rl.msg)^
    var rm = p(rl.rest)
    if not rm.ok:
        return CtxResult[T, S].failure(ctx, rm.msg)^
    var rr = rp(rm.rest)
    if not rr.ok:
        return CtxResult[T, S].failure(ctx, rr.msg)^
    return CtxResult[T, S].success(rm.get(), rr.rest)^


# ── scount ────────────────────────────────────────────────────────────────────

@parameter
def scount[T: Copyable & IC & Movable & ImplicitlyDeletable,
           S: Copyable & IC & Movable & ImplicitlyDeletable,
           p: def(Ctx[S]) capturing -> CtxResult[T, S],
           N: Int](
    ctx: Ctx[S]) -> CtxResult[List[T], S]:
    """Exactly N applications of p.  Fails (restoring ctx) if any application fails."""
    var results = List[T]()
    var cur = ctx
    for _ in range(N):
        var r = p(cur)
        if not r.ok:
            return CtxResult[List[T], S].failure(ctx, "scount: not enough matches")^
        results.append(r.get())
        cur = r.rest
    return CtxResult[List[T], S].success(results, cur)^


# ── srecognize ────────────────────────────────────────────────────────────────

@parameter
def srecognize[T: Copyable & IC & Movable & ImplicitlyDeletable,
               S: Copyable & IC & Movable & ImplicitlyDeletable,
               p: def(Ctx[S]) capturing -> CtxResult[T, S]](
    ctx: Ctx[S]) -> CtxResult[String, S]:
    """Run p; return the bytes consumed as a String (p's own result is discarded)."""
    var start = ctx.input.pos
    var r = p(ctx)
    if not r.ok:
        return CtxResult[String, S].failure(ctx, r.msg)^
    return CtxResult[String, S].success(
        ctx.input.slice_str(start, r.rest.input.pos), r.rest
    )^


# ── svalue ────────────────────────────────────────────────────────────────────

@parameter
def svalue[T: Copyable & IC & Movable & ImplicitlyDeletable,
           V: Copyable & IC & Movable & ImplicitlyDeletable,
           S: Copyable & IC & Movable & ImplicitlyDeletable,
           p: def(Ctx[S]) capturing -> CtxResult[T, S]](
    v: V, ctx: Ctx[S]) -> CtxResult[V, S]:
    """Run p; on success return `v` instead of p's own result."""
    var r = p(ctx)
    if not r.ok:
        return CtxResult[V, S].failure(ctx, r.msg)^
    return CtxResult[V, S].success(v, r.rest)^


# ── sflat_map ─────────────────────────────────────────────────────────────────

@parameter
def sflat_map[T: Copyable & IC & Movable & ImplicitlyDeletable,
              U: Copyable & IC & Movable & ImplicitlyDeletable,
              S: Copyable & IC & Movable & ImplicitlyDeletable,
              p: def(Ctx[S]) capturing -> CtxResult[T, S],
              f: def(T, Ctx[S]) capturing -> CtxResult[U, S]](
    ctx: Ctx[S]) -> CtxResult[U, S]:
    """
    Dependent stateful sequencing: run p, pass its value and the resulting
    ctx to f.  f may inspect the value to decide how to parse next and how
    to update state.
    """
    var r = p(ctx)
    if not r.ok:
        return CtxResult[U, S].failure(ctx, r.msg)^
    return f(r.get(), r.rest)^


# ── sfold_many0 / sfold_many1 ─────────────────────────────────────────────────

@parameter
def sfold_many0[T: Copyable & IC & Movable & ImplicitlyDeletable,
                Acc: Copyable & IC & Movable & ImplicitlyDeletable,
                S: Copyable & IC & Movable & ImplicitlyDeletable,
                p: def(Ctx[S]) capturing -> CtxResult[T, S],
                f: def(Acc, T) capturing -> Acc](
    init: Acc, ctx: Ctx[S]) -> CtxResult[Acc, S]:
    """
    Apply p zero or more times, folding each result into an accumulator.
    State accumulates across iterations via p.  Always succeeds.
    """
    var acc = init
    var cur = ctx
    while True:
        var r = p(cur)
        if not r.ok:
            break
        if r.rest.input.pos == cur.input.pos:   # zero-progress guard
            break
        acc = f(acc, r.get())
        cur = r.rest
    return CtxResult[Acc, S].success(acc, cur)^


@parameter
def sfold_many1[T: Copyable & IC & Movable & ImplicitlyDeletable,
                Acc: Copyable & IC & Movable & ImplicitlyDeletable,
                S: Copyable & IC & Movable & ImplicitlyDeletable,
                p: def(Ctx[S]) capturing -> CtxResult[T, S],
                f: def(Acc, T) capturing -> Acc](
    init: Acc, ctx: Ctx[S]) -> CtxResult[Acc, S]:
    """Like sfold_many0 but fails if p does not match at least once."""
    var r0 = p(ctx)
    if not r0.ok:
        return CtxResult[Acc, S].failure(ctx, "sfold_many1: zero matches")^
    var acc = f(init, r0.get())
    var cur = r0.rest
    while True:
        var r = p(cur)
        if not r.ok:
            break
        if r.rest.input.pos == cur.input.pos:   # zero-progress guard
            break
        acc = f(acc, r.get())
        cur = r.rest
    return CtxResult[Acc, S].success(acc, cur)^


# ── scond ─────────────────────────────────────────────────────────────────────

@parameter
def scond[T: Copyable & IC & Movable & ImplicitlyDeletable,
          S: Copyable & IC & Movable & ImplicitlyDeletable,
          p: def(Ctx[S]) capturing -> CtxResult[T, S]](
    condition: Bool, ctx: Ctx[S]) -> CtxResult[T, S]:
    """Run p only if `condition` is True; otherwise fail without consuming input or state."""
    if not condition:
        return CtxResult[T, S].failure(ctx, "scond: condition is False")^
    return p(ctx)^
