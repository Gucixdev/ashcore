"""
Stress: edge cases for all primitive parsers.
Tests EOF, empty input, single char, max-length token, and failure paths.
Output: result=OK or result=FAIL
"""
from ashparser.input  import Input
from ashparser.prim   import (
    satisfy, byte, tag, take_while, take_while1,
    digit, alpha, alphanum, ws, digits, ident, eof,
    _is_digit, _is_alpha, _is_alphanum,
)
from ashparser.comb   import many, opt, sep_by, sep_by1
from ashparser.result import ParseResult


def chk(label: String, cond: Bool) raises:
    if not cond:
        print("FAIL: " + label)
        raise Error("edge case failure: " + label)


def main() raises:
    # ── EOF handling ──────────────────────────────────────────────────────────
    var empty = Input.from_string(String(""))
    chk("eof on empty",         eof(empty).ok)
    chk("digit on empty fails", not digit(empty).ok)
    chk("alpha on empty fails", not alpha(empty).ok)
    chk("ident on empty fails", not ident(empty).ok)
    chk("tag on empty fails",   not tag["hi"](empty).ok)
    chk("ws on empty ok",       ws(empty).ok)
    chk("many on empty ok",     many[UInt8, digit](empty).ok)
    chk("opt on empty ok",      opt[UInt8, digit](0, empty).ok)

    # ── Single character ──────────────────────────────────────────────────────
    var one = Input.from_string(String("5"))
    chk("digit '5' ok",         digit(one).ok)
    chk("eof after digit",      eof(digit(one).rest).ok)
    chk("satisfy digit '5'",    satisfy[_is_digit](one).ok)
    chk("byte 53 '5' ok",       byte[UInt8(53)](one).ok)
    chk("byte 54 '6' fail",     not byte[UInt8(54)](one).ok)

    # ── Long token (10k chars) ────────────────────────────────────────────────
    var long_tok = String()
    for _ in range(10_000):
        long_tok += String("a")
    long_tok += String("1")
    var li = Input.from_string(long_tok)
    var lr = take_while[_is_alpha](li)
    chk("take_while 10k alpha",  lr.ok and len(lr.get()) == 10_000)
    chk("remaining after 10k",   lr.rest.remaining() == 1)

    # ── sep_by with many elements ─────────────────────────────────────────────
    @parameter
    def comma(inp: Input) -> ParseResult[UInt8]:
        var r = byte[UInt8(44)](inp)
        return r^

    var big = String()
    for i in range(1000):
        if i > 0:
            big += String(",")
        big += String("5")
    var bi = Input.from_string(big)
    var br = sep_by[UInt8, UInt8, digit, comma](bi)
    chk("sep_by 1000 elems ok",  br.ok and len(br.get()) == 1000)

    # ── sep_by1 on single element ─────────────────────────────────────────────
    var si = Input.from_string(String("9"))
    var sr = sep_by1[UInt8, UInt8, digit, comma](si)
    chk("sep_by1 single elem",   sr.ok and len(sr.get()) == 1)

    # ── Failure propagation ───────────────────────────────────────────────────
    chk("digits fail on alpha",  not digits(Input.from_string(String("abc"))).ok)
    chk("ident fail on digit",   not ident(Input.from_string(String("9bad"))).ok)
    chk("tag fail short input",  not tag["hello"](Input.from_string(String("hel"))).ok)
    chk("take_while1 fail",      not take_while1[_is_digit](
        Input.from_string(String("abc"))).ok)

    # ── Partial input recovery ────────────────────────────────────────────────
    var mixed = Input.from_string(String("abc123"))
    var ra = take_while[_is_alpha](mixed)
    chk("alpha part",            ra.ok and ra.get() == "abc")
    var rd = take_while[_is_digit](ra.rest)
    chk("digit part after alpha", rd.ok and rd.get() == "123")
    chk("eof after both parts",  eof(rd.rest).ok)

    print("result=OK")
