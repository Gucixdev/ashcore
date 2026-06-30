"""tools.trading.parser — ashparser-based parsing utilities for trading data.

Centralises all text → value conversions for the trading layer so that
individual modules (indicators, portfolio, signals) do not need to carry
hand-rolled byte-scanning routines.

Public API:
  parse_floats_csv(csv)          → List[Float64]  (comma-separated prices)
  parse_portfolio_line(line)     → PortfolioLine  (symbol qty cost_basis)
"""

from ashparser.input import Input
from ashparser.prim  import parse_float, byte, take_while1, ws, line_ending
from ashparser.comb  import opt, sep_by
from ashparser.p     import P


# ── Aliases for common parsers ────────────────────────────────────────────────

alias _PFloat = P[Float64, parse_float]
alias _PComma = P[UInt8,   byte[UInt8(44)]]   # ','


# ── CSV float parsing ─────────────────────────────────────────────────────────

def parse_floats_csv(csv: String) -> List[Float64]:
    """Parse comma-separated floats via ashparser.

    Uses ashparser's battle-tested parse_float (handles leading +/., exponent
    capping, overflow detection) and sep_by for zero-allocation splitting.
    Returns empty list on any parse error.
    """
    var r = _PFloat().p_sep_by(_PComma()).parse(csv)
    return r.get() if r.ok else List[Float64]()


# ── Portfolio line parsing ────────────────────────────────────────────────────

struct PortfolioLine(Copyable, ImplicitlyCopyable, Movable, ImplicitlyDeletable):
    """Result of parsing one portfolio text line."""
    var ok:         Bool
    var symbol:     String
    var qty:        Float64
    var cost_basis: Float64  # 0 when absent (e.g. cash line)

    def __init__(out self, ok: Bool, symbol: String,
                 qty: Float64, cost_basis: Float64):
        self.ok         = ok
        self.symbol     = symbol
        self.qty        = qty
        self.cost_basis = cost_basis

    @staticmethod
    def bad() -> PortfolioLine:
        return PortfolioLine(ok=False, symbol="", qty=0, cost_basis=0)


@parameter
def _is_sym(b: UInt8) -> Bool:
    """ASCII alphanumeric, '-', or '_' — valid symbol/word characters."""
    return ((b >= 65 and b <= 90) or (b >= 97 and b <= 122)
            or (b >= 48 and b <= 57) or b == 45 or b == 95)

@parameter
def _is_space(b: UInt8) -> Bool:
    return b == 32 or b == 9

alias _PSym = P[String, take_while1[_is_sym]]
alias _PWS  = P[String, take_while1[_is_space]]
alias _PFlt = P[Float64, parse_float]


def parse_portfolio_line(line: String) -> PortfolioLine:
    """Parse a portfolio text line using ashparser.

    Accepted formats:
      AAPL 100 150.50    → symbol=AAPL qty=100 cost_basis=150.50
      cash 5000          → symbol=cash qty=5000 cost_basis=0
      (blank / garbage)  → ok=False
    """
    var inp = Input.from_string(line)
    # symbol
    var r_sym = _PSym()(inp)
    if not r_sym.ok: return PortfolioLine.bad()
    # mandatory whitespace
    var r_ws1 = _PWS()(r_sym.rest)
    if not r_ws1.ok: return PortfolioLine.bad()
    # first number (qty or cash amount)
    var r_qty = _PFlt()(r_ws1.rest)
    if not r_qty.ok: return PortfolioLine.bad()
    var symbol = r_sym.get()
    var qty    = r_qty.get()
    # optional: whitespace + cost_basis
    var r_ws2 = _PWS()(r_qty.rest)
    if not r_ws2.ok:
        return PortfolioLine(ok=True, symbol=symbol, qty=qty, cost_basis=Float64(0))
    var r_cost = _PFlt()(r_ws2.rest)
    if not r_cost.ok:
        return PortfolioLine(ok=True, symbol=symbol, qty=qty, cost_basis=Float64(0))
    return PortfolioLine(ok=True, symbol=symbol, qty=qty, cost_basis=r_cost.get())
