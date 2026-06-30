"""
ashllmtools.rag — layer: knowledge retrieval (RAG pipeline).

Pipeline:
  retrieve → rank → compress → inject → generate → cite

Knowledge source priority (highest → lowest):
  0  current repo files (live, high trust)
  1  session memory (high trust)
  2  CHANGELOG / docs in repo (committed, high trust)
  3  fetched external docs (medium trust)
  4  web search results (low trust)
  5  model training data (cutoff, citation forbidden)

Freshness thresholds:
  repo files   → always fresh (age_seconds = -1)
  fetched docs → 3600 seconds (1 hour)
  web results  → 900 seconds  (15 minutes)
"""

from std.memory import UnsafePointer
from tools.fs    import read_text, file_exists
from tools.shell import shell_run
from context_engine import ContextChunk, AUTH_REPO, AUTH_FETCHED, AUTH_WEB
from context_engine import PRI_HIGH, PRI_MEDIUM, PRI_LOW


# ── Freshness thresholds ──────────────────────────────────────────────────────

alias FRESH_REPO    = -1    # always fresh
alias FRESH_FETCHED = 3600  # seconds
alias FRESH_WEB     = 900   # seconds


# ── Document ──────────────────────────────────────────────────────────────────

struct Document(Copyable, ImplicitlyCopyable, Movable, ImplicitlyDeletable):
    """
    A retrieved knowledge artifact.
    age_seconds == -1 for repo files (always fresh).
    """
    var content:     String
    var source:      String
    var authority:   Int      # AUTH_* constant
    var age_seconds: Int      # -1 = always fresh

    def __init__(out self,
                 content:     String,
                 source:      String,
                 authority:   Int = AUTH_FETCHED,
                 age_seconds: Int = 0):
        self.content     = content
        self.source      = source
        self.authority   = authority
        self.age_seconds = age_seconds

    def is_fresh(self) -> Bool:
        """True iff the document is within its freshness window."""
        if self.age_seconds < 0:
            return True  # always fresh (repo file)
        if self.authority == AUTH_REPO:
            return True
        if self.authority == AUTH_FETCHED:
            return self.age_seconds <= FRESH_FETCHED
        if self.authority == AUTH_WEB:
            return self.age_seconds <= FRESH_WEB
        return True

    def to_chunk(self, priority: Int = PRI_MEDIUM) -> ContextChunk:
        return ContextChunk(
            content   = self.content,
            source    = self.source,
            authority = self.authority,
            priority  = priority,
        )


# ── Retrieval strategies ──────────────────────────────────────────────────────

def retrieve_file(path: String) -> Document:
    """Read a repo file as a Document (always fresh)."""
    return Document(
        content     = read_text(path),
        source      = path,
        authority   = AUTH_REPO,
        age_seconds = FRESH_REPO,
    )


def grep_repo(pattern: String, path: String = ".") -> Document:
    """Keyword search in repo via grep. Returns matching lines."""
    var r = shell_run(
        "grep -rn --include='*.mojo' " + pattern + " " + path + " 2>/dev/null"
    )
    return Document(
        content     = r.stdout if r.ok else String(""),
        source      = "grep:" + pattern,
        authority   = AUTH_REPO,
        age_seconds = FRESH_REPO,
    )


# ── RAG Pipeline ──────────────────────────────────────────────────────────────

struct RAGPipeline(Movable):
    """
    Stateless retrieval pipeline. Collect → filter stale → rank → return chunks.

    Usage:
        var rag = RAGPipeline()
        rag.add(retrieve_file("CHANGELOG.md"))
        rag.add(grep_repo("parse_float"))
        var chunks = rag.build(top_k=5)
    """
    var _docs:      List[Document]
    var _max_bytes: Int   # per-document soft limit before truncation

    def __init__(out self, max_bytes: Int = 4096):
        self._docs      = List[Document]()
        self._max_bytes = max_bytes

    def __moveinit__(out self, owned other: Self):
        self._docs      = other._docs^
        self._max_bytes = other._max_bytes

    def add(mut self, doc: Document):
        self._docs.append(doc)

    def clear(mut self):
        self._docs = List[Document]()

    def _filter_stale(self) -> List[Document]:
        var fresh = List[Document]()
        for i in range(len(self._docs)):
            if self._docs[i].is_fresh():
                fresh.append(self._docs[i])
        return fresh

    def _rank(self, docs: List[Document]) -> List[Document]:
        """Insertion sort by authority ascending (lower = more trusted)."""
        var sorted = docs
        var n = len(sorted)
        for i in range(1, n):
            var key = sorted[i]
            var j   = i - 1
            while j >= 0 and sorted[j].authority > key.authority:
                sorted[j + 1] = sorted[j]
                j -= 1
            sorted[j + 1] = key
        return sorted

    def _compress(self, doc: Document) -> Document:
        """Truncate documents exceeding max_bytes with a notice."""
        var bl = doc.content.byte_length()
        if bl <= self._max_bytes:
            return doc
        var ptr     = doc.content.unsafe_ptr()
        var truncated = String(StringSlice(ptr=ptr, length=self._max_bytes))
        var msg = "\n[...truncated at " + String(self._max_bytes) + " bytes]"
        return Document(
            content     = truncated + msg,
            source      = doc.source,
            authority   = doc.authority,
            age_seconds = doc.age_seconds,
        )

    def build(mut self, top_k: Int = 10) -> List[ContextChunk]:
        """Return up to top_k fresh, ranked, compressed chunks."""
        var fresh  = self._filter_stale()
        var ranked = self._rank(fresh)

        var result = List[ContextChunk]()
        var limit  = top_k if top_k < len(ranked) else len(ranked)
        for i in range(limit):
            var compressed = self._compress(ranked[i])
            result.append(compressed.to_chunk())
        return result

    def size(self) -> Int:
        return len(self._docs)
