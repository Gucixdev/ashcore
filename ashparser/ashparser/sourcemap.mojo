"""
ashparser — SourceMap and LineCol

Separate from Input: build once per buffer (O(n)), then resolve any number
of byte offsets to 1-based (line, col) pairs in O(log n) via binary search.
"""
from ashparser.input import Input


struct SourceMap(Movable, ImplicitlyDeletable):
    """
    Precomputed line-start byte offsets for a byte buffer.

    Example:
        var sm  = SourceMap(inp)
        var lc  = sm.line_col(err_pos)
        print(String(lc.line) + ":" + String(lc.col))
    """
    var _offsets: List[Int]   # _offsets[i] = byte start of line i+1

    def __init__(out self, inp: Input):
        """Scan `inp` once and record the start position of every line."""
        self._offsets = List[Int]()
        self._offsets.append(0)   # line 1 always starts at byte 0
        var ptr = inp._ptr()
        for i in range(inp.len):
            if ptr[i] == 10:   # '\n'
                self._offsets.append(i + 1)

    def line_col(self, pos: Int) -> LineCol:
        """Return 1-based (line, col) for byte offset `pos`.  O(log n).
        Negative pos is clamped to 0 (→ line 1, col 1)."""
        var pos = pos if pos >= 0 else 0
        var lo = 0
        var hi = len(self._offsets) - 1
        while lo < hi:
            var mid = (lo + hi + 1) >> 1
            if self._offsets[mid] <= pos:
                lo = mid
            else:
                hi = mid - 1
        return LineCol(lo + 1, pos - self._offsets[lo] + 1)


struct LineCol(Copyable, ImplicitlyCopyable, Movable, ImplicitlyDeletable):
    """1-based line and column numbers."""
    var line: Int
    var col:  Int

    def __init__(out self, line: Int, col: Int):
        self.line = line
        self.col  = col

    def __str__(self) -> String:
        return String(self.line) + ":" + String(self.col)
