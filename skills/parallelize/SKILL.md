---
name: parallelize
description: Parallelize via subagents.
---

1. Parse user message for `sub=N` (e.g. "parallelize sub=5 ..."). If present, use N as subagent count; otherwise default to 3.
2. Split the task into N or more independent parts.
3. Dispatch each part to a separate subagent.
4. Run all subagents in parallel in a single round.
5. Merge results: converge into a coherent whole, do NOT concatenate raw outputs.

### MUST DO

Use at least 3 subagents (or `sub=N` if specified). Use as many as the work naturally splits into.