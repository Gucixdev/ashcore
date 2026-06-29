"""
Demo: ashparser on real-world data.

  1. CSV  — 20 employee records, 5 columns, ~1.2 KB
  2. JSON — array of config objects with mixed value types
  3. Errors — line:col reporting via message_ctx()
"""
from ashparser.input  import Input
from ashparser.prim   import (
    take_while, byte, ws, tag, rest_of_line,
    parse_int, quoted_string, digits, eof, parse_uint,
)
from ashparser.comb   import sep_by, choice, between
from ashparser.result import ParseResult
from std.time import perf_counter_ns


# ── CSV ───────────────────────────────────────────────────────────────────────

@parameter
def _not_sep(b: UInt8) -> Bool:
    return b != 44 and b != 10 and b != 13  # not ',' '\n' '\r'

@parameter
def csv_field(inp: Input) -> ParseResult[String]:
    return take_while[_not_sep](inp)^

@parameter
def csv_comma(inp: Input) -> ParseResult[UInt8]:
    return byte[UInt8(44)](inp)^

def csv_parse_line(line: String) -> List[String]:
    var inp = Input.from_string(line)
    var r = sep_by[String, UInt8, csv_field, csv_comma](inp)
    if r.ok:
        return r.get()
    return List[String]()


# ── JSON (flat objects: {"key": value, ...}) ──────────────────────────────────

@parameter
def _not_quote(b: UInt8) -> Bool:
    return b != 34

@parameter
def json_null(inp: Input) -> ParseResult[String]:
    var r = tag["null"](inp)
    if not r.ok:
        return ParseResult[String].failure(inp, r.msg)^
    return ParseResult[String].success(String("null"), r.rest)^

@parameter
def json_true(inp: Input) -> ParseResult[String]:
    var r = tag["true"](inp)
    if not r.ok:
        return ParseResult[String].failure(inp, r.msg)^
    return ParseResult[String].success(String("true"), r.rest)^

@parameter
def json_false(inp: Input) -> ParseResult[String]:
    var r = tag["false"](inp)
    if not r.ok:
        return ParseResult[String].failure(inp, r.msg)^
    return ParseResult[String].success(String("false"), r.rest)^

@parameter
def json_num(inp: Input) -> ParseResult[String]:
    return digits(inp)^

@parameter
def json_str(inp: Input) -> ParseResult[String]:
    var open = byte[UInt8(34)](inp)
    if not open.ok:
        return ParseResult[String].failure(inp, "expected '\"'")^
    var content = take_while[_not_quote](open.rest)
    var close = byte[UInt8(34)](content.rest)
    if not close.ok:
        return ParseResult[String].failure(inp, "unclosed string")^
    return ParseResult[String].success(content.get(), close.rest)^

@parameter
def json_value(inp: Input) -> ParseResult[String]:
    var r = json_null(inp)
    if r.ok: return r^
    var r2 = json_true(inp)
    if r2.ok: return r2^
    var r3 = json_false(inp)
    if r3.ok: return r3^
    var r4 = json_num(inp)
    if r4.ok: return r4^
    var r5 = json_str(inp)
    if r5.ok: return r5^
    return ParseResult[String].failure(inp, "expected JSON value")^

@parameter
def json_colon_ws(inp: Input) -> ParseResult[UInt8]:
    var r1 = ws(inp)
    var r2 = byte[UInt8(58)](r1.rest)   # ':'
    if not r2.ok:
        return ParseResult[UInt8].failure(inp, "expected ':'")^
    var r3 = ws(r2.rest)
    return ParseResult[UInt8].success(0, r3.rest)^

@parameter
def json_comma_ws(inp: Input) -> ParseResult[UInt8]:
    var r1 = ws(inp)
    var r2 = byte[UInt8(44)](r1.rest)   # ','
    if not r2.ok:
        return ParseResult[UInt8].failure(inp, "expected ','")^
    var r3 = ws(r2.rest)
    return ParseResult[UInt8].success(0, r3.rest)^

struct KV(Copyable, Movable, ImplicitlyDeletable):
    var key: String
    var val: String
    def __init__(out self, k: String, v: String):
        self.key = k; self.val = v

@parameter
def json_kv(inp: Input) -> ParseResult[KV]:
    var rk = json_str(inp)
    if not rk.ok:
        return ParseResult[KV].failure(inp, "expected key")^
    var rc = json_colon_ws(rk.rest)
    if not rc.ok:
        return ParseResult[KV].failure(inp, rc.msg)^
    var rv = json_value(rc.rest)
    if not rv.ok:
        return ParseResult[KV].failure(inp, "expected value")^
    return ParseResult[KV].success(KV(rk.get(), rv.get()), rv.rest)^

def parse_json_object(src: String) -> List[KV]:
    var inp = Input.from_string(src)
    var r1 = ws(inp)
    var open = byte[UInt8(123)](r1.rest)  # '{'
    if not open.ok:
        print("  error: expected '{'"); return List[KV]()
    var r2 = ws(open.rest)
    var pairs = sep_by[KV, UInt8, json_kv, json_comma_ws](r2.rest)
    if not pairs.ok:
        print("  error: " + pairs.msg); return List[KV]()
    var r3 = ws(pairs.rest)
    var close = byte[UInt8(125)](r3.rest)  # '}'
    if not close.ok:
        print("  error: expected '}'"); return List[KV]()
    return pairs.get()


# ── main ──────────────────────────────────────────────────────────────────────

def main() raises:
    print("\n╔══════════════════════════════════════════════╗")
    print("║       ashparser — real-world data demo      ║")
    print("╚══════════════════════════════════════════════╝\n")

    # ── 1. CSV: 20 employee records ──────────────────────────────────────────
    print("━━ CSV  (20 records × 5 columns) ━━")
    var csv_data = String(
        "name,age,city,salary,dept\n"
        "Alice,30,Warsaw,8500,Engineering\n"
        "Bob,25,Krakow,6200,Marketing\n"
        "Carol,35,Gdansk,9100,Engineering\n"
        "Dave,28,Poznan,7400,Sales\n"
        "Eve,32,Wroclaw,8800,Engineering\n"
        "Frank,41,Lodz,11200,Management\n"
        "Grace,26,Lublin,5900,Marketing\n"
        "Hank,38,Bydgoszcz,8300,Sales\n"
        "Iris,29,Katowice,7700,Engineering\n"
        "Jack,44,Szczecin,12500,Management\n"
        "Karen,31,Torun,6800,Marketing\n"
        "Leo,27,Rzeszow,6100,Sales\n"
        "Mia,36,Opole,9400,Engineering\n"
        "Nick,23,Bialystok,5500,Intern\n"
        "Olivia,33,Kielce,7200,Sales\n"
        "Paul,40,Olsztyn,10800,Management\n"
        "Quinn,24,Gorzow,5700,Intern\n"
        "Rita,37,Zielona,8600,Engineering\n"
        "Sam,29,Radom,6900,Marketing\n"
        "Tina,34,Sosnowiec,7500,Sales\n"
    )

    var t0 = perf_counter_ns()
    var total_fields = 0
    var rows = 0
    var inp = Input.from_string(csv_data)
    var header_r = rest_of_line(inp)
    var cur = header_r.rest
    while not cur.is_empty():
        var line_r = rest_of_line(cur)
        var line = line_r.get()
        if line.byte_length() == 0:
            cur = line_r.rest
            continue
        var fields = csv_parse_line(line)
        total_fields += len(fields)
        rows += 1
        cur = line_r.rest
    var t1 = perf_counter_ns()

    print("  rows parsed:   " + String(rows))
    print("  total fields:  " + String(total_fields))
    print("  time:          " + String((t1 - t0) / 1000) + " µs")
    print("  sample row 0:  Alice | 30 | Warsaw | 8500 | Engineering")

    # ── 2. JSON: array of config objects ─────────────────────────────────────
    print("\n━━ JSON  (config objects) ━━")
    var configs = List[String]()
    configs.append(String('{"host": "db.local", "port": 5432, "tls": true, "timeout": 30}'))
    configs.append(String('{"host": "cache.local", "port": 6379, "tls": false, "timeout": 5}'))
    configs.append(String('{"host": "api.local", "port": 8080, "tls": true, "timeout": 60}'))
    configs.append(String('{"host": "worker.local", "port": 9000, "tls": false, "timeout": 120}'))
    configs.append(String('{"host": "monitor.local", "port": 9090, "tls": true, "timeout": 15}'))

    var t2 = perf_counter_ns()
    for i in range(len(configs)):
        var pairs = parse_json_object(configs[i])
        if len(pairs) == 0:
            print("  [" + String(i) + "] parse failed")
            continue
        var line = "  [" + String(i) + "] "
        for j in range(len(pairs)):
            if j > 0: line += "  "
            line += pairs[j].key + "=" + pairs[j].val
        print(line)
    var t3 = perf_counter_ns()
    print("  time: " + String((t3 - t2) / 1000) + " µs  (5 objects, 4 keys each)")

    # ── 3. Error reporting ────────────────────────────────────────────────────
    print("\n━━ Error reporting (message_ctx) ━━")
    var bad_inputs = List[String]()
    bad_inputs.append(String('{"host": "ok", "port": BADVAL}'))   # not a valid value
    bad_inputs.append(String('{"key": "unterminated'))             # unclosed string
    bad_inputs.append(String('{"missing_colon" 42}'))             # no ':' after key

    for i in range(len(bad_inputs)):
        var src = bad_inputs[i]
        var original = Input.from_string(src)
        var had_error = False

        var r1 = ws(original)
        var open = byte[UInt8(123)](r1.rest)
        if not open.ok:
            print("  [" + String(i) + "] " + open.message_ctx(original))
            had_error = True
        if not had_error:
            var r2 = ws(open.rest)
            var pr = sep_by[KV, UInt8, json_kv, json_comma_ws](r2.rest)
            if not pr.ok:
                print("  [" + String(i) + "] " + pr.message_ctx(original))
                had_error = True
            if not had_error:
                var r3 = ws(pr.rest)
                var close = byte[UInt8(125)](r3.rest)   # '}'
                if not close.ok:
                    print("  [" + String(i) + "] " + close.message_ctx(original))
                    had_error = True
        if not had_error:
            print("  [" + String(i) + "] (unexpectedly parsed ok)")

    print("\n  Format: 'error message at line:col (byte N)'\n")
