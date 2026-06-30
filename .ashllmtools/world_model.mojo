"""
ashllmtools.world_model — system state + beliefs + assumptions + dependencies.

The world model is the agent's current belief about the external environment.
It is rebuilt on session start and re-synced before every AUTO step.
A stale world model is flagged by the decision contract (step 6).
"""

from tools.git import git_branch_current, git_status, git_is_clean
from tools.fs  import file_exists, read_text
from tools.shell import shell_run


struct FileState(Copyable, ImplicitlyCopyable, Movable, ImplicitlyDeletable):
    """Observed state of a single file."""
    var path:     String
    var exists:   Bool
    var modified: Bool

    def __init__(out self, path: String, exists: Bool, modified: Bool = False):
        self.path     = path
        self.exists   = exists
        self.modified = modified


struct GitState(Copyable, ImplicitlyCopyable, Movable, ImplicitlyDeletable):
    """Current git repository state."""
    var branch:    String
    var is_clean:  Bool
    var status:    String   # raw `git status --short` output
    var remote:    String   # remote URL (empty if not found)

    def __init__(out self,
                 branch:   String,
                 is_clean: Bool,
                 status:   String,
                 remote:   String):
        self.branch   = branch
        self.is_clean = is_clean
        self.status   = status
        self.remote   = remote


struct Assumption(Copyable, ImplicitlyCopyable, Movable, ImplicitlyDeletable):
    """A belief that might become invalid. Tagged for staleness tracking."""
    var key:        String
    var value:      String
    var confidence: Int   # 0..100; degraded after each AUTO step without re-sync

    def __init__(out self, key: String, value: String, confidence: Int = 100):
        self.key        = key
        self.value      = value
        self.confidence = confidence


struct WorldModel(Movable):
    """
    Snapshot of the environment. Rebuilt by sync().
    Consumed by the decision contract's step-6 world-sync guard.
    """
    var git:         GitState
    var files:       List[FileState]
    var assumptions: List[Assumption]
    var sync_count:  Int

    def __init__(out self):
        self.git = GitState(
            branch   = String("(unknown)"),
            is_clean = False,
            status   = String(""),
            remote   = String(""),
        )
        self.files       = List[FileState]()
        self.assumptions = List[Assumption]()
        self.sync_count  = 0

    def __moveinit__(out self, owned other: Self):
        self.git         = other.git
        self.files       = other.files^
        self.assumptions = other.assumptions^
        self.sync_count  = other.sync_count

    def sync(mut self):
        """Re-read git + key file state from disk. Call before each AUTO step."""
        var branch   = git_branch_current()
        var status   = git_status()
        var clean    = git_is_clean()
        var remote_r = shell_run("git remote get-url origin 2>/dev/null")
        var remote   = remote_r.stdout if remote_r.ok else String("")
        self.git = GitState(
            branch   = branch,
            is_clean = clean,
            status   = status,
            remote   = remote,
        )
        self.sync_count += 1
        self._degrade_assumptions()

    def track_file(mut self, path: String):
        """Register a file for tracking. Updated on next sync()."""
        self.files.append(FileState(path=path, exists=file_exists(path)))

    def set_assumption(mut self, key: String, value: String):
        """Record a belief at full confidence."""
        for i in range(len(self.assumptions)):
            if self.assumptions[i].key == key:
                var updated = Assumption(key, value, 100)
                self.assumptions[i] = updated
                return
        self.assumptions.append(Assumption(key, value, 100))

    def get_assumption(self, key: String) -> String:
        """Return assumption value, or "" if not tracked."""
        for i in range(len(self.assumptions)):
            if self.assumptions[i].key == key:
                return self.assumptions[i].value
        return String("")

    def is_stale(self) -> Bool:
        """True if any assumption confidence has dropped below threshold."""
        for i in range(len(self.assumptions)):
            if self.assumptions[i].confidence < 50:
                return True
        return False

    def describe(self) -> String:
        return (
            "WorldModel(branch=" + self.git.branch
            + ", clean=" + String(self.git.is_clean)
            + ", syncs=" + String(self.sync_count) + ")"
        )

    def _degrade_assumptions(mut self):
        for i in range(len(self.assumptions)):
            var a = self.assumptions[i]
            if a.confidence > 0:
                var updated = Assumption(a.key, a.value, a.confidence - 10)
                self.assumptions[i] = updated
