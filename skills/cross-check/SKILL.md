---
name: cross-check
description: "Launch parallel subagents to review recent changes after code modification. Trigger on: 'cross-check', 'review changes', 'check my changes', '审查改动', '交叉检查', 'review my work'. Do not use for general PR review — only for reviewing changes just made by the current agent. No arguments needed — defaults to reviewing only changes made in the current conversation."
---

# Cross-Check

Launch parallel subagents, independently review changes, triage findings, fix valid issues, re-verify.

## TL;DR

```
Make changes → Collect diff → Partition & launch parallel subagents → Triage & fix → Re-verify → Report
```

## When to use

- After code changes, before declaring done.
- User says "cross-check", "review changes", "check my changes", "审查改动", "交叉检查".
- No arguments needed — defaults to reviewing only changes made in current conversation.

## When not to use

- Existing PR review → use `code-reviewer` skill or `gh`.
- Code exploration without changes to verify.

## Dispatch strategy

| Diff size | Strategy | Rationale |
|-----------|----------|----------|
| < 200 lines, 1 file | 1 `general` subagent | Small scope |
| < 500 lines, 2-4 files | 1 `general` subagent | Moderate scope |
| >= 500 lines or >= 5 files | Multiple subagents per domain | Split keeps each focused |

Multiple subagents → partition by **domain**:

1. Group touched files by concern (logic, tests, config, UI, docs).
2. One subagent per domain — each gets its domain's diff + shared cross-domain interface summary.
3. Launch all in parallel via multiple `task` calls in one message.

> **Rule of thumb**: Never send > 800 lines diff to one subagent. Split instead.

### Domain partition example

```
Files changed: auth.ts, auth.test.ts, config.ts, README.md
Domains:
  - logic:   auth.ts, config.ts        → subagent A
  - tests:   auth.test.ts              → subagent B
  - docs:    README.md                 → subagent C  (skip if trivial)
```

Trivially small domains merge into adjacent domain.

## Input resolution

No required arguments. Determine review scope from context:

| User input | What to review |
|-----------|---------------|
| No arguments (just "cross-check") | **Only changes agent made in this conversation**: reconstruct diff from agent's own edit/write operations, not from `git diff` which includes pre-existing dirty state |
| One commit: `cross-check HEAD~1` | Diff of that single commit: `git diff HEAD~1..HEAD --` |
| Commit range: `cross-check HEAD~3..HEAD` | Diff of that range: `git diff <start>..<end> --` |
| File paths: `cross-check src/foo.ts` | Uncommitted changes for those files only |

### Scoping to current conversation (default)

When invoked without arguments, scope diff to **only changes agent made during this conversation** — exclude pre-existing dirty state, changes by others, leftover edits from before this session.

**Important**: `git diff` includes ALL uncommitted changes to a file, not just what agent changed this conversation. When scoping to current-conversation changes, avoid relying on `git diff` alone — it pulls unrelated dirty state. Use conversation history (agent's own edit/write operations) to determine what changed, or use `git diff` only when user explicitly passes a commit range or file paths.

## Workflow

### Step 1 — Gather recent changes

- Determine review scope from user input (see Input resolution).
- **Default (no arguments)**: Collect diff from conversation history — only agent's own edit/write operations. Avoid bare `git diff` which includes pre-existing dirty state.
- **Explicit commit range or paths**: Run appropriate `git diff` command(s).
- No diff output → "No changes to review." → stop.
- Count total diff lines + files changed → apply dispatch strategy.

### Step 2 — Launch review subagent(s)

Use `task` tool with `subagent_type: "general"`. **Launch all in parallel** in one message.

Each subagent prompt MUST include:

1. Diff for its domain (or full diff if single subagent).
2. Original task description (intended goal).
3. Review instructions (checklist below).
4. If multi-domain: brief note about other domains' key interfaces.

Subagent prompt template:

```
You are an independent code reviewer. Your job is to find real bugs, logic errors, and missing edge cases — not to rubber-stamp the diff.

## Reviewing approach

- Do NOT review from memory alone. When a claim about the codebase can be verified by reading files, grep, or glob, **explore the codebase to verify it**.
- Use read, grep, glob tools to check surrounding context, callers, imports, tests, and related implementations.
- If unsure whether something is a bug, explore before reporting — confirm or discard with evidence.
- Focus on behavior that differs from the intent, not on style preferences.

## Task

Original goal: <what the change intends to accomplish>

<If multi-domain:> You are reviewing the <domain name> domain. Other changed domains: <list other domains and their key files/interfaces>.

Diff:
<domain-relevant diff portion>

## Review checklist

For each item, if you cannot confirm from the diff alone, explore the codebase:

- **Correctness**: Does the diff achieve the stated goal? Any logic errors, off-by-one, wrong variable names?
- **Completeness**: Are there edge cases, error paths, or callers that this diff misses? Check by reading the callers and callees.
- **Consistency**: Does the code follow existing patterns? Read nearby code and related modules to verify.
- **Safety**: Any security issues, leaked secrets, or destructive operations?
- **Side effects**: Will this break other callers, tests, or downstream consumers? Trace the call chain.
- **Cross-domain** (if multi-domain): Are interfaces between this domain and other changed domains still compatible?

## Output format

Return ONLY this structured report:

- **Verdict**: PASS or FAIL
- **Issues**: List of issues (if any), each with:
  - file:line
  - severity: critical / warning / note
  - description
  - suggested fix (concrete, not vague)
  - evidence: what you found in the codebase that supports this finding (or "verified by reading <file>")
- If PASS, confirm the change is safe to ship.
- If you explored files to verify a concern and found no issue, explicitly state "Verified: no issue" for that item — do not leave it ambiguous.
```

### Step 3 — Triage and present findings

Collect all subagent results. Merge findings, de-duplicate, resolve contradictions by re-reading code.

**Triage every finding**:

| Finding | Action |
|---------|--------|
| **Valid and should fix** | Present to user with `question` tool if available. Let user decide to apply, skip, or modify. |
| **Valid but out of scope** | Note for user. Do NOT fix tangential things. |
| **Invalid / false positive** | Discard. Note why (e.g., "line 42 handles null already"). |
| **Style preference** | Discard. Only flag if contradicts project convention. |

**Present findings to user and ask for confirmation** before applying any fix. Use the `question` tool to list all valid findings and let user choose which to apply.

After user confirms, apply fixes. Then re-run cross-check from Step 1 to verify fixes.

| Overall verdict | Action |
|-----------------|--------|
| User approved all fixes | Apply fixes, then re-verify from Step 1. |
| User skipped some issues | Re-verify remaining changes from Step 1, then proceed to Step 4. |
| All findings resolved | Proceed to Step 4. |
| Valid issues you cannot fix | Report to user with explanation. |
| Round limit reached | Report remaining issues, let user decide. |

### Step 4 — Report to user

```markdown
## Cross-Check Result: PASS / FAIL

### Changes Reviewed (N subagents)
- <list of files changed>

### Issues Found & Resolved
- [<severity>] <file>:<line> — <description> → <suggested fix> → ✅ Fixed / ⏭ Skipped (reason)

### Summary
<one sentence verdict>
```

## Constraints

- **Independent review**: Subagents get diff + review criteria only — no bias from your own assessment. Subagents ARE expected to explore codebase independently.
- **Explore, don't guess**: Subagent prompts instruct reviewers to use read/grep/glob to verify claims. This is due diligence, not bias.
- **No modification during review**: Do not edit files while subagents review. Collect diff first, launch reviews, then act on findings.
- **Re-run after fixes**: Fix → re-verify from Step 1. Fixes can introduce new problems.
- **Max 2 rounds**: After 2 fix-and-re-review rounds, report remaining issues to user. Do not loop indefinitely.
- **Parallel launch**: Multiple subagents → launch simultaneously in one message. Never sequentially.
- All user-facing output in **Chinese** unless user explicitly requests another language.

## Common pitfalls

- **Single subagent for huge diffs**: > 800 lines degrades quality. Split by domain.
- **Reviewing your own diff in same context**: Always use separate subagent calls.
- **Skipping diff collection**: Reading files misses what changed vs. what was already there.
- **Reviewing from memory**: Subagent must explore when unsure — unverified assumptions are not findings.
- **Ignoring warnings**: Warnings often indicate real issues. Surface them.
- **Over-fixing**: Style preferences ≠ correctness. Note but don't block.
- **Fixing without user confirmation**: Always present findings to user with `question` tool before applying fixes. Let user decide.
- **Sequential launches**: Always launch in parallel.
- **Missing cross-domain issues**: Each subagent needs key interfaces from other domains to flag incompatibilities.
- **Scope creep**: Without arguments, `git diff` includes pre-existing dirty state not from this conversation. Scope to agent's own changes only.