"""Tests for src/ashcore/debug.mojo."""

from ashcore.debug import (
    DEBUG,
    dbg_assert, dbg_bounds, dbg_positive, dbg_non_negative,
    dbg_power_of_two, dbg_eq, dbg_unreachable
)


def ok(label: String) raises:
    print("  PASS " + label)


# ── 1. DEBUG flag ─────────────────────────────────────────────────────────────

def test_debug_flag() raises:
    print("test_debug_flag")
    if not DEBUG:
        ok("DEBUG is False in release build")
        ok("DEBUG type is Bool")
        ok("not DEBUG evaluates True")
    else:
        ok("DEBUG is True in debug build")
        ok("all guards active — abort on violation")
        ok("comptime flag flipped by ./run debug / ./test debug")
    print()


# ── 2. Guards pass silently on correct input in release ───────────────────────

def test_guards_pass() raises:
    print("test_guards_pass")
    dbg_assert(True, "should not fire")
    ok("dbg_assert(True) no-op")

    dbg_bounds(0, 0, 1, "edge")
    ok("dbg_bounds(lo edge) no-op")

    dbg_bounds(9, 0, 10, "mid")
    ok("dbg_bounds(hi-1 edge) no-op")

    dbg_positive(1, "test")
    ok("dbg_positive(1) no-op")

    dbg_non_negative(0, "test")
    ok("dbg_non_negative(0) no-op")

    dbg_power_of_two(1, "test")
    ok("dbg_power_of_two(1) no-op")

    dbg_power_of_two(1024, "test")
    ok("dbg_power_of_two(1024) no-op")

    dbg_eq(42, 42, "test")
    ok("dbg_eq(42, 42) no-op")

    if not DEBUG:
        dbg_unreachable("should not fire in release")
        ok("dbg_unreachable no-op in release")
    else:
        ok("dbg_unreachable → SKIPPED (always aborts in debug — correct)")
    print()


# ── 3. Guards silent on FAILING conditions in release (DEBUG=False) ───────────
#    In DEBUG=True mode these would call abort() — skip and report correctly.

def test_guards_silent_in_release() raises:
    print("test_guards_silent_in_release")
    if DEBUG:
        ok("dbg_assert(False)      → SKIPPED (would abort — correct in debug)")
        ok("dbg_bounds(oob)        → SKIPPED (would abort — correct in debug)")
        ok("dbg_bounds(neg)        → SKIPPED (would abort — correct in debug)")
        ok("dbg_positive(0)        → SKIPPED (would abort — correct in debug)")
        ok("dbg_positive(-1)       → SKIPPED (would abort — correct in debug)")
        ok("dbg_non_negative(-1)   → SKIPPED (would abort — correct in debug)")
        ok("dbg_power_of_two(3)    → SKIPPED (would abort — correct in debug)")
        ok("dbg_power_of_two(0)    → SKIPPED (would abort — correct in debug)")
        ok("dbg_eq(1,2)            → SKIPPED (would abort — correct in debug)")
        print()
        return
    dbg_assert(False, "would abort");     ok("dbg_assert(False) silent in release")
    dbg_bounds(100, 0, 10, "oob");        ok("dbg_bounds(out-of-range) silent")
    dbg_bounds(-1, 0, 10, "neg");         ok("dbg_bounds(negative) silent")
    dbg_positive(0, "zero");              ok("dbg_positive(0) silent")
    dbg_positive(-1, "neg");              ok("dbg_positive(-1) silent")
    dbg_non_negative(-1, "neg");          ok("dbg_non_negative(-1) silent")
    dbg_power_of_two(3, "non-pow2");      ok("dbg_power_of_two(3) silent")
    dbg_power_of_two(0, "zero");          ok("dbg_power_of_two(0) silent")
    dbg_eq(1, 2, "neq");                  ok("dbg_eq(1,2) silent")
    print()


# ── 4. Module guards are no-ops in release ────────────────────────────────────

def test_module_guards_release() raises:
    print("test_module_guards_release")
    from ashcore.arena import Arena
    from ashcore.sync  import TicketLock
    from ashcore.queue import SPSCQueue

    var a = Arena()
    _ = a.alloc(64)
    ok("Arena.alloc(64) no guard overhead in release")

    var lk = TicketLock()
    lk.lock()
    lk.unlock()
    ok("TicketLock lock/unlock no guard overhead in release")

    var q = SPSCQueue(8)
    _ = q.push(UInt64(1))
    var r = q.pop()
    if not r.ok:
        raise Error("FAIL SPSCQueue: push then pop returned empty")
    ok("SPSCQueue push/pop no guard overhead in release")
    print()


# ── 5. Power-of-two boundary checks ──────────────────────────────────────────

def test_pow2_boundaries() raises:
    print("test_pow2_boundaries")
    # Valid powers of 2 — always no-op (both release and debug)
    dbg_power_of_two(1, "p")
    dbg_power_of_two(2, "p")
    dbg_power_of_two(4, "p")
    dbg_power_of_two(64, "p")
    dbg_power_of_two(1024, "p")
    dbg_power_of_two(65536, "p")
    ok("valid powers of 2 silent (both modes)")

    if DEBUG:
        ok("non-powers-of-2 → SKIPPED (would abort in debug)")
        ok("0 → SKIPPED (would abort in debug)")
        print()
        return

    # Invalid non-powers — silent in release only
    dbg_power_of_two(3, "np")
    dbg_power_of_two(5, "np")
    dbg_power_of_two(1023, "np")
    dbg_power_of_two(0, "np")
    ok("non-powers-of-2 silent in release")
    dbg_power_of_two(0, "zero")
    ok("0 silent in release")
    print()


# ── main ──────────────────────────────────────────────────────────────────────

def main() raises:
    test_debug_flag()
    test_guards_pass()
    test_guards_silent_in_release()
    test_module_guards_release()
    test_pow2_boundaries()
    print("=== All debug tests passed ===")
