# langfuse

LLM observability: trace every LLM call, score outputs, track costs.

## What it gives you

- Full trace of every prompt + completion
- Latency per call, token counts, cost estimates
- Scoring: attach human or automated scores to traces
- Dataset management: save good/bad examples for fine-tuning

## Integration points in ashllmtools

| Module          | What to trace                                  |
|-----------------|------------------------------------------------|
| `skills.mojo`   | Each skill invocation (name, input, output)    |
| `workflow.mojo` | Each step (task, skill, result, step_count)    |
| `context_engine`| Chunks injected, compressed_bytes, priority    |
| `memory.mojo`   | Note writes, episodic entries, semantic lookups|

## Trace structure

```json
{
  "name": "skill.review",
  "input": { "name": "review", "inp": "src/main.mojo" },
  "output": { "ok": true, "output": "verdict=pass\n..." },
  "metadata": { "step": 3, "guard_risk": "LOW" }
}
```

## Without langfuse

Log to `scan_log`-readable files:
```
[SKILL] review(src/main.mojo) → ok=true risk=LOW step=3
```

Search later with `scan_log("agent.log", level="error")`.
