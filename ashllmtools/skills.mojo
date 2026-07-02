"""
ashllmtools.skills — thin skill registry with auto-discovery and category dispatch.

Skills are discovered at startup by scanning skills/ for .md files with YAML frontmatter:
  name: <skill_name>
  category: <category>

To add a new skill within an existing category:
  1. Create skills/<cat>/<name>.md with name/category frontmatter
  2. Add _skill_<name>() + dispatch branch in tools/<cat>/__init__.mojo

To add a brand new category:
  1. Create tools/<cat>/__init__.mojo with dispatch(name, inp) -> SkillResult
  2. Add one routing branch in run() below
"""

from tools.sys       import dispatch as _sys_dispatch
from tools.code      import dispatch as _code_dispatch
from tools.cognitive import dispatch as _cog_dispatch
from tools.trading   import dispatch as _trade_dispatch
from decision_contract import Action, evaluate
from skill_types import SkillResult, Skill
from tools.sys.shell import shell_run


# ── Auto-discovery ────────────────────────────────────────────────────────────

def _grep_key(path: String, key: String) -> String:
    """Extract value of 'key: value' from a file (first match, whitespace stripped)."""
    var r = shell_run("grep -m1 '^" + key + ": ' " + path + " 2>/dev/null")
    if not r.ok or r.stdout == "": return String("")
    var s = r.stdout
    var n = s.byte_length(); var ptr = s.unsafe_ptr()
    var skip = key.byte_length() + 2
    if skip >= n: return String("")
    var end = n
    while end > skip and (ptr[end-1] == 10 or ptr[end-1] == 13 or ptr[end-1] == 32):
        end -= 1
    return String(s[byte=skip:end])


def _scan_skills_folder(base: String) -> List[Skill]:
    """Walk base/ for *.md files, extract name/category from YAML frontmatter."""
    var skills = List[Skill]()
    var r = shell_run("find " + base + " -name '*.md' -type f | sort 2>/dev/null")
    if not r.ok or r.stdout == "": return skills^
    var listing = r.stdout
    var n = listing.byte_length(); var ptr = listing.unsafe_ptr(); var ls = 0
    for i in range(n + 1):
        if i == n or ptr[i] == 10:
            if i > ls:
                var path = String(listing[byte=ls:i])
                var name = _grep_key(path, "name")
                var cat  = _grep_key(path, "category")
                if name != "" and cat != "":
                    skills.append(Skill(name=name, desc="", category=cat))
            ls = i + 1
    return skills^


# ── SkillRegistry ─────────────────────────────────────────────────────────────

struct SkillRegistry(Movable):
    """
    Named skill registry with auto-discovery and category dispatch.

    Skills are loaded from the skills/ folder at construction time.
    Additional skills can be registered at runtime via register().
    """
    var _skills: List[Skill]

    def __init__(out self, skills_dir: String = "skills"):
        self._skills = _scan_skills_folder(skills_dir)

    def __moveinit__(out self, owned other: Self):
        self._skills = other._skills^

    def register(mut self, name: String, desc: String, category: String):
        """Manually register a skill (bypasses file discovery)."""
        self._skills.append(Skill(name=name, desc=desc, category=category))

    def run(self, name: String, inp: String) -> SkillResult:
        """Dispatch to the skill's category handler.
        Decision contract is the FIRST gate — no skill executes if blocked."""
        var action = Action(cmd=name + "(" + inp + ")", scope="skill")
        var guard  = evaluate(action)
        if guard.is_block():
            return SkillResult.failure("BLOCKED [contract]: " + guard.reason)
        var cat = self._category_of(name)
        if cat == "sys":       return _sys_dispatch(name, inp)
        if cat == "code":      return _code_dispatch(name, inp)
        if cat == "cognitive": return _cog_dispatch(name, inp)
        if cat == "trading":   return _trade_dispatch(name, inp)
        return SkillResult.failure("unknown skill: " + name)

    def list(self) -> List[String]:
        var names = List[String]()
        for i in range(len(self._skills)): names.append(self._skills[i].name)
        return names^

    def find(self, name: String) -> Bool:
        for i in range(len(self._skills)):
            if self._skills[i].name == name: return True
        return False

    def size(self) -> Int:
        return len(self._skills)

    def _category_of(self, name: String) -> String:
        for i in range(len(self._skills)):
            if self._skills[i].name == name: return self._skills[i].category
        return String("")
