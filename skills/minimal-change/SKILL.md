---
name: minimal-change
description: Prefer the smallest change that solves the problem. Reject over-engineering, unnecessary refactoring, or scope creep. Use when user wants a change, implementation, adjustment, or fix and mentions "minimal", "smallest change", "lean", or when the task is clearly targeted.
---

Make the smallest possible change that achieves the stated goal. Do not refactor, reorganize, or "improve" surrounding code unless those changes are required to achieve the goal.

Rules:

- If a one-line change works, do not write five lines.
- If a local change works, do not introduce a new abstraction.
- If an existing utility already does the job, do not write a new one.
- If the change can be a surgical edit, do not rewrite the whole function.
- If the goal can be achieved without touching other files, do not touch other files.
- When multiple valid minimal changes exist, prefer the one with the fewest side effects and the easiest rollback.