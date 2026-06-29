"""
ashparser — test suite

Pattern: chk(label, cond) raises on first failure.
All parser functions used as combinator arguments must be @parameter def.
"""
from ashparser.input  import Input
from ashparser.result import ParseResult
from ashparser.prim   import (
    satisfy, byte, tag, take_while, take_while1,
    digit, alpha, alphanum, ws, digits, ident, eof,
    _is_digit, _is_alpha, _is_alphanum, _is_hex,
    one_of, none_of,
    line_ending, rest_of_line,
    hex_digit, hex_digits,
    parse_uint, parse_int,
    quoted_string,
)
from ashparser.comb   import (
    Pair, opt, many, many1, map, choice,
    seq, skip_left, skip_right, between,
    sep_by, sep_by1,
    peek, not_followed_by,
    verify, skip_many, skip_many1,
    count, recognize,
)
from ashparser.state     import Ctx, CtxResult
from ashparser.statecomb import (
    slift, sget, smodify, smap,
    schoice, smany, smany1,
    sskip_left, sskip_right,
    ssep_by, ssep_by1,
)


def chk(label: String, cond: Bool) raises:
    if cond:
        print("  PASS " + label)
    else:
        print("  FAIL " + label)
        raise Error("FAIL: " + label)


def section(name: String):
    print("\n── " + name + " ──")


# ── @parameter helper parsers for combinator tests ────────────────────────────

@parameter
def comma(inp: Input) -> ParseResult[UInt8]:
    var r = byte[UInt8(44)](inp)   # ','
    return r^

@parameter
def open_paren(inp: Input) -> ParseResult[UInt8]:
    var r = byte[UInt8(40)](inp)   # '('
    return r^

@parameter
def close_paren(inp: Input) -> ParseResult[UInt8]:
    var r = byte[UInt8(41)](inp)   # ')'
    return r^

@parameter
def hi_tag(inp: Input) -> ParseResult[String]:
    var r = tag["hi"](inp)
    return r^

@parameter
def digit_as_int(b: UInt8) -> Int:
    return Int(b) - 48


# ── Input ─────────────────────────────────────────────────────────────────────

def test_input() raises:
    section("Input")
    var s = String("hello")
    var inp = Input.from_string(s)
    chk("peek 'h'",        inp.peek() == 104)
    chk("peek_at 1 'e'",   inp.peek_at(1) == 101)
    chk("remaining=5",     inp.remaining() == 5)
    chk("not is_empty",    not inp.is_empty())
    var inp2 = inp.advance(3)
    chk("advance 3 pos",   inp2.pos == 3)
    chk("remaining=2",     inp2.remaining() == 2)
    chk("slice_str",       inp.slice_str(1, 4) == "ell")
    chk("current_str",     inp2.current_str(2) == "lo")
    var empty = inp.advance(100)
    chk("advance past end", empty.is_empty())
    chk("peek at eof=0",   empty.peek() == 0)


# ── ParseResult ───────────────────────────────────────────────────────────────

def test_result() raises:
    section("ParseResult")
    var s = String("x")
    var inp = Input.from_string(s)
    var r = ParseResult[UInt8].success(42, inp.advance(1))
    chk("success ok",      r.ok)
    chk("success get",     r.get() == 42)
    chk("success rest",    r.rest.is_empty())
    var f = ParseResult[UInt8].failure(inp, "oops")
    chk("failure ok=F",    not f.ok)
    chk("failure msg",     f.msg == "oops")


# ── Primitives ────────────────────────────────────────────────────────────────

def test_prim() raises:
    section("Primitives")

    # satisfy
    var r1 = satisfy[_is_digit](Input.from_string(String("5")))
    chk("satisfy digit ok",     r1.ok and r1.get() == 53)
    var r2 = satisfy[_is_digit](Input.from_string(String("x")))
    chk("satisfy digit fail",   not r2.ok)
    var r3 = satisfy[_is_digit](Input.from_string(String("")))
    chk("satisfy eof fail",     not r3.ok)

    # byte
    var r4 = byte[UInt8(40)](Input.from_string(String("(x")))
    chk("byte ok",              r4.ok and r4.get() == 40)
    var r5 = byte[UInt8(40)](Input.from_string(String("x")))
    chk("byte fail",            not r5.ok)

    # tag
    var r6 = tag["hello"](Input.from_string(String("hello world")))
    chk("tag ok",               r6.ok and r6.get() == "hello")
    chk("tag rest",             r6.rest.remaining() == 6)
    var r7 = tag["xyz"](Input.from_string(String("hello")))
    chk("tag fail",             not r7.ok)
    var r8 = tag["hel"](Input.from_string(String("he")))
    chk("tag short fail",       not r8.ok)

    # digit / alpha / alphanum
    chk("digit '5'",            digit(Input.from_string(String("5"))).ok)
    chk("digit 'x' fail",       not digit(Input.from_string(String("x"))).ok)
    chk("alpha 'a'",            alpha(Input.from_string(String("a"))).ok)
    chk("alpha '9' fail",       not alpha(Input.from_string(String("9"))).ok)
    chk("alphanum '9'",         alphanum(Input.from_string(String("9"))).ok)
    chk("alphanum 'z'",         alphanum(Input.from_string(String("z"))).ok)
    chk("alphanum '!' fail",    not alphanum(Input.from_string(String("!"))).ok)

    # take_while1
    var r9 = take_while1[_is_alpha](Input.from_string(String("abc123")))
    chk("take_while1 ok",       r9.ok and r9.get() == "abc")
    var r10 = take_while1[_is_alpha](Input.from_string(String("123")))
    chk("take_while1 fail",     not r10.ok)

    # digits / ident
    var r11 = digits(Input.from_string(String("123abc")))
    chk("digits ok",            r11.ok and r11.get() == "123")
    chk("digits fail",          not digits(Input.from_string(String("abc"))).ok)
    var r12 = ident(Input.from_string(String("foo_123")))
    chk("ident ok",             r12.ok and r12.get() == "foo_123")
    chk("ident fail",           not ident(Input.from_string(String("9bad"))).ok)

    # ws / eof
    var r13 = ws(Input.from_string(String("  \t\nhello")))
    chk("ws ok",                r13.ok and r13.rest.remaining() == 5)
    chk("ws empty ok",          ws(Input.from_string(String("x"))).ok)
    chk("eof ok",               eof(Input.from_string(String(""))).ok)
    chk("eof fail",             not eof(Input.from_string(String("x"))).ok)


# ── Combinators ───────────────────────────────────────────────────────────────

def test_comb() raises:
    section("Combinators")

    # opt
    var r1 = opt[UInt8, digit](0, Input.from_string(String("5rest")))
    chk("opt success",          r1.ok and r1.get() == 53)
    var r2 = opt[UInt8, digit](0, Input.from_string(String("xyz")))
    chk("opt default",          r2.ok and r2.get() == 0)
    chk("opt no consume",       r2.rest.remaining() == 3)

    # many
    var r3 = many[UInt8, digit](Input.from_string(String("123abc")))
    chk("many ok len=3",        r3.ok and len(r3.get()) == 3)
    chk("many rest",            r3.rest.remaining() == 3)
    var r4 = many[UInt8, digit](Input.from_string(String("abc")))
    chk("many zero ok",         r4.ok and len(r4.get()) == 0)

    # many1
    var r5 = many1[UInt8, digit](Input.from_string(String("42x")))
    chk("many1 ok",             r5.ok and len(r5.get()) == 2)
    chk("many1 fail",           not many1[UInt8, digit](Input.from_string(String("x"))).ok)

    # map
    var r6 = map[UInt8, Int, digit, digit_as_int](Input.from_string(String("7rest")))
    chk("map ok",               r6.ok and r6.get() == 7)
    chk("map fail",             not map[UInt8, Int, digit, digit_as_int](Input.from_string(String("x"))).ok)

    # choice
    var r7 = choice[UInt8, digit, alpha](Input.from_string(String("5")))
    chk("choice first",         r7.ok and r7.get() == 53)
    var r8 = choice[UInt8, digit, alpha](Input.from_string(String("a")))
    chk("choice second",        r8.ok and r8.get() == 97)
    chk("choice fail",          not choice[UInt8, digit, alpha](Input.from_string(String("!"))).ok)

    # skip_left / skip_right
    var r9 = skip_left[String, String, ws, digits](Input.from_string(String("  42rest")))
    chk("skip_left ws+digits",  r9.ok and r9.get() == "42")
    var r10 = skip_right[String, UInt8, digits, comma](Input.from_string(String("99,x")))
    chk("skip_right digits,comma", r10.ok and r10.get() == "99")
    chk("skip_right rest",      r10.rest.remaining() == 1)

    # between
    var r11 = between[UInt8, UInt8, UInt8, open_paren, digit, close_paren](
        Input.from_string(String("(5)"))
    )
    chk("between (digit)",      r11.ok and r11.get() == 53)
    chk("between fail",         not between[UInt8, UInt8, UInt8, open_paren, digit, close_paren](
        Input.from_string(String("5"))).ok)

    # sep_by
    var r12 = sep_by[UInt8, UInt8, digit, comma](Input.from_string(String("1,2,3")))
    chk("sep_by ok len=3",      r12.ok and len(r12.get()) == 3)
    var r13 = sep_by[UInt8, UInt8, digit, comma](Input.from_string(String("")))
    chk("sep_by empty ok",      r13.ok and len(r13.get()) == 0)

    # sep_by1
    var r14 = sep_by1[UInt8, UInt8, digit, comma](Input.from_string(String("1,2")))
    chk("sep_by1 ok",           r14.ok and len(r14.get()) == 2)
    chk("sep_by1 fail",         not sep_by1[UInt8, UInt8, digit, comma](Input.from_string(String("x"))).ok)

    # seq
    var r15 = seq[UInt8, String, digit, digits](Input.from_string(String("1234rest")))
    chk("seq ok",               r15.ok and r15.get().first == 49 and r15.get().second == "234")


# ── New primitives ────────────────────────────────────────────────────────────

def test_new_prim() raises:
    section("New primitives")

    # one_of
    var r1 = one_of["+-*/"](Input.from_string(String("+")))
    chk("one_of '+' ok",         r1.ok and r1.get() == 43)
    var r2 = one_of["+-*/"](Input.from_string(String("x")))
    chk("one_of 'x' fail",       not r2.ok)
    var r3 = one_of["abc"](Input.from_string(String("")))
    chk("one_of EOF fail",       not r3.ok)

    # none_of
    var r4 = none_of["\","](Input.from_string(String("x")))
    chk("none_of ok",            r4.ok and r4.get() == 120)
    var r5 = none_of["\","](Input.from_string(String("\"")))
    chk("none_of excluded fail", not r5.ok)
    var r6 = none_of["abc"](Input.from_string(String("")))
    chk("none_of EOF fail",      not r6.ok)

    # line_ending
    var r7 = line_ending(Input.from_string(String("\nhello")))
    chk("line_ending LF ok",     r7.ok and r7.get() == "\n")
    chk("line_ending LF rest",   r7.rest.remaining() == 5)
    var r8 = line_ending(Input.from_string(String("\r\nhello")))
    chk("line_ending CRLF ok",   r8.ok and r8.rest.remaining() == 5)
    chk("line_ending fail",      not line_ending(Input.from_string(String("x"))).ok)
    chk("line_ending EOF fail",  not line_ending(Input.from_string(String(""))).ok)

    # rest_of_line
    var r9 = rest_of_line(Input.from_string(String("hello\nworld")))
    chk("rest_of_line ok",       r9.ok and r9.get() == "hello")
    chk("rest_of_line consumed", r9.rest.remaining() == 5)
    var r10 = rest_of_line(Input.from_string(String("hello")))
    chk("rest_of_line EOF ok",   r10.ok and r10.get() == "hello" and r10.rest.is_empty())
    var r11 = rest_of_line(Input.from_string(String("a\r\nb")))
    chk("rest_of_line CRLF",     r11.ok and r11.get() == "a" and r11.rest.remaining() == 1)
    var r12 = rest_of_line(Input.from_string(String("\nrest")))
    chk("rest_of_line empty",    r12.ok and r12.get() == "" and r12.rest.remaining() == 4)

    # hex_digit / hex_digits
    chk("hex_digit 'a' ok",      hex_digit(Input.from_string(String("a"))).ok)
    chk("hex_digit 'F' ok",      hex_digit(Input.from_string(String("F"))).ok)
    chk("hex_digit '9' ok",      hex_digit(Input.from_string(String("9"))).ok)
    chk("hex_digit 'g' fail",    not hex_digit(Input.from_string(String("g"))).ok)
    var r13 = hex_digits(Input.from_string(String("1aFf rest")))
    chk("hex_digits ok",         r13.ok and r13.get() == "1aFf")
    chk("hex_digits fail",       not hex_digits(Input.from_string(String("xyz"))).ok)

    # parse_uint
    var r14 = parse_uint(Input.from_string(String("42rest")))
    chk("parse_uint ok",         r14.ok and r14.get() == 42)
    chk("parse_uint rest",       r14.rest.remaining() == 4)
    var r15 = parse_uint(Input.from_string(String("0")))
    chk("parse_uint zero",       r15.ok and r15.get() == 0)
    chk("parse_uint fail",       not parse_uint(Input.from_string(String("abc"))).ok)
    var r16 = parse_uint(Input.from_string(String("1000000")))
    chk("parse_uint large",      r16.ok and r16.get() == 1000000)

    # parse_int
    var r17 = parse_int(Input.from_string(String("123")))
    chk("parse_int pos",         r17.ok and r17.get() == 123)
    var r18 = parse_int(Input.from_string(String("-99")))
    chk("parse_int neg",         r18.ok and r18.get() == -99)
    var r19 = parse_int(Input.from_string(String("-0")))
    chk("parse_int neg zero",    r19.ok and r19.get() == 0)
    chk("parse_int fail",        not parse_int(Input.from_string(String("abc"))).ok)
    chk("parse_int lone minus",  not parse_int(Input.from_string(String("-x"))).ok)

    # quoted_string
    var r20 = quoted_string(Input.from_string(String("\"hello\"")))
    chk("quoted_string ok",      r20.ok and r20.get() == "hello")
    chk("quoted_string rest",    r20.rest.is_empty())
    var r21 = quoted_string(Input.from_string(String("\"a\\\"b\"")))
    chk("quoted escape \\\"",    r21.ok and r21.get() == "a\"b")
    var r22 = quoted_string(Input.from_string(String("\"a\\\\b\"")))
    chk("quoted escape \\\\",    r22.ok and r22.get() == "a\\b")
    var r23 = quoted_string(Input.from_string(String("\"line\\nfeed\"")))
    chk("quoted escape \\n",     r23.ok and r23.get() == "line\nfeed")
    chk("quoted no quote fail",  not quoted_string(Input.from_string(String("hello"))).ok)
    chk("quoted unterminated",   not quoted_string(Input.from_string(String("\"abc"))).ok)
    var r24 = quoted_string(Input.from_string(String("\"\" rest")))
    chk("quoted empty string",   r24.ok and r24.get() == "")


# ── New combinators ────────────────────────────────────────────────────────────

def test_new_comb() raises:
    section("New combinators")

    # peek
    var r1 = peek[UInt8, digit](Input.from_string(String("5rest")))
    chk("peek ok val",           r1.ok and r1.get() == 53)
    chk("peek no consume",       r1.rest.remaining() == 5)
    chk("peek fail",             not peek[UInt8, digit](Input.from_string(String("x"))).ok)

    # not_followed_by
    var r2 = not_followed_by[UInt8, digit](Input.from_string(String("abc")))
    chk("not_followed_by ok",    r2.ok and r2.get() == 0)
    chk("not_followed_by nocons", r2.rest.remaining() == 3)
    chk("not_followed_by fail",  not not_followed_by[UInt8, digit](Input.from_string(String("5"))).ok)
    chk("not_followed_by EOF",   not_followed_by[UInt8, digit](Input.from_string(String(""))).ok)

    # verify
    @parameter
    def is_even(s: String) -> Bool:
        if s.byte_length() == 0:
            return False
        var v = Int(s.unsafe_ptr()[0]) - 48
        return v % 2 == 0

    var r3 = verify[String, digits, is_even](Input.from_string(String("246rest")))
    chk("verify ok",             r3.ok and r3.get() == "246")
    var r4 = verify[String, digits, is_even](Input.from_string(String("357rest")))
    chk("verify pred fail",      not r4.ok)
    chk("verify backtrack",      r4.rest.remaining() == 7)
    chk("verify parse fail",     not verify[String, digits, is_even](Input.from_string(String("abc"))).ok)

    # skip_many
    var r5 = skip_many[UInt8, digit](Input.from_string(String("123abc")))
    chk("skip_many ok",          r5.ok and r5.get() == 0)
    chk("skip_many consumed",    r5.rest.remaining() == 3)
    var r6 = skip_many[UInt8, digit](Input.from_string(String("abc")))
    chk("skip_many zero ok",     r6.ok and r6.rest.remaining() == 3)

    # skip_many1
    var r7 = skip_many1[UInt8, digit](Input.from_string(String("456x")))
    chk("skip_many1 ok",         r7.ok and r7.rest.remaining() == 1)
    chk("skip_many1 fail",       not skip_many1[UInt8, digit](Input.from_string(String("x"))).ok)

    # count
    var r8 = count[UInt8, digit, 3](Input.from_string(String("123rest")))
    chk("count ok len=3",        r8.ok and len(r8.get()) == 3)
    chk("count values",          r8.get()[0] == 49 and r8.get()[2] == 51)
    chk("count rest",            r8.rest.remaining() == 4)
    var r9 = count[UInt8, digit, 3](Input.from_string(String("12x")))
    chk("count fail backtrack",  not r9.ok and r9.rest.remaining() == 3)
    var r10 = count[UInt8, digit, 0](Input.from_string(String("abc")))
    chk("count zero ok",         r10.ok and len(r10.get()) == 0)

    # recognize
    var r11 = recognize[String, digits](Input.from_string(String("123abc")))
    chk("recognize ok",          r11.ok and r11.get() == "123")
    chk("recognize rest",        r11.rest.remaining() == 3)
    chk("recognize fail",        not recognize[String, digits](Input.from_string(String("abc"))).ok)

    # recognize with many — captures raw bytes of multi-parse
    var r12 = recognize[List[UInt8], many[UInt8, digit]](Input.from_string(String("456xyz")))
    chk("recognize many",        r12.ok and r12.get() == "456")


# ── Stateful parsing ──────────────────────────────────────────────────────────

def test_state() raises:
    section("Stateful parsing (Ctx + CtxResult)")

    # slift: promote stateless parser, state unchanged
    var ctx0 = Ctx[Int](Input.from_string(String("123abc")), 42)
    var r1 = slift[String, Int, digits](ctx0)
    chk("slift ok",              r1.ok and r1.get() == "123")
    chk("slift state unchanged", r1.rest.state == 42)
    chk("slift rest pos",        r1.rest.input.remaining() == 3)

    var ctx_bad = Ctx[Int](Input.from_string(String("abc")), 0)
    chk("slift fail",            not slift[String, Int, digits](ctx_bad).ok)

    # sget: read current state
    var ctx1 = Ctx[Int](Input.from_string(String("hello")), 99)
    var r2 = sget[Int](ctx1)
    chk("sget ok",               r2.ok and r2.get() == 99)
    chk("sget no consume",       r2.rest.input.remaining() == 5)

    # smodify: transform state
    @parameter
    def inc(n: Int) -> Int:
        return n + 1

    var ctx2 = Ctx[Int](Input.from_string(String("x")), 10)
    var r3 = smodify[Int, inc](ctx2)
    chk("smodify ok",            r3.ok)
    chk("smodify state updated", r3.rest.state == 11)
    chk("smodify no consume",    r3.rest.input.remaining() == 1)

    # smap: map over stateful result
    @parameter
    def strlen(s: String) -> Int:
        return s.byte_length()

    @parameter
    def sdigits(ctx: Ctx[Int]) -> CtxResult[String, Int]:
        return slift[String, Int, digits](ctx)^

    var ctx3 = Ctx[Int](Input.from_string(String("456rest")), 0)
    var r4 = smap[String, Int, Int, sdigits, strlen](ctx3)
    chk("smap ok",               r4.ok and r4.get() == 3)

    # schoice: try first, fallback to second
    @parameter
    def sdig(ctx: Ctx[Int]) -> CtxResult[String, Int]:
        return slift[String, Int, digits](ctx)^

    @parameter
    def sidt(ctx: Ctx[Int]) -> CtxResult[String, Int]:
        return slift[String, Int, ident](ctx)^

    var ctx4 = Ctx[Int](Input.from_string(String("42x")), 0)
    var r5 = schoice[String, Int, sdig, sidt](ctx4)
    chk("schoice first ok",      r5.ok and r5.get() == "42")

    var ctx5 = Ctx[Int](Input.from_string(String("foo")), 0)
    var r6 = schoice[String, Int, sdig, sidt](ctx5)
    chk("schoice second ok",     r6.ok and r6.get() == "foo")

    chk("schoice both fail",     not schoice[String, Int, sdig, sidt](
        Ctx[Int](Input.from_string(String("!")), 0)).ok)

    # smany: accumulate state across iterations
    @parameter
    def sdig_count(ctx: Ctx[Int]) -> CtxResult[UInt8, Int]:
        var r = digit(ctx.input)
        if not r.ok:
            return CtxResult[UInt8, Int].failure(ctx, r.msg)^
        return CtxResult[UInt8, Int].success(r.get(), Ctx[Int](r.rest, ctx.state + 1))^

    var ctx6 = Ctx[Int](Input.from_string(String("123abc")), 0)
    var r7 = smany[UInt8, Int, sdig_count](ctx6)
    chk("smany count ok",        r7.ok and len(r7.get()) == 3)
    chk("smany state = count",   r7.rest.state == 3)

    # smany1
    chk("smany1 ok",             smany1[UInt8, Int, sdig_count](
        Ctx[Int](Input.from_string(String("9x")), 0)).ok)
    chk("smany1 fail",           not smany1[UInt8, Int, sdig_count](
        Ctx[Int](Input.from_string(String("x")), 0)).ok)

    # sskip_left
    @parameter
    def sws(ctx: Ctx[Int]) -> CtxResult[String, Int]:
        return slift[String, Int, ws](ctx)^

    var ctx7 = Ctx[Int](Input.from_string(String("  42")), 0)
    var r8 = sskip_left[String, String, Int, sws, sdig](ctx7)
    chk("sskip_left ok",         r8.ok and r8.get() == "42")

    # sskip_right
    @parameter
    def scomma(ctx: Ctx[Int]) -> CtxResult[UInt8, Int]:
        return slift[UInt8, Int, comma](ctx)^

    var ctx8 = Ctx[Int](Input.from_string(String("99,x")), 0)
    var r9 = sskip_right[String, UInt8, Int, sdig, scomma](ctx8)
    chk("sskip_right ok",        r9.ok and r9.get() == "99")
    chk("sskip_right rest",      r9.rest.input.remaining() == 1)

    # ssep_by: digits separated by comma, state counts separators
    @parameter
    def sdig_str(ctx: Ctx[Int]) -> CtxResult[String, Int]:
        return slift[String, Int, digits](ctx)^

    @parameter
    def scomma_count(ctx: Ctx[Int]) -> CtxResult[UInt8, Int]:
        var r = comma(ctx.input)
        if not r.ok:
            return CtxResult[UInt8, Int].failure(ctx, r.msg)^
        return CtxResult[UInt8, Int].success(r.get(), Ctx[Int](r.rest, ctx.state + 1))^

    var ctx9 = Ctx[Int](Input.from_string(String("10,20,30")), 0)
    var r10 = ssep_by[String, UInt8, Int, sdig_str, scomma_count](ctx9)
    chk("ssep_by ok len=3",      r10.ok and len(r10.get()) == 3)
    chk("ssep_by state=2",       r10.rest.state == 2)

    # ssep_by1 fail
    chk("ssep_by1 fail",         not ssep_by1[String, UInt8, Int, sdig_str, scomma_count](
        Ctx[Int](Input.from_string(String("abc")), 0)).ok)


# ── Integration ───────────────────────────────────────────────────────────────

def test_integration() raises:
    section("Integration")

    # 1. Parse unsigned integer: digits → Int
    @parameter
    def uint_p(inp: Input) -> ParseResult[Int]:
        var r = digits(inp)
        if not r.ok:
            var out = ParseResult[Int].failure(inp, r.msg)
            return out^
        var n = 0
        var s = r.get()
        for i in range(s.byte_length()):
            n = n * 10 + (Int(s.unsafe_ptr()[i]) - 48)
        var out = ParseResult[Int].success(n, r.rest)
        return out^

    var r1 = uint_p(Input.from_string(String("1234rest")))
    chk("uint ok",              r1.ok and r1.get() == 1234)
    chk("uint rest",            r1.rest.remaining() == 4)
    chk("uint fail",            not uint_p(Input.from_string(String("abc"))).ok)

    # 2. Parse comma-separated integers: 1,2,3
    var r2 = sep_by[Int, UInt8, uint_p, comma](Input.from_string(String("10,200,3")))
    chk("csv ints ok",          r2.ok and len(r2.get()) == 3)
    chk("csv first=10",         r2.get()[0] == 10)
    chk("csv last=3",           r2.get()[2] == 3)

    # 3. Parse identifier list: ident (ws , ws ident)*
    @parameter
    def ws_comma_ws(inp: Input) -> ParseResult[UInt8]:
        var r = skip_left[String, UInt8, ws, comma](inp)
        if not r.ok:
            var out = ParseResult[UInt8].failure(inp, r.msg)
            return out^
        var r2 = ws(r.rest)
        var out = ParseResult[UInt8].success(r.get(), r2.rest)
        return out^

    var r3 = sep_by[String, UInt8, ident, ws_comma_ws](
        Input.from_string(String("foo , bar , baz"))
    )
    chk("ident list ok",        r3.ok and len(r3.get()) == 3)
    chk("ident[0]=foo",         r3.get()[0] == "foo")
    chk("ident[2]=baz",         r3.get()[2] == "baz")


# ── Main ──────────────────────────────────────────────────────────────────────

def main() raises:
    test_input()
    test_result()
    test_prim()
    test_comb()
    test_new_prim()
    test_new_comb()
    test_state()
    test_integration()
    print("\nAll tests passed.")
