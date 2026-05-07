---
name: commit-stage
description: "Validate staged git changes and commit them safely after thorough review. Trigger on: 'commit-stage', 'commit staged', 'review and commit', '提交暂存区', '检查并提交'. Do not use for general git operations without staged-change review intent."
---

# Commit-Stage

Validate staged git changes and commit only when review passes. Never modify files or widen commit scope.

## TL;DR

```
git diff --cached → line-by-line review → commit or report failure
```

## When to use

- User wants to commit staged changes.
- User says "commit-stage", "review and commit", "提交暂存区", "检查并提交".

## When not to use

- General git ops without staged-change review intent.
- Creating or modifying files.

## Workflow

### Step 1 — Inspect staged changes

- Run `git diff --cached`.
- Nothing staged → report "Nothing staged for commit." and stop.

### Step 2 — Line-by-line review

Review every line. Do not assume correctness. Look for:

- Logic errors, off-by-one, missing error handling
- Wrong variable names, broken assumptions, race conditions
- API misuse, regressions, behavior-breaking changes
- Missing tests, incomplete refactors, dead code
- Commented-out debug, formatting issues

Need context? Inspect nearby code/files. Do not guess.
Suspected bug? Reproduce it before confirming — no speculation; practice is the sole criterion for truth.

### Step 3 — Classify findings

| Classification | Action |
|---|---|
| **Related** to staged changes | Stop. Do not commit. |
| **Unrelated** | May continue, explain boundary in chat |
| **Unclear** | Stop. Prefer false positive over false negative |

### Step 4 — Failure path

When stopping:

1. Report in chat only — no .md artifacts.
2. State: problem, relation to staged changes, reason.
3. Provide complete `diff`-formatted fix in fenced code block, not partial.
4. Cannot propose reliable fix? Say so explicitly.

Failure output format:

```markdown
## Result
Commit stopped.

## Plain Explanation
<one-sentence plain-language summary of what went wrong>

## Problem
<what you found>

## Reason
<short explanation>

## Suggested Fix
````diff
<complete diff recommendation>
````
```

### Step 5 — Success path

No material problems found:

- Write conventional commit: `<type>: <description>`.
- Use user hint as commit-message intent when provided.
- No hint → infer from staged changes.
- Commit only staged content — no unstaged changes.

Success output format:

```markdown
## Result
Commit created.

## Plain Explanation
<one-sentence plain-language summary of what this commit does>

## Commit Message
`<type>: <description>`

## Summary
- <short bullet summarizing why this commit was made>
- <optional short bullet for notable scope or boundary>
```

## Constraints

- **No file modifications**: do not edit, create, or patch source files.
- **No scope widening**: commit only what is staged; no `git add` unless explicitly asked.
- **No .md artifacts**: report failures in chat only.
- All user-facing chat output in **Chinese**.
