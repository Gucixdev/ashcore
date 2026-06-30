"""
ashllmtools.agent_state — agent state machine.

States:
  REACT  — default: one user turn → one response, no autonomous multi-step
  PLAN   — decompose goal into a task list, no execution
  AUTO   — execute approved plan step-by-step until done/blocked/stopped
  PASS   — waiting, no autonomous action
  EVAL   — reflection: review last action for correctness

Transitions:
  REACT  → PLAN   when goal detected + no approved plan
  REACT  → AUTO   on /auto command
  PLAN   → AUTO   on plan approval
  PLAN   → REACT  on plan rejection
  AUTO   → PASS   on completion, /stop, or /pass
  AUTO   → REACT  on /react
  PASS   → REACT  on next user message
  any    → EVAL   on /eval or after each AUTO step
  EVAL   → REACT  verdict ok
  EVAL   → AUTO   verdict partial/incorrect (corrective re-entry)
"""

# ── State constants ───────────────────────────────────────────────────────────

alias STATE_REACT = 0
alias STATE_PLAN  = 1
alias STATE_AUTO  = 2
alias STATE_PASS  = 3
alias STATE_EVAL  = 4


def state_name(s: Int) -> String:
    if s == STATE_REACT: return String("REACT")
    if s == STATE_PLAN:  return String("PLAN")
    if s == STATE_AUTO:  return String("AUTO")
    if s == STATE_PASS:  return String("PASS")
    if s == STATE_EVAL:  return String("EVAL")
    return String("UNKNOWN")


# ── Transition events ─────────────────────────────────────────────────────────

alias EV_USER_MSG       = 0   # new user message received
alias EV_GOAL_DETECTED  = 1   # goal identified from user message
alias EV_PLAN_APPROVED  = 2   # user approved the plan
alias EV_PLAN_REJECTED  = 3   # user rejected the plan
alias EV_AUTO_CMD       = 4   # /auto command
alias EV_STOP_CMD       = 5   # /stop or /pass command
alias EV_REACT_CMD      = 6   # /react command
alias EV_EVAL_CMD       = 7   # /eval command
alias EV_STEP_DONE      = 8   # one AUTO step completed
alias EV_BLOCKED        = 9   # AUTO blocked by contract or ambiguity
alias EV_GOAL_DONE      = 10  # all acceptance criteria met


# ── State machine ─────────────────────────────────────────────────────────────

struct StateMachine(Copyable, ImplicitlyCopyable, Movable, ImplicitlyDeletable):
    """
    Lightweight state machine for agent mode tracking.
    Tracks current state and last event for logging.
    """
    var current:    Int
    var last_event: Int
    var step_count: Int   # AUTO steps executed in current run

    def __init__(out self):
        self.current    = STATE_REACT
        self.last_event = -1
        self.step_count = 0

    def transition(mut self, event: Int) -> Bool:
        """
        Apply event to current state.
        Returns True iff the state changed.
        """
        self.last_event = event
        var prev = self.current

        if self.current == STATE_REACT:
            if event == EV_GOAL_DETECTED:
                self.current = STATE_PLAN
            elif event == EV_AUTO_CMD:
                self.current = STATE_AUTO
                self.step_count = 0
            elif event == EV_EVAL_CMD:
                self.current = STATE_EVAL

        elif self.current == STATE_PLAN:
            if event == EV_PLAN_APPROVED:
                self.current    = STATE_AUTO
                self.step_count = 0
            elif event == EV_PLAN_REJECTED:
                self.current = STATE_REACT
            elif event == EV_EVAL_CMD:
                self.current = STATE_EVAL

        elif self.current == STATE_AUTO:
            if event == EV_STOP_CMD or event == EV_GOAL_DONE:
                self.current    = STATE_PASS
                self.step_count = 0
            elif event == EV_REACT_CMD:
                self.current    = STATE_REACT
                self.step_count = 0
            elif event == EV_BLOCKED:
                self.current    = STATE_PASS
                self.step_count = 0
            elif event == EV_STEP_DONE:
                self.step_count += 1
                self.current = STATE_EVAL
            elif event == EV_EVAL_CMD:
                self.current = STATE_EVAL

        elif self.current == STATE_PASS:
            if event == EV_USER_MSG:
                self.current = STATE_REACT
            elif event == EV_EVAL_CMD:
                self.current = STATE_EVAL

        elif self.current == STATE_EVAL:
            # Always return to REACT after evaluation; caller re-enters AUTO if needed
            if event == EV_STEP_DONE:
                self.current = STATE_REACT

        return self.current != prev

    def is_autonomous(self) -> Bool:
        return self.current == STATE_AUTO

    def is_waiting(self) -> Bool:
        return self.current == STATE_PASS

    def describe(self) -> String:
        return (
            "AgentState(" + state_name(self.current)
            + ", steps=" + String(self.step_count) + ")"
        )
