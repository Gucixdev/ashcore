"""
AshCore - Debug / Release mode

Set DEBUG = True to enable all runtime checks.
Every guard is @always_inline and guarded by `if DEBUG:`.
When DEBUG = False, LLVM eliminates the entire body (zero overhead in release).

On violation: prints diagnostic + calls abort() — hard crash with backtrace.
This matches C's assert() semantics: fast, unambiguous, no exception overhead.

Toggle via the run script:
    ./run           # release (DEBUG=False)
    ./run debug     # sets DEBUG=True, runs tests, restores
    ./run release   # explicit release

Guards:
    dbg_assert(cond, msg)           — general assertion
    dbg_bounds(idx, lo, hi, ctx)    — index range check
    dbg_positive(val, ctx)          — val > 0
    dbg_non_negative(val, ctx)      — val >= 0
    dbg_power_of_two(val, ctx)      — power-of-2 check
    dbg_eq(a, b, ctx)               — equality check
    dbg_unreachable(ctx)            — marks code that must never execute
"""

from std.ffi import external_call


comptime DEBUG: Bool = False


@always_inline
def _abort(msg: String):
    print(msg)
    _ = external_call["abort", Int32]()


@always_inline
def dbg_assert(cond: Bool, msg: String):
    """Assert cond. Abort with msg in debug, no-op in release."""
    if DEBUG:
        if not cond:
            _abort("[ASHEN] assertion failed: " + msg)


@always_inline
def dbg_bounds(idx: Int, lo: Int, hi: Int, ctx: String):
    """Assert lo <= idx < hi. Abort in debug, no-op in release."""
    if DEBUG:
        if idx < lo or idx >= hi:
            _abort(
                "[ASHEN] " + ctx + ": index " + String(idx)
                + " out of range [" + String(lo) + ", " + String(hi) + ")"
            )


@always_inline
def dbg_positive(val: Int, ctx: String):
    """Assert val > 0. Abort in debug, no-op in release."""
    if DEBUG:
        if val <= 0:
            _abort("[ASHEN] " + ctx + ": expected positive, got " + String(val))


@always_inline
def dbg_non_negative(val: Int, ctx: String):
    """Assert val >= 0. Abort in debug, no-op in release."""
    if DEBUG:
        if val < 0:
            _abort("[ASHEN] " + ctx + ": expected >= 0, got " + String(val))


@always_inline
def dbg_power_of_two(val: Int, ctx: String):
    """Assert val is a power of 2. Abort in debug, no-op in release."""
    if DEBUG:
        if val <= 0 or (val & (val - 1)) != 0:
            _abort("[ASHEN] " + ctx + ": expected power-of-2, got " + String(val))


@always_inline
def dbg_eq(a: Int, b: Int, ctx: String):
    """Assert a == b. Abort in debug, no-op in release."""
    if DEBUG:
        if a != b:
            _abort("[ASHEN] " + ctx + ": " + String(a) + " != " + String(b))


@always_inline
def dbg_unreachable(ctx: String):
    """Mark code that must never execute. Aborts if reached in debug."""
    if DEBUG:
        _abort("[ASHEN] unreachable: " + ctx)
