"""
ashparser — Stateful combinators

Stateful parsers: (Ctx[S]) -> CtxResult[T, S]
State threads as an immutable value (State monad style).

slift       — promote a stateless parser to stateful (state unchanged)
sget        — read current state (no input consumed)
smodify     — transform state via @parameter def, no input consumed
smap        — apply function to successful result
schoice     — ordered choice (try p, fallback to q on same ctx)
smany       — zero-or-more
smany1      — one-or-more
sskip_left  — run p then q, return q
sskip_right — run p then q, return p
ssep_by     — zero-or-more separated by sep
ssep_by1    — one-or-more separated by sep
"""
from ashparser.input  import Input
from ashparser.result import ParseResult
from ashparser.state  import Ctx, CtxResult

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
        var out = CtxResult[T, S].failure(ctx, r.msg)
        return out^
    var out = CtxResult[T, S].success(r.get(), Ctx[S](r.rest, ctx.state))
    return out^


# ── sget / smodify ────────────────────────────────────────────────────────────

@parameter
def sget[S: Copyable & IC & Movable & ImplicitlyDeletable](
    ctx: Ctx[S]) -> CtxResult[S, S]:
    """Return the current state value; consume no input.  Always succeeds."""
    var out = CtxResult[S, S].success(ctx.state, ctx)
    return out^


@parameter
def smodify[S: Copyable & IC & Movable & ImplicitlyDeletable,
            f: def(S) capturing -> S](
    ctx: Ctx[S]) -> CtxResult[UInt8, S]:
    """Apply f to the current state; consume no input.  Returns 0."""
    var new_state = f(ctx.state)
    var out = CtxResult[UInt8, S].success(0, Ctx[S](ctx.input, new_state))
    return out^


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
        var out = CtxResult[U, S].failure(ctx, r.msg)
        return out^
    var val = f(r.get())
    var out = CtxResult[U, S].success(val, r.rest)
    return out^


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
    var r2 = q(ctx)
    return r2^


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
        results.append(r.get())
        cur = r.rest
    var out = CtxResult[List[T], S].success(results, cur)
    return out^


@parameter
def smany1[T: Copyable & IC & Movable & ImplicitlyDeletable,
           S: Copyable & IC & Movable & ImplicitlyDeletable,
           p: def(Ctx[S]) capturing -> CtxResult[T, S]](
    ctx: Ctx[S]) -> CtxResult[List[T], S]:
    """One-or-more applications of p.  Fails if zero matches."""
    var r0 = p(ctx)
    if not r0.ok:
        var out = CtxResult[List[T], S].failure(
            ctx, "smany1: zero matches at pos " + String(ctx.input.pos)
        )
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
    var out = CtxResult[List[T], S].success(results, cur)
    return out^


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
        var out = CtxResult[B, S].failure(ctx, ra.msg)
        return out^
    var rb = q(ra.rest)
    return rb^


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
        var out = CtxResult[A, S].failure(ctx, ra.msg)
        return out^
    var rb = q(ra.rest)
    if not rb.ok:
        var out = CtxResult[A, S].failure(ctx, rb.msg)
        return out^
    var out = CtxResult[A, S].success(ra.get(), rb.rest)
    return out^


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
        var out = CtxResult[List[T], S].success(results, ctx)
        return out^
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
    var out = CtxResult[List[T], S].success(results, cur)
    return out^


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
        var out = CtxResult[List[T], S].failure(
            ctx, "ssep_by1: no match at pos " + String(ctx.input.pos)
        )
        return out^
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
    var out = CtxResult[List[T], S].success(results, cur)
    return out^
