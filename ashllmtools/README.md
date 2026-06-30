# ashllmtools

Architecture map for LLM-augmented development. Seven layers from raw I/O to
world model. One orthogonal firewall: the **decision contract**.

---

## Layer Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  DECISION CONTRACT  ←  firewall over all layers (not a doc) │
└─────────────────────────────────────────────────────────────┘

6  World Model        state · beliefs · assumptions · dependencies
5  Context Engine     ranking · retrieval · compression · dedup · summaries · priority
4  Memory             notes · episodic · semantic · long-term
─────────────────────────────────────────────────────────────────
3  Workflow           lang · search · sysadmin · format tasks
                      goal-management · task-decomposition · unified-decision-loop
2  Skills             refactor · analysis · code-review · bughunt · stresstest
                      exec · reflect · plan · schedule · reason · analyze
                      evaluate · decide
1  Tools              shell · read · write · search · codemap · diff · git
─────────────────────────────────────────────────────────────────
0  Chat + /commands   raw interface to the agent
```

**Layers 0–3** are execution.  
**Layers 4–6** are cognition.  
**Decision contract** is orthogonal — it intercepts every transition between layers.

---

## Directory Index

| Path | What |
|------|------|
| [`decision_contract/`](decision_contract/README.md) | Runtime firewall — hard guards, not guidelines |
| [`lazytools/`](lazytools/README.md) | Reusable tool invocations (code · sys · web) |
| [`skills/`](skills/README.md) | Composable capabilities built on tools |
| [`workflow/`](workflow/README.md) | Task-type templates + unified decision loop |
| [`agent_state/`](agent_state/README.md) | State machine: pass · auto · react · plan · eval |
| [`mcp/`](mcp/README.md) | MCP tools and providers |
| [`rag/`](rag/README.md) | Knowledge retrieval system |
| [`techniques/`](techniques/README.md) | Field-tested techniques from real projects |

---

## Design Principles

**Decision contract beats everything.** A skill or workflow that would violate
the contract is rejected before execution, not documented as "don't do this."

**Lazytools are leaves.** They call exactly one tool and return. No logic, no
branching. Logic lives in skills and workflows.

**Skills compose tools, never other skills.** Skill chains are workflows, not
meta-skills. Keeps the graph flat and debuggable.

**Context is the bottleneck.** Every layer consumes context. The context engine
(layer 5) is the most critical non-execution component.

**World model drives decisions.** The agent's belief about system state is the
input to every non-trivial decision. Stale world model = wrong decisions.
