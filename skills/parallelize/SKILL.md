---
name: parallelize
description: Parallelize via subagents.
---

1. Split the task into 3 or more independent parts.
2. Dispatch each part to a separate subagent.
3. Run all subagents in parallel in a single round.
4. Merge results: converge into a coherent whole, do NOT concatenate raw outputs.

### MUST DO

Use at least 3 subagents. Use as many as the work naturally splits into.