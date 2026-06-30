# RAG — Knowledge Retrieval System

Retrieval-Augmented Generation: inject relevant knowledge into context at
query time rather than relying on model training. Keeps context lean and
answers grounded in current, verifiable sources.

---

## Pipeline

```
query
  ↓
[1] RETRIEVE   — find relevant documents / chunks
  ↓
[2] RANK       — score by relevance + recency + authority
  ↓
[3] COMPRESS   — summarize or truncate to fit context budget
  ↓
[4] INJECT     — prepend to prompt as grounding context
  ↓
[5] GENERATE   — model answers using retrieved content
  ↓
[6] CITE       — link answer back to source chunks
```

---

## Knowledge Sources (by priority)

| Priority | Source | Freshness | Trust |
|----------|--------|-----------|-------|
| 1 | Current repo files | live | high |
| 2 | Session memory (episodic) | session | high |
| 3 | CHANGELOG / docs in repo | committed | high |
| 4 | External docs (fetched) | at fetch time | medium |
| 5 | Web search results | live | low |
| 6 | Model training data | cutoff | low |

Always prefer higher-priority sources. Never use model training data as a
citation — it's a fallback, not a source.

---

## Retrieval Strategies

### Keyword / Symbol Search
Use `search_symbol` / `grep` for code-level retrieval.  
Fast, precise, zero hallucination. Use this first.

### Semantic Retrieval
For prose knowledge (docs, issues, changelogs).  
Embed + cosine similarity if vector DB is available; otherwise use full-text
search on relevant files.

### Hybrid
Keyword pre-filter → semantic re-rank → top-K injection.  
Best for large repos or external knowledge bases.

---

## Context Budget Management

RAG competes with conversation history and tool outputs for context space.

Rules:
- Retrieved chunks get a fixed budget (e.g. 20% of total context)
- If chunks exceed budget: summarize, don't truncate mid-sentence
- De-duplicate: if the same content appears in multiple chunks, keep one
- Recency beats relevance for time-sensitive questions (deployment status,
  CI results, live errors)

---

## Freshness & Staleness

RAG answers are only as fresh as their source. Before injecting:

```
source age > threshold? → re-fetch or flag as potentially stale
threshold:
  repo files   → always fresh (read from disk)
  fetched docs → 1 hour
  web search   → 15 minutes for fast-moving topics (errors, outages)
```

If a retrieved source cannot be verified as current, label the answer
with the retrieval timestamp.

---

## Techniques

See [`techniques/`](../techniques/README.md) for `freshdocs` (keeping retrieved
docs current) and `leanctx` (compressing retrieved content to fit budget).
