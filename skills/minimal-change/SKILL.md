---
name: minimal-change
description: Prefer the smallest sufficient change. Reject broad refactors, abstractions, dependencies, fallbacks, and scope creep. Use for targeted fixes/changes, "minimal", "smallest change", "lean", or tight requests.
---

Keep work limited to the stated goal.

## Workflow

1. Restate goal + narrow success check.
2. Inspect only files needed for the edit.
3. Choose smallest sufficient change: one line → local block → existing utility → abstraction only if required.
4. Edit surgically; leave unrelated names and structure unchanged.
5. Verify narrowly.

## 🔴 CHECKPOINT / STOP

Stop before widening scope if the change spreads beyond the request, changes unrelated behavior, adds a dependency, or needs a broad refactor. If asking is disallowed, report the blocker instead of widening silently.

## Failure Modes

- If a one-line fix fails → widen only to nearest local block.
- If an existing utility might fit → inspect nearby callers first.
- If verification fails outside touched code → report it as unrelated.
- If two minimal fixes tie → choose fewer side effects and easier rollback.

## Do Not

- Do not refactor, rename, reformat, or clean nearby code.
- Do not add abstractions, dependencies, config, compatibility paths, or fallback layers.
- Do not touch extra files unless needed for goal or verification.
- Do not hide failures with mocks, silent fallbacks, or unrelated guards.
