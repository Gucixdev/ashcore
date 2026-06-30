"""
ashllmtools.skills — layer 2: named, composable capabilities.

Skills compose tools into results. Skills do NOT call other skills.
The decision contract gates every skill before its tools fire.

Cognitive skills:
  plan, analyze, reason, reflect, evaluate, decide, decompose, schedule

Code skills:
  refactor, review, bughunt, stresstest, exec_tests, search_symbol

Each skill is registered in SkillRegistry by name and description.
Dispatch: registry.run(name, input) → SkillResult.
"""

from tools.sys.shell import shell_run
from tools.sys.git   import git_status, git_diff_staged
from tools.sys.fs    import read_text, file_exists
from decision_contract import _contains, Action, evaluate, RISK_BLOCK
from tools.trading.price      import fetch_quote, fetch_close_csv
from tools.trading.indicators import compute_indicator, _parse_csv_floats, _f2s, _list_last
from tools.trading.signals    import detect_signal
from tools.trading.portfolio  import portfolio_summary


# ── SkillResult ───────────────────────────────────────────────────────────────

struct SkillResult(Copyable, ImplicitlyCopyable, Movable, ImplicitlyDeletable):
    var ok:     Bool
    var output: String
    var reason: String   # why the skill failed (empty on success)

    def __init__(out self, ok: Bool, output: String, reason: String = ""):
        self.ok     = ok
        self.output = output
        self.reason = reason

    @staticmethod
    def success(output: String) -> SkillResult:
        return SkillResult(True, output, "")

    @staticmethod
    def failure(reason: String) -> SkillResult:
        return SkillResult(False, "", reason)


# ── Skill descriptor ──────────────────────────────────────────────────────────

struct Skill(Copyable, ImplicitlyCopyable, Movable, ImplicitlyDeletable):
    """Metadata for a registered skill."""
    var name:     String
    var desc:     String
    var category: String   # "cognitive" | "code" | "sys" | "web"

    def __init__(out self, name: String, desc: String, category: String):
        self.name     = name
        self.desc     = desc
        self.category = category


# ── Built-in skill implementations ────────────────────────────────────────────

def skill_git_status(inp: String) -> SkillResult:
    """Report current git working tree status."""
    var s = git_status()
    if s == "":
        return SkillResult.success("working tree clean")
    return SkillResult.success(s)


def skill_git_diff(inp: String) -> SkillResult:
    """Show staged changes."""
    var d = git_diff_staged()
    if d == "":
        return SkillResult.success("no staged changes")
    return SkillResult.success(d)


def skill_read_file(inp: String) -> SkillResult:
    """Read file at path given in inp."""
    var path = inp
    if not file_exists(path):
        return SkillResult.failure("file not found: " + path)
    var content = read_text(path)
    return SkillResult.success(content)


def skill_run_tests(inp: String) -> SkillResult:
    """Run the test suite. inp = directory containing pixi.toml."""
    var dir = inp if inp != "" else String(".")
    var r = shell_run("cd " + dir + " && pixi run test 2>&1")
    if not r.ok:
        return SkillResult.failure("test runner failed to start")
    return SkillResult(True, r.stdout, "")


def skill_search_symbol(inp: String) -> SkillResult:
    """Grep for a symbol across .mojo files. inp = symbol name."""
    var r = shell_run("grep -rn --include='*.mojo' '\\b" + inp + "\\b' . 2>/dev/null")
    if not r.ok or r.stdout == "":
        return SkillResult.failure("symbol not found: " + inp)
    return SkillResult.success(r.stdout)


def skill_reflect(inp: String) -> SkillResult:
    """Reflection stub: tag the last result with evaluation metadata."""
    if inp == "":
        return SkillResult.failure("reflect: no input to evaluate")
    var verdict = "ok"
    if _contains(inp, "ERROR") or _contains(inp, "FAIL") or _contains(inp, "failed"):
        verdict = "incorrect"
    return SkillResult.success("verdict=" + verdict + "\ninput_length=" + String(inp.byte_length()))


def skill_analyze(inp: String) -> SkillResult:
    """Analyze the given content and return key observations (stub)."""
    if inp == "":
        return SkillResult.failure("analyze: no input")
    var lines = 0
    for i in range(inp.byte_length()):
        if inp.unsafe_ptr()[i] == UInt8(10):
            lines += 1
    return SkillResult.success(
        "lines=" + String(lines) + " bytes=" + String(inp.byte_length())
    )


def skill_plan(inp: String) -> SkillResult:
    """Decompose inp into numbered steps — one non-empty line per step."""
    if inp == "":
        return SkillResult.failure("plan: no input")
    var out = String("steps:\n")
    var step = 1
    var n = inp.byte_length()
    var ptr = inp.unsafe_ptr()
    var line_start = 0
    for i in range(n):
        if ptr[i] == 10:
            if i > line_start:
                out += String(step) + ". " + inp[line_start:i] + "\n"
                step += 1
            line_start = i + 1
    if line_start < n:
        out += String(step) + ". " + inp[line_start:n] + "\n"
        step += 1
    if step == 1:
        out += "1. " + inp + "\n"
    return SkillResult.success(out)


def skill_reason(inp: String) -> SkillResult:
    """Step-by-step structural analysis: count claims and flag reasoning keywords."""
    if inp == "":
        return SkillResult.failure("reason: no input")
    var n = inp.byte_length()
    var ptr = inp.unsafe_ptr()
    var sentences = 0
    for i in range(n):
        var b = ptr[i]
        if b == 46 or b == 63 or b == 33:
            sentences += 1
    var flags = String("")
    if _contains(inp, "because"):
        flags += " causal"
    if _contains(inp, "therefore") or _contains(inp, "thus"):
        flags += " deductive"
    if _contains(inp, "if ") or _contains(inp, "when "):
        flags += " conditional"
    if _contains(inp, "but ") or _contains(inp, "however"):
        flags += " contrastive"
    if flags == "":
        flags = " declarative"
    var cap = 80 if n > 80 else n
    return SkillResult.success(
        "sentences=" + String(sentences) + " bytes=" + String(n)
        + " reasoning_type=" + flags
        + "\nanalysis: " + inp[:cap] + ("..." if n > 80 else "")
    )


def skill_decide(inp: String) -> SkillResult:
    """Heuristic decision: extract first option; flag destructive keywords."""
    if inp == "":
        return SkillResult.failure("decide: no input")
    var risky = (_contains(inp, "delete") or _contains(inp, "force")
                 or _contains(inp, "drop") or _contains(inp, "rm "))
    var n = inp.byte_length()
    var ptr = inp.unsafe_ptr()
    var end = n
    for i in range(n):
        if ptr[i] == 10:
            end = i
            break
    var decision = inp[:end]
    var verdict = "proceed" if not risky else "review_first"
    var out = "decision: " + decision + "\nverdict=" + verdict
    if risky:
        out += "\nwarning: destructive keywords detected"
    return SkillResult.success(out)


def skill_schedule(inp: String) -> SkillResult:
    """Order tasks by dependency keywords (after/before/first) found per line."""
    if inp == "":
        return SkillResult.failure("schedule: no input")
    var n = inp.byte_length()
    var ptr = inp.unsafe_ptr()
    var early = List[String]()
    var late  = List[String]()
    var rest  = List[String]()
    var ls = 0
    for i in range(n + 1):
        if i == n or ptr[i] == 10:
            if i > ls:
                var l = inp[ls:i]
                if _contains(l, "first") or _contains(l, "start") or _contains(l, "init"):
                    early.append(l)
                elif (_contains(l, "after") or _contains(l, "depends")
                      or _contains(l, "then")):
                    late.append(l)
                else:
                    rest.append(l)
            ls = i + 1
    var out = String("schedule:\n")
    var step = 1
    for i in range(len(early)):
        out += String(step) + ". " + early[i] + "\n"
        step += 1
    for i in range(len(rest)):
        out += String(step) + ". " + rest[i] + "\n"
        step += 1
    for i in range(len(late)):
        out += String(step) + ". " + late[i] + "\n"
        step += 1
    return SkillResult.success(out)


def skill_bughunt(inp: String) -> SkillResult:
    """Grep codebase for error/panic/FIXME patterns in the given path."""
    var path = inp if inp != "" else String(".")
    var r1 = shell_run(
        "grep -rn --include='*.mojo' -E 'panic|ERROR|unreachable' "
        + path + " 2>/dev/null | head -30"
    )
    var r2 = shell_run(
        "grep -rn --include='*.mojo' -E 'TODO|FIXME|HACK|XXX' "
        + path + " 2>/dev/null | head -20"
    )
    var hits  = r1.stdout if r1.ok else String("")
    var todos = r2.stdout if r2.ok else String("")
    if hits == "" and todos == "":
        return SkillResult.success("bughunt: no error patterns or TODOs found in " + path)
    var out = String("")
    if hits != "":
        out += "=== error/panic patterns ===\n" + hits
    if todos != "":
        out += "=== TODO/FIXME ===\n" + todos
    return SkillResult.success(out)


def skill_review(inp: String) -> SkillResult:
    """Code review: diff stats and flag suspicious patterns in staged changes."""
    var diff = git_diff_staged()
    if diff == "":
        diff = shell_run("git diff HEAD 2>/dev/null").stdout
    if diff == "":
        return SkillResult.success("review: no changes to review")
    var n = diff.byte_length()
    var ptr = diff.unsafe_ptr()
    var added = 0
    var removed = 0
    var i = 0
    while i < n:
        if ptr[i] == 43 and (i == 0 or ptr[i - 1] == 10):
            if not (i + 2 < n and ptr[i + 1] == 43 and ptr[i + 2] == 43):
                added += 1
        elif ptr[i] == 45 and (i == 0 or ptr[i - 1] == 10):
            if not (i + 2 < n and ptr[i + 1] == 45 and ptr[i + 2] == 45):
                removed += 1
        i += 1
    var warnings = String("")
    if _contains(diff, "unsafe_ptr"):
        warnings += " unsafe_ptr"
    if _contains(diff, "external_call"):
        warnings += " external_call"
    if _contains(diff, "TODO"):
        warnings += " TODO"
    var verdict = "ok" if removed + added < 500 else "large_diff"
    var out = ("added=" + String(added) + " removed=" + String(removed)
               + " verdict=" + verdict)
    if warnings != "":
        out += "\nflags:" + warnings
    return SkillResult.success(out)


def skill_refactor(inp: String) -> SkillResult:
    """Read file at inp and return structural metrics and refactoring hints."""
    if inp == "":
        return SkillResult.failure("refactor: no file path provided")
    if not file_exists(inp):
        return SkillResult.failure("refactor: file not found: " + inp)
    var content = read_text(inp)
    var n = content.byte_length()
    var ptr = content.unsafe_ptr()
    var lines = 0
    var long_lines = 0
    var line_len = 0
    for i in range(n):
        if ptr[i] == 10:
            lines += 1
            if line_len > 100:
                long_lines += 1
            line_len = 0
        else:
            line_len += 1
    var r_def    = shell_run("grep -c '^def \\|^    def ' " + inp + " 2>/dev/null")
    var r_struct = shell_run("grep -c '^struct ' "          + inp + " 2>/dev/null")
    var out = ("file=" + inp + " lines=" + String(lines) + " bytes=" + String(n)
               + " defs="    + (r_def.stdout    if r_def.ok    else String("?"))
               + " structs=" + (r_struct.stdout if r_struct.ok else String("?")))
    if long_lines > 5:
        out += "\nhint: " + String(long_lines) + " lines exceed 100 chars"
    return SkillResult.success(out)


def skill_stresstest(inp: String) -> SkillResult:
    """Search for missing edge-case handling (boundary accesses, while-True loops)."""
    var path = inp if inp != "" else String(".")
    var r1 = shell_run(
        "grep -rn --include='*.mojo' -E "
        + "'\\[0\\]|\\[-1\\]|unsafe_ptr\\(\\)\\[|range\\(0\\)' "
        + path + " 2>/dev/null | head -30"
    )
    var r2 = shell_run(
        "grep -rn --include='*.mojo' 'while True' "
        + path + " 2>/dev/null | head -20"
    )
    var hits  = r1.stdout if r1.ok else String("")
    var loops = r2.stdout if r2.ok else String("")
    if hits == "" and loops == "":
        return SkillResult.success("stresstest: no obvious edge-case gaps found in " + path)
    var out = String("")
    if hits != "":
        out += "=== boundary accesses ===\n" + hits
    if loops != "":
        out += "=== while True loops ===\n" + loops
    return SkillResult.success(out)


# ── Trading skill implementations ────────────────────────────────────────────

def skill_price_fetch(inp: String) -> SkillResult:
    """Fetch latest market quote for a symbol. inp='AAPL' or 'BTC-USD'."""
    var symbol = inp
    var n = inp.byte_length()
    var ptr = inp.unsafe_ptr()
    var lo = 0
    var hi = n
    while lo < n and (ptr[lo] == 32 or ptr[lo] == 9): lo += 1
    while hi > lo and (ptr[hi-1] == 32 or ptr[hi-1] == 9): hi -= 1
    symbol = inp[lo:hi]
    if symbol == "":
        return SkillResult.failure("price_fetch: no symbol provided")
    var result = fetch_quote(symbol)
    if _contains(result, "error:"):
        return SkillResult.failure(result)
    return SkillResult.success(result)


def skill_indicator_calc(inp: String) -> SkillResult:
    """Compute a technical indicator on price data.
    inp format: 'prices:100.5,101,99.8,... indicator:sma period:5'
    or bare CSV with defaults (sma, period 10)."""
    if inp == "":
        return SkillResult.failure("indicator_calc: no input")
    var prices_csv = inp
    var indicator  = String("sma")
    var period     = 10
    # Parse keyword args if present
    var inp_n = inp.byte_length()
    var inp_p = inp.unsafe_ptr()
    if _contains(inp, "prices:"):
        var markers = List[String]()
        markers.append("prices:")
        markers.append(" indicator:")
        markers.append(" period:")
        # Extract prices: value
        var key = String("prices:")
        var kl  = key.byte_length()
        var kp  = key.unsafe_ptr()
        for i in range(inp_n - kl + 1):
            var hit = True
            for j in range(kl):
                if inp_p[i+j] != kp[j]:
                    hit = False; break
            if hit:
                var k = i + kl
                while k < inp_n and inp_p[k] == 32: k += 1
                var end = k
                while end < inp_n and inp_p[end] != 32: end += 1
                prices_csv = inp[k:end]
                break
        # Extract indicator:
        var key2 = String(" indicator:")
        var k2l  = key2.byte_length()
        var k2p  = key2.unsafe_ptr()
        for i in range(inp_n - k2l + 1):
            var hit = True
            for j in range(k2l):
                if inp_p[i+j] != k2p[j]:
                    hit = False; break
            if hit:
                var k = i + k2l
                while k < inp_n and inp_p[k] == 32: k += 1
                var end = k
                while end < inp_n and inp_p[end] != 32: end += 1
                indicator = inp[k:end]
                break
        # Extract period:
        var key3 = String(" period:")
        var k3l  = key3.byte_length()
        var k3p  = key3.unsafe_ptr()
        for i in range(inp_n - k3l + 1):
            var hit = True
            for j in range(k3l):
                if inp_p[i+j] != k3p[j]:
                    hit = False; break
            if hit:
                var k = i + k3l
                while k < inp_n and inp_p[k] == 32: k += 1
                var end = k
                while end < inp_n and inp_p[end] != 32: end += 1
                var tok = inp[k:end]
                var pp = tok.unsafe_ptr()
                var pv = 0
                for ci in range(tok.byte_length()):
                    if pp[ci] >= 48 and pp[ci] <= 57:
                        pv = pv * 10 + Int(pp[ci]) - 48
                if pv > 0: period = pv
                break
    var result = compute_indicator(prices_csv, indicator, period)
    if _contains(result, "error:"):
        return SkillResult.failure(result)
    return SkillResult.success(result)


def skill_signal_detect(inp: String) -> SkillResult:
    """Detect buy/sell/hold signal from comma-separated price CSV.
    inp: '100.5,101.2,99.8,...' (min slow+1 values, default slow=20)."""
    if inp == "":
        return SkillResult.failure("signal_detect: no price data provided")
    var result = detect_signal(inp)
    if _contains(result, "error:"):
        return SkillResult.failure(result)
    return SkillResult.success(result)


def skill_portfolio_analyze(inp: String) -> SkillResult:
    """Analyze a portfolio from text.
    inp format (one position per line): 'AAPL 100 150.50'  (symbol qty cost)
    cash line: 'cash 5000'."""
    if inp == "":
        return SkillResult.failure("portfolio_analyze: no portfolio data provided")
    var result = portfolio_summary(inp)
    if _contains(result, "error:"):
        return SkillResult.failure(result)
    return SkillResult.success(result)


def skill_backtest(inp: String) -> SkillResult:
    """Simple SMA crossover backtest on price CSV.
    inp: 'prices:100,101,...  fast:5  slow:20'  → trades + final PnL."""
    if inp == "":
        return SkillResult.failure("backtest: no input provided")
    # Parse prices_csv (use full inp as fallback)
    var prices_csv = inp
    var fast_p = 5
    var slow_p = 20
    var inp_n = inp.byte_length()
    var inp_ptr = inp.unsafe_ptr()
    # Extract prices: section if present
    var pk = String("prices:")
    var pkl = pk.byte_length()
    var pkp = pk.unsafe_ptr()
    for i in range(inp_n - pkl + 1):
        var hit = True
        for j in range(pkl):
            if inp_ptr[i+j] != pkp[j]:
                hit = False; break
        if hit:
            var k = i + pkl
            var end = k
            while end < inp_n and inp_ptr[end] != 32: end += 1
            prices_csv = inp[k:end]
            break
    # Extract fast: and slow:
    for kw_str in List[String]("fast:", "slow:"):
        var kw = kw_str
        var kl = kw.byte_length()
        var kp = kw.unsafe_ptr()
        for i in range(inp_n - kl + 1):
            var hit = True
            for j in range(kl):
                if inp_ptr[i+j] != kp[j]:
                    hit = False; break
            if hit:
                var k = i + kl
                var end = k
                while end < inp_n and inp_ptr[end] != 32: end += 1
                var tok = inp[k:end]
                var tp = tok.unsafe_ptr()
                var tv = 0
                for ci in range(tok.byte_length()):
                    if tp[ci] >= 48 and tp[ci] <= 57:
                        tv = tv * 10 + Int(tp[ci]) - 48
                if tv > 0:
                    if kw_str == "fast:":
                        fast_p = tv
                    else:
                        slow_p = tv
                break
    from tools.trading.indicators import sma as _sma
    var prices = _parse_csv_floats(prices_csv)
    var n = len(prices)
    if n < slow_p + 2:
        return SkillResult.failure(
            "backtest: need at least " + String(slow_p + 2) + " prices"
        )
    var fast_vals = _sma(prices, fast_p)
    var slow_vals = _sma(prices, slow_p)
    # Align: fast is longer; offset = fast_len - slow_len
    var fast_len = len(fast_vals)
    var slow_len = len(slow_vals)
    var offset   = fast_len - slow_len
    var trades   = 0
    var position = False
    var entry    = Float64(0)
    var pnl      = Float64(0)
    for i in range(1, slow_len):
        var f_prev = fast_vals[offset + i - 1]
        var s_prev = slow_vals[i - 1]
        var f_cur  = fast_vals[offset + i]
        var s_cur  = slow_vals[i]
        if not position and f_prev <= s_prev and f_cur > s_cur:
            position = True
            entry    = prices[i + slow_p - 1]
            trades  += 1
        elif position and f_prev >= s_prev and f_cur < s_cur:
            position = False
            pnl     += prices[i + slow_p - 1] - entry
            entry    = Float64(0)
    if position:
        pnl += prices[n - 1] - entry  # mark-to-market
    return SkillResult.success(
        "backtest: fast=" + String(fast_p) + " slow=" + String(slow_p)
        + " bars=" + String(n)
        + " trades=" + String(trades)
        + " pnl=" + _f2s(pnl)
        + (" (open_position)" if position else "")
    )


# ── SkillRegistry ─────────────────────────────────────────────────────────────

struct SkillRegistry(Movable):
    """
    Named skill registry with dispatch.

    Built-in skills are registered at construction.
    Custom skills can be added via register().
    """
    var _skills: List[Skill]

    def __init__(out self):
        self._skills = List[Skill]()
        self._register_builtins()

    def __moveinit__(out self, owned other: Self):
        self._skills = other._skills^

    def register(mut self, name: String, desc: String, category: String):
        self._skills.append(Skill(name=name, desc=desc, category=category))

    def run(self, name: String, inp: String) -> SkillResult:
        """Dispatch to built-in skill.
        Decision contract is the FIRST gate — no skill executes if blocked."""
        # ── Decision contract firewall ────────────────────────────────────────
        var action = Action(cmd=name + "(" + inp + ")", scope="skill")
        var guard  = evaluate(action)
        if guard.is_block():
            return SkillResult.failure("BLOCKED [contract]: " + guard.reason)
        # ── Dispatch ─────────────────────────────────────────────────────────
        if name == "git_status":   return skill_git_status(inp)
        if name == "git_diff":     return skill_git_diff(inp)
        if name == "read_file":    return skill_read_file(inp)
        if name == "run_tests":    return skill_run_tests(inp)
        if name == "search":       return skill_search_symbol(inp)
        if name == "reflect":      return skill_reflect(inp)
        if name == "analyze":      return skill_analyze(inp)
        if name == "plan":         return skill_plan(inp)
        if name == "reason":       return skill_reason(inp)
        if name == "decide":       return skill_decide(inp)
        if name == "schedule":     return skill_schedule(inp)
        if name == "bughunt":      return skill_bughunt(inp)
        if name == "review":       return skill_review(inp)
        if name == "refactor":     return skill_refactor(inp)
        if name == "stresstest":       return skill_stresstest(inp)
        if name == "price_fetch":      return skill_price_fetch(inp)
        if name == "indicator_calc":   return skill_indicator_calc(inp)
        if name == "signal_detect":    return skill_signal_detect(inp)
        if name == "portfolio_analyze":return skill_portfolio_analyze(inp)
        if name == "backtest":         return skill_backtest(inp)
        return SkillResult.failure("unknown skill: " + name)

    def list(self) -> List[String]:
        var names = List[String]()
        for i in range(len(self._skills)):
            names.append(self._skills[i].name)
        return names

    def find(self, name: String) -> Bool:
        for i in range(len(self._skills)):
            if self._skills[i].name == name:
                return True
        return False

    def size(self) -> Int:
        return len(self._skills)

    def _register_builtins(mut self):
        self.register("git_status",  "show working tree status",       "sys")
        self.register("git_diff",    "show staged changes",            "sys")
        self.register("read_file",   "read file content",              "code")
        self.register("run_tests",   "run test suite",                 "code")
        self.register("search",      "search for symbol in codebase",  "code")
        self.register("reflect",     "evaluate last result",           "cognitive")
        self.register("analyze",     "analyze content for insights",   "cognitive")
        self.register("plan",        "decompose goal into task list",  "cognitive")
        self.register("reason",      "step-by-step reasoning",         "cognitive")
        self.register("decide",      "choose between options",         "cognitive")
        self.register("bughunt",     "locate root cause of a bug",     "code")
        self.register("stresstest",  "find edge cases in code",        "code")
        self.register("review",      "code review with verdict",       "code")
        self.register("refactor",    "targeted code improvement",      "code")
        self.register("schedule",         "sequence tasks by dependency",   "cognitive")
        self.register("price_fetch",      "fetch latest market quote",      "trading")
        self.register("indicator_calc",   "compute SMA/EMA/RSI/MACD",      "trading")
        self.register("signal_detect",    "buy/sell/hold signal from prices","trading")
        self.register("portfolio_analyze","P&L and allocation breakdown",   "trading")
        self.register("backtest",         "SMA crossover backtest",         "trading")
