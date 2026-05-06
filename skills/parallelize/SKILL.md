---
name: parallelize
description: Parallelize via subagents.
---

1. Parse user message for `sub=N` (e.g. "parallelize sub=5 ..."). If present, use N; otherwise default 3.
2. Decompose task into N+ **atomic** parts — each self-contained, independently executable. Parts mutually exclusive (no overlap) unless search/review (see below).
3. Dispatch each atomic part to separate subagent.
4. Run all subagents parallel in single round.
5. Merge results: converge into coherent whole, do NOT concatenate raw outputs.

### Overlap-allowed tasks

These task types may produce overlapping results — allow overlap in decomposition, **deduplicate + aggregate** during merge:

- Code review & search tasks (`grep`, codebase search, file search)
- Test coverage exploration (agents may test same area)
- Vulnerability / security scanning

### MUST DO

Use ≥3 subagents (or `sub=N` if specified). Use as many as work naturally splits into.
