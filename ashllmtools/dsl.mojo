"""
ashllmtools.dsl — compact relational notation for world model and context facts.

Multi-line parsing (parse_facts) uses ashparser for clean line iteration;
single-fact parsing (parse_fact) is a hand-rolled leftmost-operator scan
because the 24-operator grammar requires non-left-to-right operator detection.

Operator table (scanned longest-first to avoid prefix ambiguity):

  <->   bidirectional relation          a <-> b
  +-    partial modification / change   config +- timeout
  &&    dependent sequence              task_a && task_b
  ??    open question                   perf ?? unknown
  >>    leads to / results in           error >> retry
  <<    originates from / results from  token << vault
  <=    storage / responsibility        secrets <= env
  <>    equivalence                     dev <> local
  !=    inequality / conflict           prod != staging
  ==    comparison                      ver == 2
  =     definition / assignment         env = production
  >     preference / recommendation     cache > db
  +     conjunction / composition       auth + tls
  -     negation / removal              debug -
  /     alternative / or               json / msgpack
  !     attention / warning             ! rate_limit
  ?     check / verify                  health ?
  ~     approximation / default         timeout ~ 30
  &     sharing / reference             pool & workers
  *     all cases                       * endpoints
  $     requirement / cost / endpoint   tls $
  %     remainder / slice / dependent   rows % 1000
  ^     source / superordinate          ^ config
  @     destination / annotation        log @ stdout

Context annotation: trailing (...) on any fact line
  env = production (staging)  → lhs="env" op="=" rhs="production" ctx="staging"
"""

# ── Operator aliases ──────────────────────────────────────────────────────────

alias OP_BIDIR  = "<->"
alias OP_MOD    = "+-"
alias OP_SEQ    = "&&"
alias OP_OPEN   = "??"
alias OP_LEADS  = ">>"
alias OP_FROM   = "<<"
alias OP_OWN    = "<="
alias OP_EQUIV  = "<>"
alias OP_NEQ    = "!="
alias OP_EQ     = "=="
alias OP_DEF    = "="
alias OP_PREF   = ">"
alias OP_AND    = "+"
alias OP_NOT    = "-"
alias OP_OR     = "/"
alias OP_WARN   = "!"
alias OP_CHECK  = "?"
alias OP_APPROX = "~"
alias OP_REF    = "&"
alias OP_ALL    = "*"
alias OP_REQ    = "$"
alias OP_SLICE  = "%"
alias OP_SRC    = "^"
alias OP_AT     = "@"


# ── Internal helpers ──────────────────────────────────────────────────────────

def _find_substr(h: String, n: String) -> Int:
    """Return byte index of first occurrence of n in h, or -1."""
    var hl = h.byte_length()
    var nl = n.byte_length()
    if nl == 0 or nl > hl:
        return -1
    var hp = h.unsafe_ptr()
    var np = n.unsafe_ptr()
    for i in range(hl - nl + 1):
        var hit = True
        for j in range(nl):
            if hp[i + j] != np[j]:
                hit = False
                break
        if hit:
            return i
    return -1


def _trim(s: String) -> String:
    """Strip leading/trailing spaces and tabs."""
    var n = s.byte_length()
    if n == 0:
        return s
    var ptr = s.unsafe_ptr()
    var lo = 0
    var hi = n
    while lo < n and (ptr[lo] == 32 or ptr[lo] == 9):
        lo += 1
    while hi > lo and (ptr[hi - 1] == 32 or ptr[hi - 1] == 9):
        hi -= 1
    return String(s[byte=lo:hi])


def _all_ops() -> List[String]:
    """Operators in priority order: longest first, then defined order."""
    var ops = List[String]()
    # 3-char
    ops.append("<->")
    # 2-char
    ops.append("+-")
    ops.append("&&")
    ops.append("??")
    ops.append(">>")
    ops.append("<<")
    ops.append("<=")
    ops.append("<>")
    ops.append("!=")
    ops.append("==")
    # 1-char
    ops.append("=")
    ops.append(">")
    ops.append("+")
    ops.append("-")
    ops.append("/")
    ops.append("!")
    ops.append("?")
    ops.append("~")
    ops.append("&")
    ops.append("*")
    ops.append("$")
    ops.append("%")
    ops.append("^")
    ops.append("@")
    return ops^


# ── DSLFact ───────────────────────────────────────────────────────────────────

struct DSLFact(Copyable, ImplicitlyCopyable, Movable, ImplicitlyDeletable):
    """
    One parsed DSL fact: lhs op rhs (ctx).

    ok=False when no operator was found in the input line.
    """
    var lhs: String
    var op:  String
    var rhs: String
    var ctx: String
    var ok:  Bool

    def __init__(out self, lhs: String, op: String, rhs: String,
                 ctx: String = "", ok: Bool = True):
        self.lhs = lhs
        self.op  = op
        self.rhs = rhs
        self.ctx = ctx
        self.ok  = ok

    @staticmethod
    def bad(line: String) -> DSLFact:
        return DSLFact(lhs=line, op="", rhs="", ctx="", ok=False)

    def to_string(self) -> String:
        var out = self.lhs + " " + self.op + " " + self.rhs
        if self.ctx != "":
            out += " (" + self.ctx + ")"
        return out

    def describe(self) -> String:
        var out = "DSLFact(lhs=" + self.lhs + " op=" + self.op + " rhs=" + self.rhs
        if self.ctx != "":
            out += " ctx=" + self.ctx
        out += ")"
        return out


# ── Parser ────────────────────────────────────────────────────────────────────

def parse_fact(line: String) -> DSLFact:
    """
    Parse one DSL fact line into a DSLFact.

    Steps:
      1. Trim whitespace.
      2. Scan for each operator (longest first); record (op, position).
      3. Pick the leftmost match; ties broken by operator length (longer wins).
      4. Split into lhs = s[:pos] and rhs_raw = s[pos+len(op):].
      5. Trim both sides.
      6. Extract trailing (...) from rhs as ctx.
    """
    var s = _trim(line)
    if s.byte_length() == 0:
        return DSLFact.bad(line)

    var ops = _all_ops()
    var best_pos = s.byte_length()
    var best_op  = String("")

    for oi in range(len(ops)):
        var op  = ops[oi]
        var pos = _find_substr(s, op)
        if pos < 0:
            continue
        if pos < best_pos:
            best_pos = pos
            best_op  = op
        elif pos == best_pos and op.byte_length() > best_op.byte_length():
            best_op  = op

    if best_op == "":
        return DSLFact.bad(line)

    var lhs = _trim(String(s[byte=:best_pos]))
    var rhs_raw = _trim(String(s[byte=best_pos + best_op.byte_length():]))

    # Extract trailing (...) from rhs as context
    var rhs = rhs_raw
    var ctx = String("")
    var rn  = rhs_raw.byte_length()
    var rp  = rhs_raw.unsafe_ptr()
    var close = -1
    for i in range(rn - 1, -1, -1):
        if rp[i] == 41:   # ')'
            close = i; break
    if close >= 0:
        var open_ = -1
        for i in range(close - 1, -1, -1):
            if rp[i] == 40:   # '('
                open_ = i; break
        if open_ >= 0:
            ctx = String(rhs_raw[byte=open_ + 1:close])
            rhs = _trim(String(rhs_raw[byte=:open_]))

    return DSLFact(lhs=lhs, op=best_op, rhs=rhs, ctx=ctx)


def parse_facts(text: String) -> List[DSLFact]:
    """Parse every non-empty, non-comment line in text using ashparser line iteration."""
    from ashparser.input import Input
    from ashparser.prim  import rest_of_line, line_ending
    var out = List[DSLFact]()
    var inp = Input.from_string(text)
    while not inp.is_empty():
        var r_line = rest_of_line(inp)
        var line   = _trim(r_line.get()) if r_line.ok else String("")
        inp = r_line.rest
        var r_le = line_ending(inp)
        if r_le.ok: inp = r_le.rest
        if line.byte_length() == 0 or line.unsafe_ptr()[0] == 35: continue
        out.append(parse_fact(line))
    return out


# ── DSLStore ──────────────────────────────────────────────────────────────────

struct DSLStore(Movable):
    """
    Collection of DSLFact entries with query and render methods.

    Example:
        var store = DSLStore()
        store.add_line("env = production (staging)")
        store.add_line("cache > db (latency)")
        store.add_line("api_key << vault")
        print(store.to_string())
    """
    var _facts: List[DSLFact]

    def __init__(out self):
        self._facts = List[DSLFact]()

    def __moveinit__(out self, owned other: Self):
        self._facts = other._facts^

    def add(mut self, fact: DSLFact):
        self._facts.append(fact)

    def add_line(mut self, line: String):
        """Parse line and append the resulting DSLFact."""
        self._facts.append(parse_fact(line))

    def add_text(mut self, text: String):
        """Parse every line in text and append all valid facts."""
        var facts = parse_facts(text)
        for i in range(len(facts)):
            self._facts.append(facts[i])

    def size(self) -> Int:
        return len(self._facts)

    def clear(mut self):
        self._facts = List[DSLFact]()

    def query_lhs(self, lhs: String) -> List[DSLFact]:
        """All facts whose lhs matches."""
        var out = List[DSLFact]()
        for i in range(len(self._facts)):
            if self._facts[i].lhs == lhs:
                out.append(self._facts[i])
        return out

    def query_op(self, op: String) -> List[DSLFact]:
        """All facts that use the given operator."""
        var out = List[DSLFact]()
        for i in range(len(self._facts)):
            if self._facts[i].op == op:
                out.append(self._facts[i])
        return out

    def query_rhs(self, rhs: String) -> List[DSLFact]:
        """All facts whose rhs matches."""
        var out = List[DSLFact]()
        for i in range(len(self._facts)):
            if self._facts[i].rhs == rhs:
                out.append(self._facts[i])
        return out

    def get(self, lhs: String, op: String) -> String:
        """rhs of the first fact matching lhs+op, or '' if not found."""
        for i in range(len(self._facts)):
            var f = self._facts[i]
            if f.lhs == lhs and f.op == op:
                return f.rhs
        return String("")

    def has(self, lhs: String, op: String, rhs: String) -> Bool:
        """True iff any stored fact matches all three fields."""
        for i in range(len(self._facts)):
            var f = self._facts[i]
            if f.lhs == lhs and f.op == op and f.rhs == rhs:
                return True
        return False

    def update(mut self, lhs: String, op: String, rhs: String):
        """Update rhs of first matching lhs+op fact (preserving ctx), or append."""
        for i in range(len(self._facts)):
            if self._facts[i].lhs == lhs and self._facts[i].op == op:
                var ctx = self._facts[i].ctx
                self._facts[i] = DSLFact(lhs=lhs, op=op, rhs=rhs, ctx=ctx)
                return
        self._facts.append(DSLFact(lhs=lhs, op=op, rhs=rhs))

    def remove(mut self, lhs: String, op: String):
        """Remove all facts matching lhs+op."""
        var kept = List[DSLFact]()
        for i in range(len(self._facts)):
            if not (self._facts[i].lhs == lhs and self._facts[i].op == op):
                kept.append(self._facts[i])
        self._facts = kept^

    def to_string(self) -> String:
        var out = String("")
        for i in range(len(self._facts)):
            if self._facts[i].ok:
                out += self._facts[i].to_string() + "\n"
        return out
