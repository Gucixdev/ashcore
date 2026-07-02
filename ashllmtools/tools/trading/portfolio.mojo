"""tools.trading.portfolio — position tracking and P&L analysis.

Line parsing uses ashparser via tools.trading.parser.parse_portfolio_line,
replacing hand-rolled token extraction with combinator-based parsing.
"""

from tools.trading.indicators import _f2s
from tools.trading.parser     import parse_portfolio_line


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
        return t^

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
        return out^

    def describe(self) -> String:
        var n   = len(self.positions)
        var inv = self.total_invested()
        var out = ("positions=" + String(n)
                   + " invested=" + _f2s(inv)
                   + " cash=" + _f2s(self.cash)
                   + " total=" + _f2s(self.total_value()) + "\n")
        for i in range(n):
            out += self.positions[i].describe() + "\n"
        return out^


# ── Parser + summary ──────────────────────────────────────────────────────────

def parse_portfolio(text: String) -> Portfolio:
    """Parse a portfolio from text using ashparser.

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
        # Slice one line
        var j = i
        while j < n and ptr[j] != 10: j += 1
        var line = String(text[byte=i:j])
        i = j + 1
        # Skip blank lines and comments
        var lp = line.unsafe_ptr(); var ll = line.byte_length(); var s = 0
        while s < ll and (lp[s] == 32 or lp[s] == 9): s += 1
        if s >= ll or lp[s] == 35: continue   # empty or '#'
        # ashparser-based line parse
        var pl = parse_portfolio_line(line)
        if not pl.ok: continue
        if pl.symbol == "cash":
            pf.cash = pl.qty
        else:
            pf.add(Position(pl.symbol, pl.qty, pl.cost_basis))
    return pf^


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
    return out^
