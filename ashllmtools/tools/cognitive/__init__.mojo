"""tools.cognitive — cognitive-category skills: plan, reason, decide, etc.

To add a new cognitive skill:
  1. Create skills/cognitive/<name>.md with name/category frontmatter
  2. Write _skill_<name>() below
  3. Add one line in dispatch()
"""

from decision_contract import _contains
from skill_types import SkillResult


def _skill_reflect(inp: String) -> SkillResult:
    if inp == "": return SkillResult.failure("reflect: no input to evaluate")
    var verdict = "ok"
    if _contains(inp, "ERROR") or _contains(inp, "FAIL") or _contains(inp, "failed"):
        verdict = "incorrect"
    return SkillResult.success(
        "verdict=" + verdict + "\ninput_length=" + String(inp.byte_length())
    )

def _skill_analyze(inp: String) -> SkillResult:
    if inp == "": return SkillResult.failure("analyze: no input")
    var lines = 0
    for i in range(inp.byte_length()):
        if inp.unsafe_ptr()[i] == UInt8(10): lines += 1
    return SkillResult.success(
        "lines=" + String(lines) + " bytes=" + String(inp.byte_length())
    )

def _skill_plan(inp: String) -> SkillResult:
    if inp == "": return SkillResult.failure("plan: no input")
    var out = String("steps:\n"); var step = 1
    var n = inp.byte_length(); var ptr = inp.unsafe_ptr(); var ls = 0
    for i in range(n):
        if ptr[i] == 10:
            if i > ls: out += String(step) + ". " + String(inp[byte=ls:i]) + "\n"; step += 1
            ls = i + 1
    if ls < n: out += String(step) + ". " + String(inp[byte=ls:n]) + "\n"; step += 1
    if step == 1: out += "1. " + inp + "\n"
    return SkillResult.success(out)

def _skill_reason(inp: String) -> SkillResult:
    if inp == "": return SkillResult.failure("reason: no input")
    var n = inp.byte_length(); var ptr = inp.unsafe_ptr(); var sentences = 0
    for i in range(n):
        var b = ptr[i]
        if b == 46 or b == 63 or b == 33: sentences += 1
    var flags = String("")
    if _contains(inp, "because"):                              flags += " causal"
    if _contains(inp, "therefore") or _contains(inp, "thus"): flags += " deductive"
    if _contains(inp, "if ") or _contains(inp, "when "):      flags += " conditional"
    if _contains(inp, "but ") or _contains(inp, "however"):   flags += " contrastive"
    if flags == "": flags = " declarative"
    var cap = 80 if n > 80 else n
    return SkillResult.success(
        "sentences=" + String(sentences) + " bytes=" + String(n)
        + " reasoning_type=" + flags
        + "\nanalysis: " + inp[:cap] + ("..." if n > 80 else "")
    )

def _skill_decide(inp: String) -> SkillResult:
    if inp == "": return SkillResult.failure("decide: no input")
    var risky = (_contains(inp, "delete") or _contains(inp, "force")
                 or _contains(inp, "drop") or _contains(inp, "rm "))
    var n = inp.byte_length(); var ptr = inp.unsafe_ptr(); var end = n
    for i in range(n):
        if ptr[i] == 10: end = i; break
    var verdict = "proceed" if not risky else "review_first"
    var out = "decision: " + inp[:end] + "\nverdict=" + verdict
    if risky: out += "\nwarning: destructive keywords detected"
    return SkillResult.success(out)

def _skill_schedule(inp: String) -> SkillResult:
    if inp == "": return SkillResult.failure("schedule: no input")
    var n = inp.byte_length(); var ptr = inp.unsafe_ptr()
    var early = List[String](); var late = List[String](); var rest = List[String]()
    var ls = 0
    for i in range(n + 1):
        if i == n or ptr[i] == 10:
            if i > ls:
                var l = String(inp[byte=ls:i])
                if _contains(l, "first") or _contains(l, "start") or _contains(l, "init"):
                    early.append(l)
                elif _contains(l, "after") or _contains(l, "depends") or _contains(l, "then"):
                    late.append(l)
                else:
                    rest.append(l)
            ls = i + 1
    var out = String("schedule:\n"); var step = 1
    for i in range(len(early)): out += String(step) + ". " + early[i] + "\n"; step += 1
    for i in range(len(rest)):  out += String(step) + ". " + rest[i]  + "\n"; step += 1
    for i in range(len(late)):  out += String(step) + ". " + late[i]  + "\n"; step += 1
    return SkillResult.success(out)

def _skill_evaluate(inp: String) -> SkillResult:
    if inp == "": return SkillResult.failure("evaluate: no input")
    var contradictions = String("")
    if _contains(inp, "always") and _contains(inp, "never"): contradictions += " always/never"
    if _contains(inp, "all") and _contains(inp, "none"):     contradictions += " all/none"
    var hedged = _contains(inp, "may") or _contains(inp, "might") or _contains(inp, "could")
    var out = "claim_length=" + String(inp.byte_length())
    out += "\nhedged=" + String(hedged)
    if contradictions != "": out += "\ncontradictions:" + contradictions
    out += "\nverdict=" + ("uncertain" if hedged else "stated")
    return SkillResult.success(out)

def dispatch(name: String, inp: String) -> SkillResult:
    if name == "reflect":  return _skill_reflect(inp)
    if name == "analyze":  return _skill_analyze(inp)
    if name == "plan":     return _skill_plan(inp)
    if name == "reason":   return _skill_reason(inp)
    if name == "decide":   return _skill_decide(inp)
    if name == "schedule": return _skill_schedule(inp)
    if name == "evaluate": return _skill_evaluate(inp)
    return SkillResult.failure("unknown cognitive skill: " + name)
