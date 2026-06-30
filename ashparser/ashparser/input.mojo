"""
ashparser — Input

Zero-copy view into a byte buffer.  Advancing creates a new Input value;
the underlying buffer is never copied.  All parser functions take and return
Input by value (cheap: two words on the stack — address + position).
"""


struct Input(Copyable, ImplicitlyCopyable, Movable, ImplicitlyDeletable):
    """
    Immutable view into a contiguous byte buffer.

    pos  — absolute byte offset of the current read head.
    len  — total length of the original buffer (never changes).

    Example:
        var s   = String("hello world")
        var inp = Input.from_string(s)
        var b   = inp.peek()           # ord('h') = 104
        var inp2 = inp.advance(5)      # points at ' world'
    """
    var _addr: Int   # raw address of byte buffer — borrowed (caller ensures lifetime)
    var pos:   Int
    var len:   Int

    @staticmethod
    def from_string(s: String) -> Input:
        """Borrow a String's bytes.  `s` must outlive the Input."""
        return Input(Int(s.unsafe_ptr()), 0, s.byte_length())

    @staticmethod
    def from_bytes(ptr: UnsafePointer[UInt8, ImmutAnyOrigin], length: Int) -> Input:
        return Input(Int(ptr), 0, length)

    def __init__(out self, addr: Int, pos: Int, length: Int):
        self._addr = addr
        self.pos   = pos
        self.len   = length

    @always_inline
    def _ptr(self) -> UnsafePointer[UInt8, ImmutAnyOrigin]:
        return UnsafePointer[UInt8, ImmutAnyOrigin](unsafe_from_address=self._addr)

    # ── Navigation ────────────────────────────────────────────────────────────

    @always_inline
    def peek(self) -> UInt8:
        """Current byte, or 0 if at end."""
        if self.pos >= self.len:
            return 0
        return self._ptr()[self.pos]

    @always_inline
    def peek_at(self, offset: Int) -> UInt8:
        """Byte at pos+offset, or 0 if out of bounds."""
        var i = self.pos + offset
        if i < 0 or i >= self.len:
            return 0
        return self._ptr()[i]

    @always_inline
    def advance(self, n: Int) -> Input:
        """Return a new Input advanced by n bytes (clamped to end)."""
        var new_pos = self.pos + n
        if new_pos > self.len:
            new_pos = self.len
        return Input(self._addr, new_pos, self.len)

    @always_inline
    def at(self, pos: Int) -> Input:
        """Return Input with read head at absolute `pos`. Caller ensures bounds."""
        return Input(self._addr, pos, self.len)

    @always_inline
    def remaining(self) -> Int:
        return self.len - self.pos

    @always_inline
    def is_empty(self) -> Bool:
        return self.pos >= self.len

    # ── Slicing ───────────────────────────────────────────────────────────────

    def slice_str(self, start: Int, end: Int) -> String:
        """
        Copy bytes [start, end) (absolute offsets) into a new String.
        Use only for extracting token values — this allocates.
        """
        var n = end - start
        if n <= 0 or start < 0 or end > self.len:
            return String("")
        var base = UnsafePointer[UInt8, ImmutAnyOrigin](unsafe_from_address=self._addr + start)
        return String(StringSlice(ptr=base, length=n))

    def current_str(self, length: Int) -> String:
        """Copy `length` bytes starting at pos."""
        return self.slice_str(self.pos, self.pos + length)

    # ── Debug ─────────────────────────────────────────────────────────────────

    def dump(self) -> String:
        var rem = self.remaining()
        var preview_len = rem if rem < 20 else 20
        return (
            "Input(pos=" + String(self.pos)
            + "/" + String(self.len)
            + " next='" + self.current_str(preview_len)
            + ("'" if rem <= 20 else "'...)")
        )

