---
name: cross-check
description: "Launch parallel subagents to review recent changes after code modification. Trigger on: 'cross-check', 'review changes', 'check my changes', '审查改动', '交叉检查', 'review my work'. Do not use for general PR review — only for reviewing changes just made by the current agent."
---

# Cross-Check

Launch parallel subagents → independently review changes → triage findings → report to user → fix & re-verify.

## TL;DR

```
Collect diff + parse intent → Launch ≥3 subagents → Triage → Report to user → User decides → Fix & re-verify
```

## When to use

- After code changes, before declaring done.
- User says "cross-check", "review changes", "check my changes", "审查改动", "交叉检查".

## When not to use

- Existing PR review → use `code-reviewer` skill or `gh`.
- Code exploration without changes to verify.

## Input resolution

| Input | Scope | Focus |
|-------|-------|-------|
| No arguments | Agent's own edits this session | General review |
| Commit range: `cross-check HEAD~3..HEAD` | `git diff <range>` | General review |
| File paths: `cross-check src/foo.ts` | Uncommitted changes for those files | General review |
| Arbitrary message: `cross-check 刚才改的认证逻辑` | Main agent parses which files/changes | Main agent parses review angle |
| Message with angle: `cross-check 性能问题` | Main agent parses scope | Review focuses on performance |
| Subagent count: `cross-check sub=5` | Same scope logic, count overridden | Uses N subagents instead of default |

Default (no arguments): scope to **only changes agent made in this conversation** — exclude pre-existing dirty state. Use conversation history to determine actual scope.

## Dispatch strategy

No fixed thresholds. Main agent judges based on diff size and complexity.

| Diff size | Strategy | Subagent gets |
|-----------|----------|---------------|
| Small | Each subagent sees full diff | Full diff |
| Large | Partition by domain | Each subagent gets its domain's diff + cross-domain interface summary |

Default 3 subagents (overridden by `sub=N` in message). All use `general` type, same role, independent views. If domains < count, assign extra subagents to largest domain or fall back to full-diff review.

Partition by domain (large diffs):

1. Group touched files by concern (logic, tests, config, UI, docs).
2. One subagent per domain.
3. Trivially small domains merge into adjacent domain.

## Workflow

### Step 1 — Collect diff + parse intent

- Determine scope and review focus from user input (see Input resolution).
- Arbitrary messages: main agent interprets intent → (a) which files/changes to review, (b) what review angle. If scope unclear, ask user.
- No diff → "No changes to review." → stop.
- Apply dispatch strategy based on diff size.

### Step 2 — Launch subagents

Use `task` tool with `subagent_type: "general"`. **Launch all in parallel** in one message. Default 3 subagents unless overridden by `sub=N`.

Each subagent prompt MUST include:

1. Diff (full or domain slice).
2. Original task description (intended goal).
3. Review focus (if specified).
4. If multi-domain: brief note about other domains' key interfaces.

Subagent prompt template:

```
You are an independent code reviewer. Find real bugs, logic errors, and missing edge cases — not style nits.

Explore the codebase (read, grep, glob) to verify claims before reporting. Do not guess.

## Task

Original goal: <what the change intends to accomplish>

Review focus: <general / performance / security / etc. — or "general" if none specified>

<If multi-domain:> You are reviewing the <domain name> domain. Other changed domains: <list other domains and their key files/interfaces>.

Diff:
<diff content>

## Review checklist

- Correctness: logic errors, off-by-one, wrong variable names?
- Completeness: edge cases, error paths, missed callers?
- Consistency: follows existing patterns in surrounding code?
- Safety: security issues, leaked secrets, destructive ops?
- Side effects: breaks other callers, tests, downstream?
- Cross-domain (if applicable): interfaces between this domain and other changed domains still compatible?

If user-specified focus exists, weight findings in that area more heavily.

## Output format

One line per finding, caveman-review style:

- `<file>:L<line>: 🔴 bug: <problem>. <fix>.`
- `<file>:L<line>: 🟡 risk: <problem>. <fix>.`
- `<file>:L<line>: 🔵 nit: <problem>. <fix>.`
- `<file>:L<line>: ❓ q: <genuine question>.`

If no issues: output "PASS: safe to ship."

If you explored to verify a concern and found no issue: state "Verified: no issue at <location>" — do not leave it ambiguous.
```

### Step 3 — Triage + Report to user

Collect all subagent results. Merge findings, de-duplicate, verify each against code.

**Triage every finding**:

| Finding | Action |
|---------|--------|
| Valid, should fix | Keep. |
| Valid but out of scope | Note for user. Do NOT fix tangential things. |
| Invalid / false positive | Discard (state why). |
| Style preference | Discard, unless contradicts project convention. |

No valid findings remain → skip to Step 5 (PASS). Report out-of-scope notes to user as informational.

Present findings to user BEFORE applying any fix:

```markdown
## Cross-Check Result: FAIL

### Changes Reviewed (N subagents)
- <list of files changed>

### Issues Found
- 🔴 L<line>: <description>. Suggested fix: <concrete suggestion>
- 🟡 L<line>: <description>. Suggested fix: <concrete suggestion>

Apply fixes? (fix / no / revise)
```

Use `question` tool. Wait for user decision.

### Step 4 — Fix (or not)

| Decision | Action |
|----------|--------|
| fix | Apply fixes, then re-run from Step 1. |
| no | Proceed to Step 5. |
| revise | Discuss and adjust, then re-present findings via Step 3. If code changes, re-verify from Step 1. |

After fixes, always re-verify from Step 1 — fixes can introduce new problems.

### Step 5 — Final result

**If PASS (no valid findings):**

```markdown
## Cross-Check Result: PASS

### Changes Reviewed (N subagents)
- <list of files changed>

### Result
- No issues found
- <one sentence verdict>
```

**If issues were found and resolved/skipped:**

```markdown
## Cross-Check Complete

### Changes Reviewed (N subagents)
- <list of files changed>

### Result
- All issues resolved / N issues skipped by user
- <one sentence verdict>
```

No decision prompt in final result.

## Constraints

- **Default 3 subagents**: Overridden by `sub=N` in user message. More for large diffs. Domains < count → assign extra to largest domain or fall back to full-diff review.
- **Parallel launch**: All subagents in one message, never sequential.
- **No editing during review**: Collect diff, launch reviews, then act on findings.
- **Report before fixing**: Always show findings to user first. User decides.
- **Max 2 re-verify rounds**: Track rounds. After 2, report remaining issues. Do not loop.
- **Explore, don't guess**: Subagents must use tools to verify claims.
- **Independent review**: Subagents get diff + review criteria only — no bias from main agent.
- **User-facing output**: Follow user's language preference.