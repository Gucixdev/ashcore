# Skills

Composable capabilities that assemble lazytools into a result.
A skill takes an input, runs a sequence of tools, and returns a structured output.
Skills do not call other skills (that's a workflow).

---

## Skill Anatomy

```
name:       <skill-name>
input:      what the skill receives
steps:      ordered list of lazytool calls
output:     what the skill returns
contract:   which guards apply (from decision_contract/guards.md)
```

---

## Cognitive Skills (no tool I/O)

### `reason`
Decompose a problem into first principles. No tools. Pure synthesis.  
Input: question or situation  
Output: structured reasoning chain → conclusion

### `analyze`
Examine a piece of code, output, or situation for properties.  
Input: artifact  
Output: findings with severity (observation / concern / flaw / bloat)

### `evaluate`
Score options against criteria.  
Input: options list + criteria  
Output: ranked options with rationale per criterion

### `decide`
Commit to one option given analysis and constraints.  
Input: evaluate output  
Output: decision + one-sentence justification

### `reflect`
Review what happened in the last action/step. Was it correct?  
Input: action + result  
Output: verdict (ok / incorrect / partial) + correction if needed

### `plan`
Produce an ordered task list for a goal.  
Input: goal + world model snapshot  
Output: numbered step list with dependencies marked

### `schedule`
Assign tasks to execution order given parallelism opportunities.  
Input: plan  
Output: batches of parallel steps

---

## Code Skills

### `refactor`
Improve code structure without changing behavior.  
Steps: `read_file` → analyze → propose changes → `write_file` (guarded)  
Contract: reversibility=low (git-tracked)

### `code_review`
Find correctness bugs and simplification opportunities.  
Steps: `diff_staged` → analyze → classify findings by severity  
Output: ranked finding list (critical → low)

### `bughunt`
Trace a reported symptom to its root cause.  
Steps: `search_symbol` → `read_file_range` → reason → trace call chain  
Output: root cause + affected code locations

### `stresstest`
Identify inputs that could break a component.  
Steps: analyze → enumerate edge cases → categorize (overflow / empty / race / boundary)  
Output: test case list with expected behavior

### `exec`
Run a specific command and interpret the result.  
Steps: `run_tests` or `check_types` → reflect on output  
Output: pass / fail + diagnosis if fail

---

## Meta Skills

### `summarize`
Compress a long artifact to essential points.  
Input: text / code / diff  
Output: bullet-point summary, max 10 items

### `decompose`
Break a vague goal into concrete sub-tasks.  
Input: high-level goal  
Output: task list with acceptance criteria per task
