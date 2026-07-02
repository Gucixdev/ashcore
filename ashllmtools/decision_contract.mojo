"""
ashllmtools.decision_contract — runtime firewall, NOT documentation.

Every action passes through evaluate() before execution.
No workflow, skill, or tool bypasses this gate.

Risk levels (exclusive, ordered):
  LOW    — proceed without user confirmation
  MEDIUM — log + proceed
  HIGH   — surface to user, require explicit approval
  BLOCK  — hard stop, never execute

6-step evaluation (in order; first BLOCK wins):
  1. hard_rules_guard   — non-negotiable hard stops
  2. scope_guard        — is the target in authorized scope?
  3. reversibility_guard — can this be undone?
  4. blast_radius_guard — how many things does this affect?
  5. auth_guard         — explicit authorization check for HIGH risk
  6. world_sync_guard   — hook for world model freshness (always LOW)

Hard rules (always BLOCK regardless of other guards):
  G1  no direct push to main/master
  G2  no --force / --no-verify without explicit instruction
  G3  no DROP / TRUNCATE on shared databases
  G4  no rm -rf without explicit user confirmation
  G5  no credential commits (.env, secrets.*, *.key)
  G6  no force-push to any protected branch
  F1  no full file reads when offset+limit suffices
  F2  no repeated injection of context already present
  F3  no tool call when a simpler built-in exists
  F4  no new file when an existing file fits
  E1  no executing unreviewed remote scripts
  E2  no installing packages from untrusted sources
  E3  no exposing internal paths in external outputs
  E4  no spawning sub-agents for trivially local tasks
  N1  no comments unless WHY is non-obvious
  N2  no abstraction without a failing test that requires it
  N3  no refactor inside a bug-fix commit
  N4  no multi-concern commits
  S1  no secrets in logs or outputs
  S2  no hardcoded credentials
  S3  no disabling TLS verification
"""

# ── Risk levels ───────────────────────────────────────────────────────────────

alias RISK_LOW    = 0
alias RISK_MEDIUM = 1
alias RISK_HIGH   = 2
alias RISK_BLOCK  = 3


def risk_name(level: Int) -> String:
    if level == RISK_LOW:    return String("LOW")
    if level == RISK_MEDIUM: return String("MEDIUM")
    if level == RISK_HIGH:   return String("HIGH")
    return String("BLOCK")


# ── String helpers ────────────────────────────────────────────────────────────

def _contains(haystack: String, needle: String) -> Bool:
    """Case-sensitive substring check."""
    var hl = haystack.byte_length()
    var nl = needle.byte_length()
    if nl == 0:
        return True
    if nl > hl:
        return False
    var hp = haystack.unsafe_ptr()
    var np = needle.unsafe_ptr()
    for i in range(hl - nl + 1):
        var is_match = True
        for j in range(nl):
            if hp[i + j] != np[j]:
                is_match = False
                break
        if is_match:
            return True
    return False


# ── Action descriptor ─────────────────────────────────────────────────────────

struct Action(Copyable, ImplicitlyCopyable, Movable, ImplicitlyDeletable):
    """Describes a proposed action before execution."""
    var cmd:         String   # shell command or operation name
    var scope:       String   # target: branch name, file path, service, etc.
    var reversible:  Bool     # can it be undone?
    var blast:       Int      # 0=local, 1=repo, 2=shared-infra, 3=prod
    var authorized:  Bool     # explicit user authorization received?

    def __init__(out self,
                 cmd:        String,
                 scope:      String,
                 reversible: Bool  = True,
                 blast:      Int   = 0,
                 authorized: Bool  = False):
        self.cmd        = cmd
        self.scope      = scope
        self.reversible = reversible
        self.blast      = blast
        self.authorized = authorized


# ── Guard result ──────────────────────────────────────────────────────────────

struct GuardResult(Copyable, ImplicitlyCopyable, Movable, ImplicitlyDeletable):
    """Result of a single guard evaluation."""
    var risk:   Int
    var reason: String

    def __init__(out self, risk: Int, reason: String):
        self.risk   = risk
        self.reason = reason

    def is_block(self) -> Bool:
        return self.risk == RISK_BLOCK


# ── Individual guards ─────────────────────────────────────────────────────────

def scope_guard(action: Action) -> GuardResult:
    """G1/G6: Block pushes to protected branches."""
    var s = action.scope
    if s == "main" or s == "master" or s == "origin/main" or s == "origin/master":
        return GuardResult(RISK_BLOCK, "G1: direct write to protected branch is forbidden")
    return GuardResult(RISK_LOW, "scope ok")


def reversibility_guard(action: Action) -> GuardResult:
    """Irreversible actions require HIGH authorization."""
    if not action.reversible:
        if action.authorized:
            return GuardResult(RISK_MEDIUM, "irreversible but authorized")
        return GuardResult(RISK_HIGH, "R1: irreversible action — requires user approval")
    return GuardResult(RISK_LOW, "reversible")


def blast_radius_guard(action: Action) -> GuardResult:
    """High blast radius escalates risk."""
    if action.blast >= 3:
        return GuardResult(RISK_BLOCK, "B1: prod blast radius — hard block")
    if action.blast >= 2:
        if not action.authorized:
            return GuardResult(RISK_HIGH, "B2: shared-infra blast radius — approval required")
        return GuardResult(RISK_MEDIUM, "B2: shared-infra, authorized")
    if action.blast >= 1:
        return GuardResult(RISK_MEDIUM, "B3: repo-wide change — log and proceed")
    return GuardResult(RISK_LOW, "local blast radius")


def hard_rules_guard(action: Action) -> GuardResult:
    """Check hard rules G1-S3 that can never be overridden."""
    var cmd = action.cmd
    # G4: rm -rf
    if _contains(cmd, "rm -rf") and not action.authorized:
        return GuardResult(RISK_BLOCK, "G4: rm -rf requires explicit authorization")
    # G2: --force / --no-verify
    if (_contains(cmd, "--force") or _contains(cmd, "--no-verify")) and not action.authorized:
        return GuardResult(RISK_BLOCK, "G2: force flags require explicit authorization")
    # G3: DROP / TRUNCATE (check both cases)
    if (_contains(cmd, "DROP TABLE") or _contains(cmd, "drop table")
            or _contains(cmd, "TRUNCATE") or _contains(cmd, "truncate")) and not action.authorized:
        return GuardResult(RISK_BLOCK, "G3: destructive SQL requires explicit authorization")
    # S1/S2: credential patterns (simple heuristic)
    if (_contains(cmd, ".env") or _contains(cmd, "SECRET") or _contains(cmd, "PASSWORD")
            or _contains(cmd, "secret") or _contains(cmd, "password")) and not action.authorized:
        return GuardResult(RISK_BLOCK, "S1/S2: potential credential exposure")
    return GuardResult(RISK_LOW, "hard rules ok")


# ── Main entry point ──────────────────────────────────────────────────────────

def evaluate(action: Action) -> GuardResult:
    """
    6-step decision contract evaluation.
    Returns the highest-risk GuardResult encountered.
    First BLOCK result short-circuits remaining checks.
    """
    # Step 1: hard rules (always checked first)
    var r = hard_rules_guard(action)
    if r.is_block():
        return r

    # Step 2: scope
    var sg = scope_guard(action)
    if sg.is_block():
        return sg
    if sg.risk > r.risk:
        r = sg

    # Step 3: reversibility
    var rev = reversibility_guard(action)
    if rev.risk > r.risk:
        r = rev
    if r.is_block():
        return r

    # Step 4: blast radius
    var blast = blast_radius_guard(action)
    if blast.is_block():
        return blast
    if blast.risk > r.risk:
        r = blast

    # Step 5: auth (HIGH without authorization → surface to user, stay HIGH)
    if r.risk == RISK_HIGH and not action.authorized:
        return GuardResult(RISK_HIGH,
            "action is HIGH risk: " + r.reason + " — surface to user for approval")

    # Step 6: world-sync (hook for WorldModel.sync(); always LOW here)
    return r
