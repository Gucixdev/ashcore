"""
ashllmtools.workflow — unified decision loop + task decomposition.

Every workflow is an instance of the unified decision loop:

  1. ORIENT   — sync world model to current state
  2. PLAN     — decompose goal if no plan exists
  3. SELECT   — pick next unblocked task
  4. CONTRACT — decision contract evaluation (firewall gate)
  5. EXECUTE  — invoke skill or tool
  6. REFLECT  — evaluate result
  7. UPDATE   — update world model + memory
  8. CHECK    — goal achieved? blocked? → exit or loop

Exit conditions:
  done    — all tasks DONE, acceptance criteria met
  blocked — contract BLOCK, missing info, or unresolvable dependency
  error   — unrecoverable failure
"""

from ashllmtools.decision_contract import Action, GuardResult, evaluate
from ashllmtools.decision_contract import RISK_BLOCK, RISK_HIGH, RISK_LOW
from ashllmtools.decision_contract import risk_name, _contains


# ── Task status ───────────────────────────────────────────────────────────────

alias TS_PENDING  = 0
alias TS_RUNNING  = 1
alias TS_DONE     = 2
alias TS_BLOCKED  = 3
alias TS_SKIPPED  = 4


def ts_name(s: Int) -> String:
    if s == TS_PENDING:  return String("PENDING")
    if s == TS_RUNNING:  return String("RUNNING")
    if s == TS_DONE:     return String("DONE")
    if s == TS_BLOCKED:  return String("BLOCKED")
    if s == TS_SKIPPED:  return String("SKIPPED")
    return String("?")


# ── Task ──────────────────────────────────────────────────────────────────────

struct Task(Copyable, ImplicitlyCopyable, Movable, ImplicitlyDeletable):
    """
    A single unit of work within a workflow.
    deps: list of task IDs that must be DONE before this task can start.
    """
    var id:     Int
    var desc:   String
    var skill:  String   # which skill handles this task
    var deps:   List[Int]
    var status: Int
    var result: String   # output after execution

    def __init__(out self, id: Int, desc: String, skill: String = ""):
        self.id     = id
        self.desc   = desc
        self.skill  = skill
        self.deps   = List[Int]()
        self.status = TS_PENDING
        self.result = String("")

    def add_dep(mut self, dep_id: Int):
        self.deps.append(dep_id)

    def is_ready(self, tasks: List[Task]) -> Bool:
        """True iff all dependencies are DONE."""
        for d in range(len(self.deps)):
            var dep_id = self.deps[d]
            for t in range(len(tasks)):
                if tasks[t].id == dep_id and tasks[t].status != TS_DONE:
                    return False
        return True

    def describe(self) -> String:
        return "[" + String(self.id) + "] " + ts_name(self.status) + " — " + self.desc


# ── Loop result ───────────────────────────────────────────────────────────────

alias LOOP_CONTINUE = 0
alias LOOP_DONE     = 1
alias LOOP_BLOCKED  = 2
alias LOOP_ERROR    = 3


struct StepResult(Copyable, ImplicitlyCopyable, Movable, ImplicitlyDeletable):
    """Result of one iteration of the unified decision loop."""
    var outcome: Int
    var reason:  String

    def __init__(out self, outcome: Int, reason: String):
        self.outcome = outcome
        self.reason  = reason


# ── WorkflowEngine ────────────────────────────────────────────────────────────

struct WorkflowEngine(Movable):
    """
    Stateful task runner implementing the unified decision loop.

    One step() call = one loop iteration (steps 1-8 above).
    The caller drives the outer loop (agent_state AUTO handles this).
    """
    var tasks:    List[Task]
    var goal:     String
    var _next_id: Int

    def __init__(out self, goal: String):
        self.tasks    = List[Task]()
        self.goal     = goal
        self._next_id = 0

    def __moveinit__(out self, owned other: Self):
        self.tasks    = other.tasks^
        self.goal     = other.goal
        self._next_id = other._next_id

    # ── Task management ───────────────────────────────────────────────────

    def add_task(mut self, desc: String, skill: String = "") -> Int:
        """Add a task. Returns its ID."""
        var id = self._next_id
        self._next_id += 1
        self.tasks.append(Task(id=id, desc=desc, skill=skill))
        return id

    def add_dep(mut self, task_id: Int, dep_id: Int):
        for i in range(len(self.tasks)):
            if self.tasks[i].id == task_id:
                self.tasks[i].add_dep(dep_id)
                return

    # ── Unified decision loop — one step ──────────────────────────────────

    def step(mut self) -> StepResult:
        """Execute one iteration of the unified decision loop."""
        # Steps 1-2: ORIENT + PLAN are external (caller syncs world model)
        # Step 3: SELECT — first unblocked PENDING task
        var task_idx = self._select()
        if task_idx < 0:
            if self._all_done():
                return StepResult(LOOP_DONE, "all tasks completed")
            return StepResult(LOOP_BLOCKED, "no unblocked tasks available")

        # Step 4: CONTRACT
        var t   = self.tasks[task_idx]
        var act = Action(
            cmd        = t.skill + ": " + t.desc,
            scope      = "repo",
            reversible = True,
            blast      = 0,
            authorized = False,
        )
        var guard = evaluate(act)
        if guard.risk == RISK_BLOCK:
            self.tasks[task_idx].status = TS_BLOCKED
            return StepResult(LOOP_BLOCKED,
                "task " + String(t.id) + " blocked: " + guard.reason)

        # Step 5: EXECUTE
        self.tasks[task_idx].status = TS_RUNNING
        var out = self._execute_task(task_idx)

        # Step 6: REFLECT — any non-empty result not starting with "ERROR:" = success
        var failed = (out == "") or _contains(out, "ERROR:")
        if failed:
            self.tasks[task_idx].status = TS_BLOCKED
            return StepResult(LOOP_BLOCKED,
                "task " + String(t.id) + " execution failed: " + out)

        # Step 7: UPDATE
        self.tasks[task_idx].result = out
        self.tasks[task_idx].status = TS_DONE

        # Step 8: CHECK
        if self._all_done():
            return StepResult(LOOP_DONE, "goal achieved: " + self.goal)
        return StepResult(LOOP_CONTINUE, "task " + String(t.id) + " done")

    def run(mut self, max_steps: Int = 100) -> StepResult:
        """Run the loop until done, blocked, or max_steps exceeded."""
        for _ in range(max_steps):
            var r = self.step()
            if r.outcome != LOOP_CONTINUE:
                return r
        return StepResult(LOOP_BLOCKED, "max_steps exceeded")

    def describe(self) -> String:
        var done    = 0
        var pending = 0
        var blocked = 0
        for i in range(len(self.tasks)):
            var s = self.tasks[i].status
            if s == TS_DONE:
                done += 1
            elif s == TS_PENDING or s == TS_RUNNING:
                pending += 1
            elif s == TS_BLOCKED:
                blocked += 1
        var gl   = self.goal.byte_length()
        var cap  = 40 if gl > 40 else gl
        var goal = String(StringSlice(ptr=self.goal.unsafe_ptr(), length=cap))
        return (
            "Workflow(" + goal
            + ", done=" + String(done)
            + ", pending=" + String(pending)
            + ", blocked=" + String(blocked) + ")"
        )

    # ── Internal helpers ──────────────────────────────────────────────────

    def _select(self) -> Int:
        """Return index of first ready PENDING task, or -1."""
        for i in range(len(self.tasks)):
            if self.tasks[i].status == TS_PENDING:
                if self.tasks[i].is_ready(self.tasks):
                    return i
        return -1

    def _all_done(self) -> Bool:
        for i in range(len(self.tasks)):
            var s = self.tasks[i].status
            if s != TS_DONE and s != TS_SKIPPED:
                return False
        return True

    def _execute_task(mut self, idx: Int) -> String:
        """Stub executor. Returns non-empty result = success."""
        return "stub: " + self.tasks[idx].desc
