---
name: commit-stage
description: "Validate staged git changes and commit them safely after thorough review. Trigger on: 'commit-stage', 'commit staged', 'review and commit', '提交暂存区', '检查并提交'. Do not use for general git operations without staged-change review intent."
---

# Commit-Stage

Validate staged git changes and commit only when review passes. Never modify files or widen commit scope.

## TL;DR

```
git diff --cached → line-by-line review + documentation drift check → commit or report failure
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
- Security/privacy leaks: secrets, tokens, private keys, credentials, `.env` values, personal data, internal hosts/IPs, user absolute paths, machine-local cache/build paths, accidentally staged logs/caches/build outputs
- Missing tests, incomplete refactors, dead code
- Commented-out debug, formatting issues
- **Documentation drift**: repository `.md` files that describe changed behavior/interfaces/commands but were not updated in this commit (see below)

Need context? Inspect nearby code/files. Do not guess.
Suspected bug? Reproduce it before confirming — no speculation; practice is the sole criterion for truth.

#### Documentation drift check

1. **Collect candidates** — run `git ls-files '*.md'` to list all tracked markdown files.
2. **Exclude already-staged .md** — if a `.md` is part of the staged changes, treat it as "user already covered"; only verify its sync completeness, do not suggest additional edits beyond what was staged.
3. **Semantic judgment** — for each candidate, determine whether it describes behavior, interfaces, CLI flags, configuration keys, commands, or workflows that the staged diff modifies. A mere lexical mention without semantic conflict (e.g., internal refactor that does not change public behavior) does **not** constitute drift.
4. **Classify**:
   - High confidence the doc is stale → **Related** (stop commit, provide diff fix).
   - Uncertain whether the doc needs updating → **Unclear** (stop commit, state location + one-sentence reason, do not force a diff).
5. **Failure report label** — prefix the Problem section with `Documentation drift: <file path>` so the user can immediately distinguish doc issues from code bugs.

### Step 2.5 — Parallel subagent review (when warranted)

When the review workload is large (many staged files, many candidate `.md` files, or both), split the work into atomic subtasks and delegate to parallel subagents. The decision to split is heuristic — use your judgment based on diff size, candidate count, and available context budget. Do **not** split trivially small reviews.

**Splitting rules:**

| Dimension | Atomic unit |
|---|---|
| Code review | One staged file = one subtask |
| Documentation drift | One candidate `.md` = one subtask |

**Shared read-only context (given to every subagent):**

- Full staged diff (`git diff --cached`).
- **Identifier Inventory**: before splitting, extract from the diff all public-facing identifiers — exported API names, CLI commands/flags, configuration keys, environment variables, command paths, behavioral keywords. This inventory ensures every subagent has cross-file visibility.

**Subagent output contract (fixed structure):**

```
classification: Related | Unrelated | Unclear
kind: Code | DocumentationDrift
location: <file:line or file:section>
problem: <one-sentence>
reason: <short explanation>
suggested_fix: <diff block or "N/A">
```

**Main agent aggregation:**

1. Collect all subagent results.
2. Deduplicate by (location, problem summary).
3. Re-classify each finding independently (subagent classification is advisory, not final).
4. **Identifier coverage check**: verify every item in the Identifier Inventory was examined by at least one subagent; if not, perform a targeted follow-up check for uncovered identifiers.
5. Make the final commit/stop decision.

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
<Colloquial, zero jargon, understandable by someone who has never seen this project; 1-2 sentences / ~50 chars; state what went wrong and who is affected>

## Review Checklist
- [ ] Staged diff reviewed line by line
- [ ] Correctness/regression risks checked
- [ ] Security/privacy leaks checked
- [ ] Related documentation drift checked
- [ ] Commit scope boundary checked

## Problem
<what you found — for documentation drift, prefix with "Documentation drift: <path>">

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
<Colloquial, zero jargon, understandable by someone who has never seen this project; 1-2 sentences / ~50 chars; state what changed and what the user will notice>

## Review Checklist
- [ ] Staged diff reviewed line by line
- [ ] Correctness/regression risks checked
- [ ] Security/privacy leaks checked
- [ ] Related documentation drift checked
- [ ] Commit scope boundary checked

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
