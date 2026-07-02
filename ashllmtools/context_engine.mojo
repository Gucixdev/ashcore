"""
ashllmtools.context_engine — layer 5: context budget management.
Imports DSLStore from dsl for the add_facts() bridge.

Responsibilities:
  rank()      — score chunks by relevance + recency + authority
  compress()  — summarize or truncate to fit budget
  dedup()     — remove duplicate content
  build()     — assemble final prompt context within token budget

Budget allocation (default 20k token budget):
  CRITICAL chunks     — always included, bypass budget cap
  remaining budget    — filled in rank order (authority asc, priority asc)
"""

from dsl import DSLStore

# ── Priority constants ────────────────────────────────────────────────────────

alias PRI_CRITICAL = 0   # always included (task goal, hard constraints)
alias PRI_HIGH     = 1   # current tool output / last user turn
alias PRI_MEDIUM   = 2   # recent history / retrieved docs
alias PRI_LOW      = 3   # old history / low-authority sources


# ── Source authority constants ────────────────────────────────────────────────

alias AUTH_REPO    = 0   # current repo files — highest trust
alias AUTH_SESSION = 1   # session memory
alias AUTH_FETCHED = 2   # externally fetched docs
alias AUTH_WEB     = 3   # web search results — lowest trust


# ── ContextChunk ──────────────────────────────────────────────────────────────

struct ContextChunk(Copyable, ImplicitlyCopyable, Movable, ImplicitlyDeletable):
    """
    A single unit of context to be injected into the prompt.
    Tokens estimated as byte_length // 4 (rough approximation).
    """
    var content:   String
    var source:    String   # file path, URL, or description
    var authority: Int      # AUTH_* constant
    var priority:  Int      # PRI_* constant
    var tokens:    Int      # estimated token count

    def __init__(out self,
                 content:   String,
                 source:    String,
                 authority: Int = AUTH_SESSION,
                 priority:  Int = PRI_MEDIUM):
        self.content   = content
        self.source    = source
        self.authority = authority
        self.priority  = priority
        self.tokens    = content.byte_length() // 4 + 1


def _chunk_score(c: ContextChunk) -> Int:
    """Lower score = higher priority. authority * 10 + priority."""
    return c.authority * 10 + c.priority


# ── ContextEngine ─────────────────────────────────────────────────────────────

struct ContextEngine(Movable):
    """
    Assembles final prompt context from a pool of chunks within a token budget.

    Usage:
        var engine = ContextEngine(budget=20000)
        engine.add(ContextChunk(content, source, AUTH_REPO, PRI_HIGH))
        var ctx = engine.build()     # sorted, deduped, budget-capped string
    """
    var _chunks: List[ContextChunk]
    var budget:  Int

    def __init__(out self, budget: Int = 20000):
        self._chunks = List[ContextChunk]()
        self.budget  = budget

    def __moveinit__(out self, owned other: Self):
        self._chunks = other._chunks^
        self.budget  = other.budget

    def add(mut self, chunk: ContextChunk):
        self._chunks.append(chunk)

    def add_facts(mut self, store: DSLStore,
                  priority: Int = PRI_MEDIUM,
                  source: String = "world_model:facts"):
        """Convert a DSLStore into a single ContextChunk and add it."""
        var text = store.to_string()
        if text.byte_length() > 0:
            self.add(ContextChunk(text, source, AUTH_SESSION, priority))

    def clear(mut self):
        self._chunks = List[ContextChunk]()

    def total_tokens(self) -> Int:
        var t = 0
        for i in range(len(self._chunks)):
            t += self._chunks[i].tokens
        return t

    def rank(mut self):
        """Sort chunks: CRITICAL first, then by (authority asc, priority asc)."""
        var n = len(self._chunks)
        for i in range(1, n):
            var key = self._chunks[i]
            var j   = i - 1
            # CRITICAL always sorts first (score -1 conceptually)
            var key_score = -1 if key.priority == PRI_CRITICAL else _chunk_score(key)
            while j >= 0:
                var cur_score = -1 if self._chunks[j].priority == PRI_CRITICAL else _chunk_score(self._chunks[j])
                if cur_score <= key_score:
                    break
                self._chunks[j + 1] = self._chunks[j]
                j -= 1
            self._chunks[j + 1] = key

    def dedup(mut self):
        """Remove exact-duplicate content strings."""
        var i = 0
        while i < len(self._chunks):
            var j = i + 1
            while j < len(self._chunks):
                if self._chunks[j].content == self._chunks[i].content:
                    _ = self._chunks.pop(j)
                else:
                    j += 1
            i += 1

    def build(mut self) -> String:
        """
        Return the assembled context string within the token budget.
        Applies rank() then dedup() then budget cutoff.
        CRITICAL chunks always appear regardless of budget.
        """
        self.rank()
        self.dedup()

        var out  = String("")
        var used = 0
        for i in range(len(self._chunks)):
            var c = self._chunks[i]
            var block = "\n---\n[" + c.source + "]\n" + c.content
            if c.priority == PRI_CRITICAL:
                out = out + block
            elif used + c.tokens <= self.budget:
                out  = out + block
                used += c.tokens
        return out^

    def describe(self) -> String:
        return (
            "ContextEngine(chunks=" + String(len(self._chunks))
            + ", tokens=" + String(self.total_tokens())
            + "/" + String(self.budget) + ")"
        )
