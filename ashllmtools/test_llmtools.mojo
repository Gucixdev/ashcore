"""ashllmtools — test suite."""

from tools.sys.fs    import show_tree, file_info, system_info, scan_log, write_text
from tools.sys.shell import shell_run
from decision_contract import (
    Action, evaluate, _contains,
    RISK_LOW, RISK_MEDIUM, RISK_HIGH, RISK_BLOCK,
)
from agent_state import (
    StateMachine,
    STATE_REACT, STATE_PLAN, STATE_AUTO, STATE_PASS, STATE_EVAL,
    EV_GOAL_DETECTED, EV_PLAN_APPROVED, EV_PLAN_REJECTED,
    EV_AUTO_CMD, EV_STOP_CMD, EV_REACT_CMD, EV_EVAL_CMD,
    EV_STEP_DONE, EV_BLOCKED, EV_GOAL_DONE, EV_USER_MSG,
)
from memory import (
    NoteMemory, EpisodicMemory, SemanticMemory, LongTermMemory,
)
from context_engine import (
    ContextChunk, ContextEngine,
    PRI_CRITICAL, PRI_HIGH, PRI_MEDIUM, PRI_LOW,
    AUTH_REPO, AUTH_SESSION, AUTH_FETCHED, AUTH_WEB,
)
from rag import Document, RAGPipeline, FRESH_FETCHED
from workflow import WorkflowEngine, LOOP_DONE, LOOP_BLOCKED, TS_DONE
from skills import SkillRegistry
from skill_types import SkillResult
from world_model import WorldModel
from dsl import DSLFact, DSLStore, parse_fact, parse_facts


# ── helpers ───────────────────────────────────────────────────────────────────

struct Counter(Copyable, ImplicitlyCopyable, Movable, ImplicitlyDeletable):
    var passed: Int
    var failed: Int

    def __init__(out self):
        self.passed = 0
        self.failed = 0


def ok(mut c: Counter, cond: Bool, msg: String):
    if cond:
        c.passed += 1
    else:
        c.failed += 1
        print("FAIL: " + msg)


def _find_pos(haystack: String, needle: String) -> Int:
    """Return byte offset of first needle occurrence in haystack, or -1."""
    var hl = haystack.byte_length()
    var nl = needle.byte_length()
    if nl == 0:
        return 0
    if nl > hl:
        return -1
    var hp = haystack.unsafe_ptr()
    var np = needle.unsafe_ptr()
    for i in range(hl - nl + 1):
        var is_match = True
        for j in range(nl):
            if hp[i + j] != np[j]:
                is_match = False
                break
        if is_match:
            return i
    return -1


# ── decision_contract ─────────────────────────────────────────────────────────

def test_decision_contract(mut c: Counter):
    # Safe local action → LOW
    var a = Action(cmd="read file.mojo", scope="src/", reversible=True, blast=0)
    var g = evaluate(a)
    ok(c, g.risk == RISK_LOW, "safe action is LOW risk")

    # Push to main → BLOCK (G1)
    var b = Action(cmd="git push", scope="main", reversible=False, blast=1)
    var gb = evaluate(b)
    ok(c, gb.risk == RISK_BLOCK, "push to main is BLOCK")

    # rm -rf without auth → BLOCK (G4)
    var c = Action(cmd="rm -rf /tmp/x", scope="local",
                   reversible=False, authorized=False)
    var gc = evaluate(c)
    ok(c, gc.risk == RISK_BLOCK, "rm -rf without auth is BLOCK")

    # rm -rf with explicit auth → HIGH (irreversible, authorized)
    var d = Action(cmd="rm -rf /tmp/x", scope="local",
                   reversible=False, authorized=True)
    var gd = evaluate(d)
    ok(c, gd.risk <= RISK_HIGH, "rm -rf with auth is HIGH or lower")

    # --force without auth → BLOCK (G2)
    var e = Action(cmd="git push --force", scope="feature-branch",
                   reversible=False, authorized=False)
    var ge = evaluate(e)
    ok(c, ge.risk == RISK_BLOCK, "--force without auth is BLOCK")

    # Prod blast radius → BLOCK
    var f = Action(cmd="deploy", scope="prod", reversible=False, blast=3)
    var gf = evaluate(f)
    ok(c, gf.risk == RISK_BLOCK, "prod blast radius is BLOCK")

    # Shared-infra without auth → HIGH
    var h = Action(cmd="migrate db", scope="staging",
                   reversible=False, blast=2, authorized=False)
    var gh = evaluate(h)
    ok(c, gh.risk >= RISK_HIGH, "shared-infra without auth is HIGH")

    # _contains helper
    ok(c, _contains("hello world", "world"), "_contains: found")
    ok(c, not _contains("hello", "xyz"), "_contains: not found")
    ok(c, _contains("hello", ""), "_contains: empty needle always true")
    ok(c, not _contains("hi", "hello"), "_contains: needle longer than haystack")


# ── agent_state ───────────────────────────────────────────────────────────────

def test_agent_state(mut c: Counter):
    var sm = StateMachine()
    ok(c, sm.current == STATE_REACT, "starts in REACT")

    # REACT → PLAN on goal_detected
    _ = sm.transition(EV_GOAL_DETECTED)
    ok(c, sm.current == STATE_PLAN, "REACT+goal→PLAN")

    # PLAN → AUTO on approval
    _ = sm.transition(EV_PLAN_APPROVED)
    ok(c, sm.current == STATE_AUTO, "PLAN+approve→AUTO")
    ok(c, sm.is_autonomous(), "AUTO is autonomous")

    # AUTO → PASS on stop
    _ = sm.transition(EV_STOP_CMD)
    ok(c, sm.current == STATE_PASS, "AUTO+stop→PASS")
    ok(c, sm.is_waiting(), "PASS is waiting")

    # PASS → REACT on user message
    _ = sm.transition(EV_USER_MSG)
    ok(c, sm.current == STATE_REACT, "PASS+msg→REACT")

    # REACT → AUTO directly on /auto
    var sm2 = StateMachine()
    _ = sm2.transition(EV_AUTO_CMD)
    ok(c, sm2.current == STATE_AUTO, "REACT+/auto→AUTO")

    # PLAN → REACT on rejection
    var sm3 = StateMachine()
    _ = sm3.transition(EV_GOAL_DETECTED)
    _ = sm3.transition(EV_PLAN_REJECTED)
    ok(c, sm3.current == STATE_REACT, "PLAN+reject→REACT")

    # AUTO → REACT on /react
    var sm4 = StateMachine()
    _ = sm4.transition(EV_AUTO_CMD)
    _ = sm4.transition(EV_REACT_CMD)
    ok(c, sm4.current == STATE_REACT, "AUTO+/react→REACT")

    # EVAL transition
    var sm5 = StateMachine()
    _ = sm5.transition(EV_EVAL_CMD)
    ok(c, sm5.current == STATE_EVAL, "REACT+/eval→EVAL")

    # describe
    var desc = sm.describe()
    ok(c, desc.byte_length() > 0, "describe returns non-empty string")


# ── memory ────────────────────────────────────────────────────────────────────

def test_memory(mut c: Counter):
    # NoteMemory
    var notes = NoteMemory()
    notes.set("branch", "main")
    ok(c, notes.get("branch") == "main", "note set/get")
    notes.set("branch", "dev")
    ok(c, notes.get("branch") == "dev", "note overwrite")
    ok(c, notes.get("missing") == "", "note missing → empty")
    ok(c, notes.size() == 1, "note size after overwrite")
    notes.set("x", "1")
    ok(c, notes.size() == 2, "note size after second insert")
    notes.delete("x")
    ok(c, notes.size() == 1, "note size after delete")

    # EpisodicMemory
    var ep = EpisodicMemory()
    ep.record("user", "hello")
    ep.next_turn()
    ep.record("tool", "result")
    ok(c, ep.size() == 2, "episode count")
    var last = ep.last_n(1)
    ok(c, len(last) == 1, "last_n(1) returns 1")
    ok(c, last[0].kind == "tool", "last episode is tool")
    var since = ep.since_turn(1)
    ok(c, len(since) == 1, "since_turn(1) returns episodes from turn 1+")

    # SemanticMemory
    var sem = SemanticMemory()
    var tags1 = List[String]()
    tags1.append("mojo")
    tags1.append("parser")
    sem.store("parse_int implementation", tags1)
    var tags2 = List[String]()
    tags2.append("mojo")
    tags2.append("arena")
    sem.store("arena allocator", tags2)
    var query = List[String]()
    query.append("parser")
    var hits = sem.retrieve(query, 10)
    ok(c, len(hits) == 1, "semantic retrieve by tag")
    ok(c, hits[0].content == "parse_int implementation", "semantic retrieve correct chunk")

    # LongTermMemory composite
    var ltm = LongTermMemory()
    ltm.notes.set("goal", "fix bug")
    ok(c, ltm.notes.get("goal") == "fix bug", "LTM note")
    var serial = ltm.serialize_notes()
    ok(c, _find_pos(serial, "goal=fix bug") >= 0, "LTM serialization contains note")
    ok(c, ltm.describe().byte_length() > 0, "LTM describe non-empty")


# ── context_engine ────────────────────────────────────────────────────────────

def test_context_engine(mut c: Counter):
    var engine = ContextEngine(budget=10000)
    engine.add(ContextChunk("HIGH content", "src/main.mojo", AUTH_REPO, PRI_HIGH))
    engine.add(ContextChunk("LOW content",  "cache.txt",     AUTH_WEB,  PRI_LOW))
    engine.add(ContextChunk("MED content",  "docs/",         AUTH_FETCHED, PRI_MEDIUM))

    var ctx = engine.build()
    ok(c, ctx.byte_length() > 0, "context engine produces output")

    # HIGH (AUTH_REPO=0) should appear before LOW (AUTH_WEB=3) after ranking
    var high_pos = _find_pos(ctx, "HIGH content")
    var low_pos  = _find_pos(ctx, "LOW content")
    ok(c, high_pos >= 0 and low_pos >= 0, "both chunks present in output")
    ok(c, high_pos < low_pos, "high-authority chunk ranked before low-authority")

    # Dedup removes exact duplicates
    var engine2 = ContextEngine(budget=10000)
    engine2.add(ContextChunk("same", "a", AUTH_REPO, PRI_HIGH))
    engine2.add(ContextChunk("same", "b", AUTH_REPO, PRI_HIGH))
    engine2.dedup()
    ok(c, len(engine2._chunks) == 1, "dedup removes duplicate content")

    # add_facts: DSLStore → ContextChunk
    var engine_f = ContextEngine(budget=10000)
    var dstore = DSLStore()
    dstore.add_line("env = production")
    dstore.add_line("cache > db")
    engine_f.add_facts(dstore)
    ok(c, len(engine_f._chunks) == 1, "add_facts: one chunk added")
    var ctx_f = engine_f.build()
    ok(c, _find_pos(ctx_f, "env = production") >= 0, "add_facts: fact content in context")
    ok(c, _find_pos(ctx_f, "cache > db") >= 0,       "add_facts: second fact in context")

    # add_facts: empty store adds nothing
    var engine_e = ContextEngine(budget=10000)
    var empty_store = DSLStore()
    engine_e.add_facts(empty_store)
    ok(c, len(engine_e._chunks) == 0, "add_facts: empty store adds no chunk")

    # CRITICAL chunks bypass budget
    var engine3 = ContextEngine(budget=5)  # tiny budget
    engine3.add(ContextChunk("normal chunk with many bytes here", "big.mojo",
                              AUTH_REPO, PRI_MEDIUM))
    engine3.add(ContextChunk("small", "s.mojo", AUTH_REPO, PRI_CRITICAL))
    var ctx3 = engine3.build()
    ok(c, _find_pos(ctx3, "small") >= 0, "CRITICAL chunk bypasses budget")


# ── rag ───────────────────────────────────────────────────────────────────────

def test_rag(mut c: Counter):
    # Fresh repo doc (age=-1)
    var fresh = Document("content", "src/lib.mojo", AUTH_REPO, FRESH_REPO)
    ok(c, fresh.is_fresh(), "repo doc always fresh")

    # Stale fetched doc
    var stale = Document("content", "https://docs.example.com",
                          AUTH_FETCHED, FRESH_FETCHED + 1)
    ok(c, not stale.is_fresh(), "fetched doc stale after threshold")

    # Fresh fetched doc
    var ok_doc = Document("content", "https://docs.example.com", AUTH_FETCHED, 0)
    ok(c, ok_doc.is_fresh(), "fetched doc fresh at age=0")

    # RAGPipeline filters stale
    var rag = RAGPipeline()
    rag.add(fresh)
    rag.add(stale)
    var chunks = rag.build(top_k=10)
    ok(c, len(chunks) == 1, "RAG filters out stale documents")

    # RAGPipeline ranks by authority (repo before web)
    var rag2 = RAGPipeline()
    rag2.add(Document("web result",   "https://search.example.com", AUTH_WEB,  0))
    rag2.add(Document("repo content", "src/lib.mojo",               AUTH_REPO, FRESH_REPO))
    var chunks2 = rag2.build(top_k=10)
    ok(c, len(chunks2) == 2, "RAG returns both fresh docs")
    ok(c, chunks2[0].authority == AUTH_REPO, "RAG ranks repo before web")

    # to_chunk conversion
    var doc = Document("data", "src/x.mojo", AUTH_REPO, FRESH_REPO)
    var chunk = doc.to_chunk(PRI_HIGH)
    ok(c, chunk.content == "data",        "to_chunk preserves content")
    ok(c, chunk.authority == AUTH_REPO,   "to_chunk preserves authority")
    ok(c, chunk.priority == PRI_HIGH,     "to_chunk applies priority")


# ── workflow ──────────────────────────────────────────────────────────────────

def test_workflow(mut c: Counter):
    # Single task — git_status always succeeds
    var w = WorkflowEngine("check repo")
    _ = w.add_task("", "git_status")
    var r = w.run(max_steps=5)
    ok(c, r.outcome == LOOP_DONE, "single-task workflow completes")
    ok(c, w.tasks[0].status == TS_DONE, "task marked DONE")

    # Two independent tasks
    var w2 = WorkflowEngine("update tests")
    _ = w2.add_task("", "git_status")
    _ = w2.add_task("all passing\n", "reflect")
    var r2 = w2.run(max_steps=10)
    ok(c, r2.outcome == LOOP_DONE, "two-task workflow completes")

    # Dependency ordering: b depends on a → a must complete first
    var w3 = WorkflowEngine("staged check")
    var a   = w3.add_task("line1\nline2\n", "analyze")
    var b   = w3.add_task("", "git_status")
    w3.add_dep(b, a)
    var r3 = w3.run(max_steps=10)
    ok(c, r3.outcome == LOOP_DONE,       "dependent tasks complete in order")
    ok(c, w3.tasks[0].status == TS_DONE, "first dep task done")
    ok(c, w3.tasks[1].status == TS_DONE, "second dep task done")

    # Empty workflow → immediately done
    var w4 = WorkflowEngine("empty")
    var r4 = w4.step()
    ok(c, r4.outcome == LOOP_DONE, "empty workflow immediately done")

    # Unknown skill → task blocked → workflow blocked
    var w5 = WorkflowEngine("unknown skill")
    _ = w5.add_task("some input", "does_not_exist")
    var r5 = w5.run(max_steps=2)
    ok(c, r5.outcome == LOOP_BLOCKED, "unknown skill causes blocked workflow")


# ── skills ────────────────────────────────────────────────────────────────────

def test_skills(mut c: Counter):
    var reg = SkillRegistry()
    ok(c, reg.size() >= 14, "all builtin skills registered")
    ok(c, reg.find("reflect"),   "reflect skill registered")
    ok(c, reg.find("bughunt"),   "bughunt skill registered")
    ok(c, reg.find("review"),    "review skill registered")
    ok(c, reg.find("plan"),      "plan skill registered")
    ok(c, reg.find("run_tests"), "run_tests skill registered")

    # reflect on ok output
    var r = reg.run("reflect", "all tests passed")
    ok(c, r.ok, "reflect succeeds on ok output")
    ok(c, _find_pos(r.output, "verdict=ok") >= 0, "reflect verdict ok")

    # reflect on error output
    var r2 = reg.run("reflect", "ERROR: test failed")
    ok(c, r2.ok, "reflect succeeds on error output")
    ok(c, _find_pos(r2.output, "verdict=incorrect") >= 0, "reflect verdict incorrect")

    # reflect on FAIL pattern
    var r3 = reg.run("reflect", "FAIL: something broke")
    ok(c, r3.ok, "reflect succeeds on FAIL output")
    ok(c, _find_pos(r3.output, "verdict=incorrect") >= 0, "reflect FAIL → incorrect")

    # analyze — counts lines
    var r4 = reg.run("analyze", "line1\nline2\nline3\n")
    ok(c, r4.ok, "analyze succeeds")
    ok(c, _find_pos(r4.output, "lines=3") >= 0, "analyze counts 3 newlines")

    # analyze — empty input fails
    var r5 = reg.run("analyze", "")
    ok(c, not r5.ok, "analyze fails on empty input")

    # unknown skill
    var r6 = reg.run("doesnotexist", "")
    ok(c, not r6.ok, "unknown skill returns failure")
    ok(c, _find_pos(r6.reason, "unknown skill") >= 0, "unknown skill reason message")

    # reflect empty input
    var r7 = reg.run("reflect", "")
    ok(c, not r7.ok, "reflect fails on empty input")

    # custom registration
    reg.register("myskill", "a custom skill", "cognitive")
    ok(c, reg.find("myskill"), "custom skill registered")

    # skill list includes all
    var names = reg.list()
    ok(c, len(names) >= 15, "list returns all skills including custom")

    # plan
    var rplan = reg.run("plan", "Read the file\nRun the tests\nFix the bugs")
    ok(c, rplan.ok,                               "plan succeeds")
    ok(c, _find_pos(rplan.output, "steps:") >= 0, "plan output has steps header")
    ok(c, _find_pos(rplan.output, "1.") >= 0,     "plan produces numbered steps")
    ok(c, not reg.run("plan", "").ok,             "plan fails on empty input")

    # reason
    var rreas = reg.run("reason", "The function fails because input is empty.")
    ok(c, rreas.ok,                                         "reason succeeds")
    ok(c, _find_pos(rreas.output, "sentences=") >= 0,       "reason reports sentence count")
    ok(c, _find_pos(rreas.output, "causal") >= 0,           "reason detects causal keyword")
    ok(c, not reg.run("reason", "").ok,                     "reason fails on empty input")

    # decide
    var rdec = reg.run("decide", "Option A: rewrite the parser")
    ok(c, rdec.ok,                                     "decide succeeds")
    ok(c, _find_pos(rdec.output, "decision:") >= 0,    "decide output has decision field")
    ok(c, _find_pos(rdec.output, "verdict=") >= 0,     "decide output has verdict field")
    var rdec_risky = reg.run("decide", "delete the entire database")
    ok(c, rdec_risky.ok,                                       "decide succeeds on risky input")
    ok(c, _find_pos(rdec_risky.output, "review_first") >= 0,   "decide flags destructive action")
    ok(c, not reg.run("decide", "").ok,                "decide fails on empty input")

    # schedule
    var rsched = reg.run("schedule", "deploy after build\nbuild\ntest first")
    ok(c, rsched.ok,                                    "schedule succeeds")
    ok(c, _find_pos(rsched.output, "schedule:") >= 0,   "schedule output has header")
    ok(c, _find_pos(rsched.output, "1.") >= 0,          "schedule produces step 1")
    ok(c, not reg.run("schedule", "").ok,               "schedule fails on empty input")

    # bughunt — search in current dir
    var rbug = reg.run("bughunt", ".")
    ok(c, rbug.ok, "bughunt succeeds on repo root")

    # review — succeeds whether or not there are staged changes
    var rrev = reg.run("review", "")
    ok(c, rrev.ok, "review succeeds")
    ok(c, _find_pos(rrev.output, "added=") >= 0
       or _find_pos(rrev.output, "review:") >= 0,
       "review output contains stats or no-changes message")

    # refactor — on this test file
    var rref = reg.run("refactor", "test_llmtools.mojo")
    ok(c, rref.ok, "refactor succeeds on test_llmtools.mojo")
    ok(c, _find_pos(rref.output, "lines=") >= 0, "refactor reports line count")

    # stresstest
    var rst = reg.run("stresstest", ".")
    ok(c, rst.ok, "stresstest succeeds on repo root")

    # whalecheck — synthetic series with one large spike
    var prices_flat  = String("100,101,100,101,100,101,100,115,100,101,100")
    var rwc = reg.run("whalecheck", prices_flat)
    ok(c, rwc.ok, "whalecheck succeeds")
    ok(c, _find_pos(rwc.output, "whale_analysis:") >= 0, "whalecheck output has header")
    ok(c, _find_pos(rwc.output, "whale_bars=") >= 0,     "whalecheck reports whale_bars")
    ok(c, not reg.run("whalecheck", "").ok,              "whalecheck fails on empty input")

    # chart — render ASCII chart
    var rch = reg.run("chart", prices_flat)
    ok(c, rch.ok, "chart succeeds")
    ok(c, _find_pos(rch.output, "|") >= 0,  "chart output has border characters")
    ok(c, _find_pos(rch.output, "lo=") >= 0, "chart output has lo value")
    ok(c, _find_pos(rch.output, "hi=") >= 0, "chart output has hi value")
    ok(c, not reg.run("chart", "").ok,      "chart fails on empty input")

    # backtest — smoke test with synthetic prices
    var prices_long = String(
        "100,101,102,103,102,101,100,99,98,97,96,95,96,97,98,99,100,101,102,103,104,105"
    )
    var rbt = reg.run("backtest", "prices:" + prices_long + " fast:3 slow:5")
    ok(c, rbt.ok, "backtest succeeds on valid series")
    ok(c, _find_pos(rbt.output, "backtest:") >= 0, "backtest output has header")
    ok(c, _find_pos(rbt.output, "pnl=") >= 0,      "backtest output has pnl")


# ── world_model ───────────────────────────────────────────────────────────────

def test_world_model(mut c: Counter):
    # __init__: default state is unknown branch, not clean, sync_count=0
    var wm = WorldModel()
    ok(c, wm.git.branch == "(unknown)", "default branch is (unknown)")
    ok(c, wm.git.is_clean == False,     "default is_clean is False")
    ok(c, wm.sync_count == 0,           "initial sync_count is 0")
    ok(c, len(wm.files) == 0,           "no files tracked initially")
    ok(c, len(wm.assumptions) == 0,     "no assumptions initially")

    # describe() returns a non-empty string containing branch info
    var desc = wm.describe()
    ok(c, desc.byte_length() > 0,                    "describe() is non-empty")
    ok(c, _find_pos(desc, "WorldModel") >= 0,         "describe() contains WorldModel")
    ok(c, _find_pos(desc, "syncs=0") >= 0,            "describe() shows sync count")

    # set_assumption / get_assumption round-trip
    wm.set_assumption("env", "production")
    ok(c, wm.get_assumption("env") == "production",   "get_assumption retrieves set value")
    ok(c, wm.get_assumption("missing") == "",         "missing assumption returns empty")

    # is_stale() is False when all assumptions have confidence ≥ 50
    ok(c, not wm.is_stale(),                          "not stale with fresh assumption")

    # update existing assumption keeps count stable
    wm.set_assumption("env", "staging")
    ok(c, wm.get_assumption("env") == "staging",      "set_assumption updates existing key")
    ok(c, len(wm.assumptions) == 1,                   "no duplicate assumption added")

    # sync() re-reads git state and increments sync_count
    wm.sync()
    ok(c, wm.sync_count == 1,                         "sync_count incremented after sync()")
    ok(c, wm.git.branch != "",                        "branch non-empty after sync()")

    # After sync, assumption confidence degrades by 10 (100 → 90, still fresh)
    ok(c, not wm.is_stale(),                          "still not stale after one sync")

    # track_file: registers file, checks existence
    wm.track_file("world_model.mojo")
    ok(c, len(wm.files) == 1,                         "file tracked")
    ok(c, wm.files[0].path == "world_model.mojo",     "tracked file path correct")

    # After 5 syncs (5×10 = 50 degradation, confidence = 50) not stale yet
    # After 6th sync confidence = 40 < 50 → stale
    wm.set_assumption("check", "val")
    for _ in range(6):
        wm.sync()
    ok(c, wm.is_stale(),                              "stale after enough syncs degrade confidence")


# ── fs: show_tree / file_info / system_info / scan_log ───────────────────────

def test_fs_extended(mut c: Counter):
    # show_tree: returns non-empty string for any real path
    var tree = show_tree(".", 2)
    ok(c, tree.byte_length() > 0, "show_tree returns non-empty output")

    # show_tree: non-existent path returns an informative string
    var bad = show_tree("/nonexistent_path_xyz", 1)
    ok(c, bad.byte_length() > 0, "show_tree non-existent path returns message")

    # file_info: current directory
    var fi = file_info(".")
    ok(c, fi.byte_length() > 0, "file_info('.') returns output")
    ok(c, _find_pos(fi, "type=") >= 0, "file_info contains type field")

    # file_info: non-existent path returns error message
    var fi_bad = file_info("/nonexistent_xyz")
    ok(c, _find_pos(fi_bad, "not found") >= 0, "file_info non-existent returns not-found message")

    # system_info: always returns non-empty on Linux
    var si = system_info()
    ok(c, si.byte_length() > 0, "system_info returns output")
    ok(c, _find_pos(si, "kernel=") >= 0 or _find_pos(si, "unavailable") >= 0,
       "system_info contains kernel or unavailable marker")

    # scan_log: non-existent file → error message
    var sl_bad = scan_log("/nonexistent_log.txt")
    ok(c, _find_pos(sl_bad, "not found") >= 0, "scan_log missing file returns not-found")

    # scan_log: tail of /proc/version (always exists on Linux)
    var sl = scan_log("/proc/version", last_n=5)
    ok(c, sl.byte_length() > 0, "scan_log /proc/version returns output")

    # scan_log: pattern that matches nothing → no-matches message
    var sl_nm = scan_log("/proc/version", pattern="XXXXXXNOTPRESENT")
    ok(c, _find_pos(sl_nm, "no matches") >= 0, "scan_log no matches returns message")

    # scan_log: level shorthand on a synthesised log
    # (write a tiny temp log, scan it, clean up)
    var tmp = "/tmp/_ash_scan_log_test.log"
    try:
        write_text(tmp,
            "INFO  app started\n"
            + "DEBUG connecting\n"
            + "ERROR database timeout\n"
            + "WARN  retry 1\n"
            + "INFO  recovered\n"
        )
        var err_lines = scan_log(tmp, level="error")
        ok(c, _find_pos(err_lines, "ERROR") >= 0, "scan_log level=error finds ERROR line")

        var warn_lines = scan_log(tmp, level="warn")
        ok(c, _find_pos(warn_lines, "WARN") >= 0, "scan_log level=warn finds WARN line")

        var combo = scan_log(tmp, pattern="database", level="warn")
        ok(c, combo.byte_length() > 0, "scan_log pattern+level combo returns output")

        var all_lines = scan_log(tmp, last_n=3)
        ok(c, all_lines.byte_length() > 0, "scan_log tail-only returns output")
        _ = shell_run("rm -f " + tmp + " 2>/dev/null")
    except:
        _ = shell_run("rm -f " + tmp + " 2>/dev/null")


# ── dsl ───────────────────────────────────────────────────────────────────────

def test_dsl(mut c: Counter):
    # ── parse_fact: definition / assignment ──────────────────────────────────
    var f1 = parse_fact("env = production")
    ok(c, f1.ok,             "parse_fact: ok flag set")
    ok(c, f1.lhs == "env",   "parse_fact: lhs")
    ok(c, f1.op  == "=",     "parse_fact: op =")
    ok(c, f1.rhs == "production", "parse_fact: rhs")
    ok(c, f1.ctx == "",      "parse_fact: no ctx")

    # ── context extraction ────────────────────────────────────────────────────
    var f2 = parse_fact("env = production (staging)")
    ok(c, f2.ok,               "parse_fact ctx: ok")
    ok(c, f2.rhs == "production", "parse_fact ctx: rhs without ctx")
    ok(c, f2.ctx == "staging", "parse_fact ctx: ctx extracted")

    # ── 2-char operators: longest-first disambiguation ────────────────────────
    var feq = parse_fact("ver == 2")
    ok(c, feq.op == "==", "parse_fact: == not =")

    var fneq = parse_fact("prod != staging")
    ok(c, fneq.op == "!=" and fneq.lhs == "prod", "parse_fact: !=")

    var fleads = parse_fact("error >> retry")
    ok(c, fleads.op == ">>" and fleads.rhs == "retry", "parse_fact: >>")

    var ffrom = parse_fact("token << vault")
    ok(c, ffrom.op == "<<" and ffrom.lhs == "token", "parse_fact: <<")

    var fown = parse_fact("secrets <= env")
    ok(c, fown.op == "<=" and fown.rhs == "env", "parse_fact: <=")

    var fequiv = parse_fact("dev <> local")
    ok(c, fequiv.op == "<>" and fequiv.lhs == "dev", "parse_fact: <>")

    var fbidir = parse_fact("a <-> b")
    ok(c, fbidir.op == "<->", "parse_fact: <-> (3-char) beats <>")

    var fmod = parse_fact("config +- timeout")
    ok(c, fmod.op == "+-", "parse_fact: +-")

    var fseq = parse_fact("task_a && task_b")
    ok(c, fseq.op == "&&", "parse_fact: &&")

    var fopen = parse_fact("perf ?? unknown")
    ok(c, fopen.op == "??", "parse_fact: ??")

    # ── 1-char operators ──────────────────────────────────────────────────────
    var fpref = parse_fact("cache > db")
    ok(c, fpref.op == ">" and fpref.lhs == "cache", "parse_fact: >")

    var fand = parse_fact("auth + tls")
    ok(c, fand.op == "+", "parse_fact: +")

    var fnot = parse_fact("debug -")
    ok(c, fnot.op == "-" and fnot.lhs == "debug", "parse_fact: -")

    var fwarn = parse_fact("! rate_limit")
    ok(c, fwarn.op == "!" and fwarn.rhs == "rate_limit", "parse_fact: !")

    var fcheck = parse_fact("health ?")
    ok(c, fcheck.op == "?", "parse_fact: ?")

    var fapprox = parse_fact("timeout ~ 30")
    ok(c, fapprox.op == "~", "parse_fact: ~")

    var fref = parse_fact("pool & workers")
    ok(c, fref.op == "&", "parse_fact: &")

    var fall = parse_fact("* endpoints")
    ok(c, fall.op == "*", "parse_fact: *")

    var freq = parse_fact("tls $")
    ok(c, freq.op == "$", "parse_fact: $")

    var fslice = parse_fact("rows % 1000")
    ok(c, fslice.op == "%", "parse_fact: %")

    var fsrc = parse_fact("^ config")
    ok(c, fsrc.op == "^", "parse_fact: ^")

    var fat = parse_fact("log @ stdout")
    ok(c, fat.op == "@", "parse_fact: @")

    var falt = parse_fact("json / msgpack")
    ok(c, falt.op == "/" and falt.rhs == "msgpack", "parse_fact: /")

    # ── bad line (no operator) ────────────────────────────────────────────────
    var fbad = parse_fact("justword")
    ok(c, not fbad.ok, "parse_fact: no-op line → ok=False")

    # ── to_string / describe round-trip ──────────────────────────────────────
    var fts = parse_fact("cache > db (latency)")
    ok(c, _find_pos(fts.to_string(), "cache > db") >= 0,    "to_string contains lhs op rhs")
    ok(c, _find_pos(fts.to_string(), "(latency)") >= 0,     "to_string contains ctx")
    ok(c, _find_pos(fts.describe(), "DSLFact") >= 0,        "describe contains DSLFact")

    # ── parse_facts: multi-line + comment skip ────────────────────────────────
    var text = (
        "# this is a comment\n"
        + "env = production\n"
        + "cache > db\n"
        + "\n"
        + "api_key << vault\n"
    )
    var facts = parse_facts(text)
    ok(c, len(facts) == 3, "parse_facts: 3 facts (comment + blank skipped)")

    # ── DSLStore ──────────────────────────────────────────────────────────────
    var store = DSLStore()
    ok(c, store.size() == 0, "DSLStore starts empty")

    store.add_line("env = production (staging)")
    store.add_line("cache > db")
    store.add_line("api_key << vault")
    ok(c, store.size() == 3, "DSLStore.size after 3 add_line calls")

    # query_lhs
    var by_lhs = store.query_lhs("env")
    ok(c, len(by_lhs) == 1, "query_lhs: finds 1 match")
    ok(c, by_lhs[0].rhs == "production", "query_lhs: correct rhs")

    # query_op
    var by_op = store.query_op("=")
    ok(c, len(by_op) == 1, "query_op: finds 1 = fact")

    # query_rhs
    var by_rhs = store.query_rhs("vault")
    ok(c, len(by_rhs) == 1, "query_rhs: finds api_key << vault")
    ok(c, by_rhs[0].lhs == "api_key", "query_rhs: correct lhs")

    # get
    ok(c, store.get("env", "=") == "production", "get: returns rhs for lhs+op")
    ok(c, store.get("missing", "=") == "",        "get: empty for missing key")

    # has
    ok(c, store.has("cache", ">", "db"),         "has: exact match found")
    ok(c, not store.has("cache", ">", "memory"), "has: wrong rhs → False")

    # add_text
    var store2 = DSLStore()
    store2.add_text("a = 1\nb = 2\n# skip me\nc = 3\n")
    ok(c, store2.size() == 3, "add_text: 3 facts from multi-line text")

    # clear
    store2.clear()
    ok(c, store2.size() == 0, "clear: store is empty after clear")

    # to_string
    var store3 = DSLStore()
    store3.add_line("env = production")
    var s = store3.to_string()
    ok(c, _find_pos(s, "env = production") >= 0, "to_string: fact rendered")

    # ── update ────────────────────────────────────────────────────────────────
    var su = DSLStore()
    su.add_line("env = production (staging)")
    su.update("env", "=", "development")         # update existing
    ok(c, su.get("env", "=") == "development",       "update: rhs replaced")
    ok(c, su.size() == 1,                            "update: no duplicate added")
    var u_ctx = su.query_lhs("env")
    ok(c, u_ctx[0].ctx == "staging",                 "update: ctx preserved")
    su.update("branch", "=", "main")             # append new
    ok(c, su.size() == 2,                            "update: append when not found")
    ok(c, su.get("branch", "=") == "main",           "update: appended value readable")

    # ── remove ────────────────────────────────────────────────────────────────
    var sr = DSLStore()
    sr.add_line("env = production")
    sr.add_line("cache > db")
    sr.add_line("env = staging")   # second env = (different value — different row)
    sr.remove("env", "=")          # removes ALL env = facts
    ok(c, sr.size() == 1,             "remove: both env= facts removed")
    ok(c, sr.get("cache", ">") == "db", "remove: unrelated fact kept")
    sr.remove("nonexistent", "=")  # no-op
    ok(c, sr.size() == 1,             "remove: no-op on missing fact")

    # ── WorldModel.record + facts_to_string ───────────────────────────────────
    var wm = WorldModel()
    ok(c, wm.facts.size() == 0, "WorldModel starts with no facts")

    wm.record("env = production (staging)")
    wm.record("cache > db")
    ok(c, wm.facts.size() == 2, "WorldModel.record adds facts")

    wm.record_text("api_key << vault\n# comment\ntls $\n")
    ok(c, wm.facts.size() == 4, "WorldModel.record_text adds facts (comment skipped)")

    var wm_str = wm.facts_to_string()
    ok(c, _find_pos(wm_str, "env = production") >= 0, "facts_to_string contains env fact")
    ok(c, _find_pos(wm_str, "cache > db") >= 0,       "facts_to_string contains cache fact")

    # describe() now shows fact count
    wm.sync()
    var desc = wm.describe()
    ok(c, _find_pos(desc, "facts=4") >= 0, "describe includes fact count")

    # ── WorldModel.sync() auto-records git facts ──────────────────────────────
    var wm2 = WorldModel()
    wm2.sync()
    ok(c, wm2.facts.get("branch", "=") != "", "sync: branch fact recorded")
    var clean_val = wm2.facts.get("clean", "=")
    ok(c, clean_val == "True" or clean_val == "False", "sync: clean fact recorded")

    # ── set_assumption mirrors to facts ───────────────────────────────────────
    var wm3 = WorldModel()
    wm3.set_assumption("env", "production")
    ok(c, wm3.facts.get("env", "=") == "production", "set_assumption mirrors to facts")
    wm3.set_assumption("env", "staging")
    ok(c, wm3.facts.get("env", "=") == "staging",    "set_assumption update mirrors to facts")
    ok(c, wm3.facts.size() == 1,                      "set_assumption: no duplicate in facts")


# ── main ──────────────────────────────────────────────────────────────────────

def main():
    var c = Counter()
    test_decision_contract(c)
    test_agent_state(c)
    test_memory(c)
    test_context_engine(c)
    test_rag(c)
    test_workflow(c)
    test_skills(c)
    test_world_model(c)
    test_dsl(c)
    test_fs_extended(c)

    print("\n--- ashllmtools ---")
    print("passed: " + String(c.passed))
    print("failed: " + String(c.failed))
    if c.failed > 0:
        raise Error("tests failed: " + String(c.failed))
