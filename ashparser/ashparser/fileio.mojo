"""
ashparser — fileio

Two utilities for parsing files:

  read_file(path)          — read entire file into memory; works with all
                             existing combinators unchanged; limited by RAM
  StreamingInput(path)     — chunked reader; RAM usage = chunk_size (default 1 MB)
                             regardless of file size; yields one Input per line
                             or per chunk; existing combinators work unchanged

StreamingInput is a *producer* of Input values — the combinator layer is
never touched. The returned Input borrows StreamingInput's internal buffer and
is only valid until the next call to next_line() or next_chunk().
"""

from pathlib import Path
from std.ffi import external_call
from ashparser.input import Input


# ─── Whole-file convenience ──────────────────────────────────────────────────

def read_file(path: String) raises -> (String, Input):
    """
    Read the entire file at `path` into a String and return an Input view.

    The String must outlive the Input — store both together and let the
    String go out of scope only when you're done parsing:

        var (buf, inp) = read_file("data.csv")
        var result = many[csv_row](inp)

    For files that don't fit in RAM, use StreamingInput instead.
    """
    var content = Path(path).read_text()
    var inp     = Input.from_string(content)
    return (content^, inp)


# ─── Streaming chunked reader ─────────────────────────────────────────────────

struct StreamingInput(Movable, ImplicitlyDeletable):
    """
    Chunked file reader. Produces Input values for each line or chunk.
    All existing ashparser combinators work unchanged — no signatures modified.

    RAM usage is bounded by chunk_size (default 1 MB), not the file size.

    Usage — line-by-line (CSV, logs, config):
        var r = StreamingInput.from_file("data.csv")
        while r.has_more():
            var line = r.next_line()      # borrows internal buffer
            var parsed = csv_row(line)    # parse before next call
            if parsed.ok: process(parsed.get())

    Usage — chunk-by-chunk (for formats that don't split on lines):
        var r = StreamingInput.from_file("data.bin", chunk_size=4096)
        while r.has_more():
            var chunk = r.next_chunk()
            var n_consumed = parse_chunk(chunk)
            r.rewind(chunk.remaining() - n_consumed)  # unused tail → next chunk

    Lifetime contract: the Input returned by next_line() / next_chunk() shares
    the internal buffer. Call your parser immediately; do not store the Input
    across another next_line() / next_chunk() call.
    """
    var _fd:            Int32
    var _buf:           UnsafePointer[UInt8]
    var _chunk_size:    Int
    var _buf_pos:       Int    # current read cursor inside buffer
    var _buf_len:       Int    # number of valid bytes in buffer
    var _eof:           Bool
    var _read_error:    Bool   # True if a read() syscall returned an error
    var _last_truncated: Bool  # True if last next_line() was truncated at chunk_size
    var _owned:         Bool   # True when this instance owns fd + buf

    def __init__(out self, fd: Int32, buf: UnsafePointer[UInt8], chunk_size: Int):
        self._fd             = fd
        self._buf            = buf
        self._chunk_size     = chunk_size
        self._buf_pos        = 0
        self._buf_len        = 0
        self._eof            = False
        self._read_error     = False
        self._last_truncated = False
        self._owned          = True

    def __moveinit__(out self, owned other: Self):
        self._fd             = other._fd
        self._buf            = other._buf
        self._chunk_size     = other._chunk_size
        self._buf_pos        = other._buf_pos
        self._buf_len        = other._buf_len
        self._eof            = other._eof
        self._read_error     = other._read_error
        self._last_truncated = other._last_truncated
        self._owned          = other._owned
        other._owned         = False   # transfer ownership

    def __del__(owned self):
        if self._owned:
            _ = external_call["close", Int32](self._fd)
            self._buf.free()

    # ── Construction ─────────────────────────────────────────────────────────

    @staticmethod
    def from_file(path: String, chunk_size: Int = 1 << 20) raises -> StreamingInput:
        """
        Open `path` for streaming. chunk_size bytes are held in RAM at a time.
        Raises if the file cannot be opened or chunk_size is not positive.
        """
        if chunk_size <= 0:
            raise Error("StreamingInput: chunk_size must be > 0")
        # O_RDONLY=0 | O_CLOEXEC=0x80000 — prevents fd leaking into child processes.
        var fd = external_call["open", Int32](path.unsafe_ptr(), Int32(0x80000))
        if fd < 0:
            raise Error("StreamingInput: cannot open '" + path + "'")
        var buf = UnsafePointer[UInt8].alloc(chunk_size)
        var s   = StreamingInput(fd, buf, chunk_size)
        s._fill()
        return s^

    # ── State ────────────────────────────────────────────────────────────────

    def has_more(self) -> Bool:
        """True if there are unread bytes remaining."""
        return not self._eof or self._buf_pos < self._buf_len

    def has_error(self) -> Bool:
        """True if a read() syscall returned an error (errno set by OS)."""
        return self._read_error

    def last_line_truncated(self) -> Bool:
        """True if the most recent next_line() call returned a line that was
        truncated at chunk_size (the logical line was longer than the buffer).
        Call rewind() or increase chunk_size if this is a problem."""
        return self._last_truncated

    # ── Line-by-line API ─────────────────────────────────────────────────────

    def next_line(mut self) -> Input:
        """
        Return Input for the next newline-delimited record (newline excluded).
        Transparently loads the next chunk when the buffer is exhausted.
        The returned Input is valid only until the next call to next_line()
        or next_chunk().
        """
        while True:
            var start = self._buf_pos
            var i     = start
            while i < self._buf_len:
                if self._buf[i] == 10:   # '\n'
                    self._buf_pos        = i + 1
                    self._last_truncated = False
                    return Input(Int(self._buf) + start, 0, i - start)
                i += 1

            # No newline found in buffer.
            if self._eof:
                # Last line has no trailing newline — return whatever is left.
                self._buf_pos        = self._buf_len
                self._last_truncated = False
                return Input(Int(self._buf) + start, 0, self._buf_len - start)

            # Guard: line longer than chunk_size → return the full buffer as a
            # truncated line and signal via last_line_truncated().
            if start == 0 and self._buf_len == self._chunk_size:
                self._buf_pos        = self._buf_len
                self._last_truncated = True
                return Input(Int(self._buf), 0, self._chunk_size)

            # Shift unfinished line to front, then refill.
            self._buf_pos = start
            self._fill()

    # ── Chunk API ────────────────────────────────────────────────────────────

    def next_chunk(mut self) -> Input:
        """
        Return Input over the current buffer contents (~chunk_size bytes).
        Call rewind(n) before the next call if n bytes at the end of the
        chunk were not consumed (e.g. an incomplete last record).
        The returned Input is valid only until the next call.
        """
        if self._buf_pos >= self._buf_len and not self._eof:
            self._buf_pos = self._buf_len   # trigger full refill
            self._fill()
        var start  = self._buf_pos
        var length = self._buf_len - start
        self._buf_pos        = self._buf_len   # mark all consumed
        self._last_truncated = False
        return Input(Int(self._buf) + start, 0, length)

    def rewind(mut self, n: Int):
        """
        Mark the last `n` bytes as unconsumed — they will appear at the start
        of the next chunk. Use with next_chunk() to handle split records.
        Negative n is a no-op (no bytes are "un-consumed").
        """
        if n <= 0:
            return
        var new_pos = self._buf_pos - n
        self._buf_pos = new_pos if new_pos >= 0 else 0

    # ── Internal ─────────────────────────────────────────────────────────────

    def _fill(mut self):
        """
        Shift bytes [buf_pos, buf_len) to the front of the buffer with memmove,
        then read up to (chunk_size - leftover) new bytes from the file.
        """
        var leftover = self._buf_len - self._buf_pos
        if leftover > 0 and self._buf_pos > 0:
            # memmove handles the overlapping-region case correctly.
            _ = external_call["memmove", UnsafePointer[UInt8]](
                self._buf, self._buf.offset(self._buf_pos), leftover
            )

        var to_read = self._chunk_size - leftover
        var n = external_call["read", Int](
            self._fd, self._buf.offset(leftover), to_read
        )
        if n < 0:
            # OS-level read error — mark EOF and record the error.
            self._eof        = True
            self._read_error = True
            self._buf_len    = leftover
        elif n == 0:
            self._eof     = True
            self._buf_len = leftover
        else:
            self._buf_len = leftover + n
            if n < to_read:
                self._eof = True   # short read — file exhausted
        self._buf_pos = 0
