"""
ashllmtools.memory — four memory tiers.

  NoteMemory      (layer 4a) — key→value scratch pad; survives turns
  EpisodicMemory  (layer 4b) — ordered list of events with turn index
  SemanticMemory  (layer 4c) — chunks with tags for similarity retrieval
  LongTermMemory  (layer 4d) — composite; persists across sessions via disk
"""


# ── NoteMemory ────────────────────────────────────────────────────────────────

struct Note(Copyable, ImplicitlyCopyable, Movable, ImplicitlyDeletable):
    var key:   String
    var value: String

    def __init__(out self, key: String, value: String):
        self.key   = key
        self.value = value


struct NoteMemory(Movable):
    """Key-value scratchpad. O(n) lookup; suitable for small note sets."""
    var _notes: List[Note]

    def __init__(out self):
        self._notes = List[Note]()

    def __moveinit__(out self, owned other: Self):
        self._notes = other._notes^

    def set(mut self, key: String, value: String):
        for i in range(len(self._notes)):
            if self._notes[i].key == key:
                self._notes[i] = Note(key, value)
                return
        self._notes.append(Note(key, value))

    def get(self, key: String) -> String:
        for i in range(len(self._notes)):
            if self._notes[i].key == key:
                return self._notes[i].value
        return String("")

    def delete(mut self, key: String):
        var i = 0
        while i < len(self._notes):
            if self._notes[i].key == key:
                _ = self._notes.pop(i)
                return
            i += 1

    def keys(self) -> List[String]:
        var result = List[String]()
        for i in range(len(self._notes)):
            result.append(self._notes[i].key)
        return result^

    def size(self) -> Int:
        return len(self._notes)


# ── EpisodicMemory ────────────────────────────────────────────────────────────

struct Episode(Copyable, ImplicitlyCopyable, Movable, ImplicitlyDeletable):
    var turn:    Int
    var kind:    String   # "user" | "tool" | "result" | "error"
    var content: String

    def __init__(out self, turn: Int, kind: String, content: String):
        self.turn    = turn
        self.kind    = kind
        self.content = content


struct EpisodicMemory(Movable):
    """Ordered log of agent turns + tool calls. Used for context compression."""
    var _episodes: List[Episode]
    var _turn:     Int

    def __init__(out self):
        self._episodes = List[Episode]()
        self._turn     = 0

    def __moveinit__(out self, owned other: Self):
        self._episodes = other._episodes^
        self._turn     = other._turn

    def record(mut self, kind: String, content: String):
        self._episodes.append(Episode(self._turn, kind, content))

    def next_turn(mut self):
        self._turn += 1

    def last_n(self, n: Int) -> List[Episode]:
        var result = List[Episode]()
        var start  = len(self._episodes) - n
        if start < 0:
            start = 0
        for i in range(start, len(self._episodes)):
            result.append(self._episodes[i])
        return result

    def since_turn(self, t: Int) -> List[Episode]:
        var result = List[Episode]()
        for i in range(len(self._episodes)):
            if self._episodes[i].turn >= t:
                result.append(self._episodes[i])
        return result

    def size(self) -> Int:
        return len(self._episodes)


# ── SemanticMemory ────────────────────────────────────────────────────────────

struct SemanticChunk(Copyable, ImplicitlyCopyable, Movable, ImplicitlyDeletable):
    var content: String
    var tags:    List[String]   # keyword tags for retrieval

    def __init__(out self, content: String, tags: List[String]):
        self.content = content
        self.tags    = tags


struct SemanticMemory(Movable):
    """
    Keyword-tagged chunk store.
    Retrieval: return all chunks that share at least one tag with the query tags.
    For vector similarity: this is the hook point — replace _match with cosine sim.
    """
    var _chunks: List[SemanticChunk]

    def __init__(out self):
        self._chunks = List[SemanticChunk]()

    def __moveinit__(out self, owned other: Self):
        self._chunks = other._chunks^

    def store(mut self, content: String, tags: List[String]):
        self._chunks.append(SemanticChunk(content, tags))

    def retrieve(self, query_tags: List[String], top_k: Int) -> List[SemanticChunk]:
        var scored = List[Int]()  # indices of matching chunks (score = tag overlap)
        for i in range(len(self._chunks)):
            var score = 0
            for qi in range(len(query_tags)):
                for ci in range(len(self._chunks[i].tags)):
                    if self._chunks[i].tags[ci] == query_tags[qi]:
                        score += 1
            if score > 0:
                scored.append(i)
        # Return first top_k matches (no re-ranking; add score sort here for production)
        var result = List[SemanticChunk]()
        var limit  = top_k if top_k < len(scored) else len(scored)
        for i in range(limit):
            result.append(self._chunks[scored[i]])
        return result

    def size(self) -> Int:
        return len(self._chunks)


# ── LongTermMemory ────────────────────────────────────────────────────────────

struct LongTermMemory(Movable):
    """
    Composite long-term store.
    On-disk persistence is via write_text/read_text (see tools/fs.mojo).
    Call save(path) to persist and load(path) to restore across sessions.
    Format: simple key=value lines for NoteMemory; episodes as turn|kind|content lines.
    """
    var notes:   NoteMemory
    var episodes: EpisodicMemory
    var semantic: SemanticMemory

    def __init__(out self):
        self.notes    = NoteMemory()
        self.episodes = EpisodicMemory()
        self.semantic = SemanticMemory()

    def __moveinit__(out self, owned other: Self):
        self.notes    = other.notes^
        self.episodes = other.episodes^
        self.semantic = other.semantic^

    def serialize_notes(self) -> String:
        """Serialize NoteMemory to key=value lines."""
        var out = String("")
        var keys = self.notes.keys()
        for i in range(len(keys)):
            var k = keys[i]
            var v = self.notes.get(k)
            out = out + k + "=" + v + "\n"
        return out

    def describe(self) -> String:
        return (
            "LongTermMemory(notes=" + String(self.notes.size())
            + ", episodes=" + String(self.episodes.size())
            + ", semantic=" + String(self.semantic.size()) + ")"
        )
