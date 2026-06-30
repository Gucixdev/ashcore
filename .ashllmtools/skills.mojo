"""
ashllmtools.skills — layer 2: named, composable capabilities.

Skills compose tools into results. Skills do NOT call other skills.
The decision contract gates every skill before its tools fire.

Cognitive skills:
  plan, analyze, reason, reflect, evaluate, decide, decompose, schedule

Code skills:
  refactor, review, bughunt, stresstest, exec_tests, search_symbol

Each skill is registered in SkillRegistry by name and description.
Dispatch: registry.run(name, input) → SkillResult.
"""

from tools.shell import shell_run
from tools.git   import git_status, git_diff_staged
from tools.fs    import read_text, file_exists
from decision_contract import _contains


# ── SkillResult ───────────────────────────────────────────────────────────────

struct SkillResult(Copyable, ImplicitlyCopyable, Movable, ImplicitlyDeletable):
    var ok:     Bool
    var output: String
    var reason: String   # why the skill failed (empty on success)

    def __init__(out self, ok: Bool, output: String, reason: String = ""):
        self.ok     = ok
        self.output = output
        self.reason = reason

    @staticmethod
    def success(output: String) -> SkillResult:
        return SkillResult(True, output, "")

    @staticmethod
    def failure(reason: String) -> SkillResult:
        return SkillResult(False, "", reason)


# ── Skill descriptor ──────────────────────────────────────────────────────────

struct Skill(Copyable, ImplicitlyCopyable, Movable, ImplicitlyDeletable):
    """Metadata for a registered skill."""
    var name:     String
    var desc:     String
    var category: String   # "cognitive" | "code" | "sys" | "web"

    def __init__(out self, name: String, desc: String, category: String):
        self.name     = name
        self.desc     = desc
        self.category = category


# ── Built-in skill implementations ────────────────────────────────────────────

def skill_git_status(inp: String) -> SkillResult:
    """Report current git working tree status."""
    var s = git_status()
    if s == "":
        return SkillResult.success("working tree clean")
    return SkillResult.success(s)


def skill_git_diff(inp: String) -> SkillResult:
    """Show staged changes."""
    var d = git_diff_staged()
    if d == "":
        return SkillResult.success("no staged changes")
    return SkillResult.success(d)


def skill_read_file(inp: String) -> SkillResult:
    """Read file at path given in inp."""
    var path = inp
    if not file_exists(path):
        return SkillResult.failure("file not found: " + path)
    var content = read_text(path)
    return SkillResult.success(content)


def skill_run_tests(inp: String) -> SkillResult:
    """Run the test suite. inp = directory containing pixi.toml."""
    var dir = inp if inp != "" else String(".")
    var r = shell_run("cd " + dir + " && pixi run test 2>&1")
    if not r.ok:
        return SkillResult.failure("test runner failed to start")
    return SkillResult(True, r.stdout, "")


def skill_search_symbol(inp: String) -> SkillResult:
    """Grep for a symbol across .mojo files. inp = symbol name."""
    var r = shell_run("grep -rn --include='*.mojo' '\\b" + inp + "\\b' . 2>/dev/null")
    if not r.ok or r.stdout == "":
        return SkillResult.failure("symbol not found: " + inp)
    return SkillResult.success(r.stdout)


def skill_reflect(inp: String) -> SkillResult:
    """Reflection stub: tag the last result with evaluation metadata."""
    if inp == "":
        return SkillResult.failure("reflect: no input to evaluate")
    var verdict = "ok"
    if _contains(inp, "ERROR") or _contains(inp, "FAIL") or _contains(inp, "failed"):
        verdict = "incorrect"
    return SkillResult.success("verdict=" + verdict + "\ninput_length=" + String(inp.byte_length()))


def skill_analyze(inp: String) -> SkillResult:
    """Analyze the given content and return key observations (stub)."""
    if inp == "":
        return SkillResult.failure("analyze: no input")
    var lines = 0
    for i in range(inp.byte_length()):
        if inp.unsafe_ptr()[i] == UInt8(10):
            lines += 1
    return SkillResult.success(
        "lines=" + String(lines) + " bytes=" + String(inp.byte_length())
    )


# ── SkillRegistry ─────────────────────────────────────────────────────────────

struct SkillRegistry(Movable):
    """
    Named skill registry with dispatch.

    Built-in skills are registered at construction.
    Custom skills can be added via register().
    """
    var _skills: List[Skill]

    def __init__(out self):
        self._skills = List[Skill]()
        self._register_builtins()

    def __moveinit__(out self, owned other: Self):
        self._skills = other._skills^

    def register(mut self, name: String, desc: String, category: String):
        self._skills.append(Skill(name=name, desc=desc, category=category))

    def run(self, name: String, inp: String) -> SkillResult:
        """Dispatch to built-in or return failure if unknown."""
        if name == "git_status":   return skill_git_status(inp)
        if name == "git_diff":     return skill_git_diff(inp)
        if name == "read_file":    return skill_read_file(inp)
        if name == "run_tests":    return skill_run_tests(inp)
        if name == "search":       return skill_search_symbol(inp)
        if name == "reflect":      return skill_reflect(inp)
        if name == "analyze":      return skill_analyze(inp)
        return SkillResult.failure("unknown skill: " + name)

    def list(self) -> List[String]:
        var names = List[String]()
        for i in range(len(self._skills)):
            names.append(self._skills[i].name)
        return names

    def find(self, name: String) -> Bool:
        for i in range(len(self._skills)):
            if self._skills[i].name == name:
                return True
        return False

    def size(self) -> Int:
        return len(self._skills)

    def _register_builtins(mut self):
        self.register("git_status",  "show working tree status",       "sys")
        self.register("git_diff",    "show staged changes",            "sys")
        self.register("read_file",   "read file content",              "code")
        self.register("run_tests",   "run test suite",                 "code")
        self.register("search",      "search for symbol in codebase",  "code")
        self.register("reflect",     "evaluate last result",           "cognitive")
        self.register("analyze",     "analyze content for insights",   "cognitive")
        self.register("plan",        "decompose goal into task list",  "cognitive")
        self.register("reason",      "step-by-step reasoning",         "cognitive")
        self.register("decide",      "choose between options",         "cognitive")
        self.register("bughunt",     "locate root cause of a bug",     "code")
        self.register("stresstest",  "find edge cases in code",        "code")
        self.register("review",      "code review with verdict",       "code")
        self.register("refactor",    "targeted code improvement",      "code")
        self.register("schedule",    "sequence tasks by dependency",   "cognitive")
