"""tools.trading.portfolio — position tracking and P&L analysis."""

from tools.trading.indicators import _parse_float_str, _f2s


# ── Helpers ───────────────────────────────────────────────────────────────────

def _read_token(s: String, start: Int) -> String:
    """Return next whitespace-delimited token starting at or after `start`."""
    var n   = s.byte_length()
    var ptr = s.unsafe_ptr()
    var i   = start
    while i < n and (ptr[i] == 32 or ptr[i] == 9): i += 1
    var j = i
    while j < n and ptr[j] != 32 and ptr[j] != 9 and ptr[j] != 10: j += 1
    return s[i:j]


def _token_end(s: String, start: Int) -> Int:
    """Byte index immediately past the next token at or after `start`."""
    var n   = s.byte_length()
    var ptr = s.unsafe_ptr()
    var i   = start
    while i < n and (ptr[i] == 32 or ptr[i] == 9): i += 1
    while i < n and ptr[i] != 32 and ptr[i] != 9 and ptr[i] != 10: i += 1
    return i


# ── Position / Portfolio ──────────────────────────────────────────────────────

struct Position(Copyable, ImplicitlyCopyable, Movable, ImplicitlyDeletable):
    """A single holding: symbol, quantity, and per-unit cost basis."""
    var symbol:     String
    var qty:        Float64
    var cost_basis: Float64   # per unit (e.g. per share)

    def __init__(out self, symbol: String, qty: Float64, cost_basis: Float64):
        self.symbol     = symbol
        self.qty        = qty
        self.cost_basis = cost_basis

    def total_cost(self) -> Float64:
        return self.qty * self.cost_basis

    def describe(self) -> String:
        return (self.symbol
                + ": qty=" + _f2s(self.qty)
                + " cost=" + _f2s(self.cost_basis)
                + " total_cost=" + _f2s(self.total_cost()))


struct Portfolio(Movable):
    """Collection of positions with aggregate analytics."""
    var positions: List[Position]
    var cash:      Float64

    def __init__(out self):
        self.positions = List[Position]()
        self.cash      = Float64(0)

    def __moveinit__(out self, owned other: Self):
        self.positions = other.positions^
        self.cash      = other.cash

    def add(mut self, p: Position):
        self.positions.append(p)

    def total_invested(self) -> Float64:
        var t = Float64(0)
        for i in range(len(self.positions)):
            t += self.positions[i].total_cost()
        return t

    def total_value(self) -> Float64:
        return self.total_invested() + self.cash

    def to_dsl(self) -> String:
        """Serialize to DSL fact format."""
        var out = String("")
        for i in range(len(self.positions)):
            var p = self.positions[i]
            out += p.symbol + "_qty = " + _f2s(p.qty) + "\n"
            out += p.symbol + "_cost = " + _f2s(p.cost_basis) + "\n"
        if self.cash > Float64(0):
            out += "cash = " + _f2s(self.cash) + "\n"
        return out

    def describe(self) -> String:
        var n   = len(self.positions)
        var inv = self.total_invested()
        var out = ("positions=" + String(n)
                   + " invested=" + _f2s(inv)
                   + " cash=" + _f2s(self.cash)
                   + " total=" + _f2s(self.total_value()) + "\n")
        for i in range(n):
            out += self.positions[i].describe() + "\n"
        return out


# ── Parser + summary ──────────────────────────────────────────────────────────

def parse_portfolio(text: String) -> Portfolio:
    """Parse a portfolio from text.

    Format — one position per line:
        AAPL  100  150.50     # symbol qty cost_basis
        cash  5000            # cash balance (no cost_basis)

    Lines starting with '#' are skipped.
    """
    var pf  = Portfolio()
    var n   = text.byte_length()
    var ptr = text.unsafe_ptr()
    var i   = 0
    while i < n:
        # Find line end
        var j = i
        while j < n and ptr[j] != 10: j += 1
        var line = text[i:j]
        i = j + 1
        # Trim and skip comments / blank lines
        var lp = line.unsafe_ptr()
        var ll = line.byte_length()
        var s  = 0
        while s < ll and (lp[s] == 32 or lp[s] == 9): s += 1
        if s >= ll or lp[s] == 35:   # empty or '#'
            continue
        var sym = _read_token(line, 0)
        var p1  = _token_end(line, 0)
        var tok2 = _read_token(line, p1)
        if sym == "" or tok2 == "":
            continue
        var qty  = _parse_float_str(tok2)
        if sym == "cash":
            pf.cash = qty
            continue
        var p2    = _token_end(line, p1)
        var tok3  = _read_token(line, p2)
        var cost  = _parse_float_str(tok3) if tok3 != "" else Float64(0)
        pf.add(Position(sym, qty, cost))
    return pf


def portfolio_summary(text: String) -> String:
    """Parse and summarize a portfolio text. Returns multi-line report."""
    var pf = parse_portfolio(text)
    if len(pf.positions) == 0 and pf.cash == Float64(0):
        return "error: no positions parsed"
    # Allocation breakdown
    var inv  = pf.total_invested()
    var out  = pf.describe()
    if inv > Float64(0):
        out += "allocation:\n"
        for i in range(len(pf.positions)):
            var p    = pf.positions[i]
            var pct  = p.total_cost() / inv * Float64(100)
            out += "  " + p.symbol + ": " + _f2s(pct) + "%\n"
    return out
