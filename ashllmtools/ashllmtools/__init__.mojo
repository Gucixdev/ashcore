# ashllmtools — LLM-augmented development runtime for Mojo

# Layer 0: lazytools
from ashllmtools.tools import (
    ShellResult, shell_run, shell_ok,
    file_exists, read_text, write_text, list_dir,
    git_branch_current, git_status, git_diff_staged, git_log, git_is_clean,
)

# Layer 1 / firewall: decision contract
from ashllmtools.decision_contract import (
    RISK_LOW, RISK_MEDIUM, RISK_HIGH, RISK_BLOCK,
    risk_name,
    Action,
    GuardResult,
    evaluate,
)

# Agent state machine
from ashllmtools.agent_state import (
    STATE_REACT, STATE_PLAN, STATE_AUTO, STATE_PASS, STATE_EVAL,
    state_name,
    EV_USER_MSG, EV_GOAL_DETECTED, EV_PLAN_APPROVED, EV_PLAN_REJECTED,
    EV_AUTO_CMD, EV_STOP_CMD, EV_REACT_CMD, EV_EVAL_CMD,
    EV_STEP_DONE, EV_BLOCKED, EV_GOAL_DONE,
    StateMachine,
)

# Layer 3: world model
from ashllmtools.world_model import (
    FileState, GitState, Assumption, WorldModel,
)

# Layer 4: memory
from ashllmtools.memory import (
    Note, NoteMemory,
    Episode, EpisodicMemory,
    SemanticChunk, SemanticMemory,
    LongTermMemory,
)

# Layer 5: context engine
from ashllmtools.context_engine import (
    PRI_CRITICAL, PRI_HIGH, PRI_MEDIUM, PRI_LOW,
    AUTH_REPO, AUTH_SESSION, AUTH_FETCHED, AUTH_WEB,
    ContextChunk, ContextEngine,
)

# Layer 5 / RAG: knowledge retrieval
from ashllmtools.rag import (
    Document, RAGPipeline,
    retrieve_file, grep_repo,
)

# Layer 2: workflow
from ashllmtools.workflow import (
    TS_PENDING, TS_RUNNING, TS_DONE, TS_BLOCKED, TS_SKIPPED,
    ts_name,
    Task, StepResult,
    LOOP_CONTINUE, LOOP_DONE, LOOP_BLOCKED, LOOP_ERROR,
    WorkflowEngine,
)

# Layer 2: skills
from ashllmtools.skills import (
    SkillResult, Skill, SkillRegistry,
)
