---
name: cross-check
description: "Launch parallel subagents to review recent changes after code modification. Trigger on: 'cross-check', 'review changes', 'check my changes', '审查改动', '交叉检查', 'review my work'. Do not use for general PR review — only for reviewing changes just made by the current agent."
---

# Cross-Check

Orthogonal-lens review of recent changes → triage → report → user decides → fix & re-verify.

## TL;DR

```
Collect diff + parse intent → Assign orthogonal lenses (budget N) → Parallel review → Triage → Report → User decides → Fix & re-verify
```

`sub=N` is a **budget**, not a clone count. Never launch N identical reviewers.

## When to use

- After code changes, before declaring done.
- User says "cross-check", "review changes", "check my changes", "审查改动", "交叉检查".

## When not to use

- Existing PR review unrelated to recent local changes.
- Code exploration without changes to verify.

## Input resolution

| Input | Scope | Focus / budget |
|-------|-------|----------------|
| No arguments | Agent's own edits this session | General; auto budget |
| Commit range: `cross-check HEAD~3..HEAD` | `git diff <range>` | General; auto budget |
| File paths: `cross-check src/foo.ts` | Uncommitted changes for those files | General; auto budget |
| Arbitrary message: `cross-check 刚才改的认证逻辑` | Main agent parses files/changes | Main agent parses review angle |
| Message with angle: `cross-check 性能问题` | Main agent parses scope | That angle becomes the Focus/Safety lens priority |
| Subagent count: `cross-check sub=5` | Same scope logic | Budget N instead of auto |

Default (no arguments): scope to **only changes agent made in this conversation** — exclude pre-existing dirty state. Use conversation history to determine actual scope.

## Dispatch strategy

### Budget

| Diff size | Default budget (no `sub=N`) |
|-----------|-----------------------------|
| Tiny: ~1 file and ≲50 changed lines, single concern | **1** — one independent Correctness subagent (never self-review own edits by default) |
| Normal: one coherent concern | **3** — one agent per base lens |
| Large / multi-domain | **max(3, domain count)** — one agent per domain first; leftover budget deepens |

`sub=N` overrides the default budget. `sub=0` forces main-agent-only review — only when the user explicitly sets it; report must state `Subagents: 0 (forced)`.

### Orthogonal lenses (never clone)

Base lenses, in fill order:

| # | Lens | Looks for |
|---|------|-----------|
| 1 | **Correctness** | Logic errors, edge cases, error paths, goal not met |
| 2 | **Regression** | Callers, tests, interface compatibility, adjacent behavior broken |
| 3 | **Focus/Safety** | User-specified angle if any; else security, data loss, destructive ops, secrets |

Deepening lenses (only when budget > base lenses already assigned):

| # | Lens | Looks for |
|---|------|-----------|
| 4 | **Goal-gap** | Why the change might fail the original goal despite looking correct |
| 5 | **Hotpath** | Unnecessary work, repeated computation, large allocs on hot paths |
| 6+ | Repeat deepen on **largest remaining risk surface** (biggest domain / hottest file), alternating Goal-gap and Hotpath-style probes — still a distinct prompt, never a clone of Correctness |

### Assignment rules

```
budget N
  → if multi-domain: assign 1 agent per domain (up to N)
  → remaining slots: fill orthogonal lenses on full diff or on largest domain
  → never assign two agents the same lens + same diff slice
```

| Shape | Strategy |
|-------|----------|
| Tiny + no `sub=N` | 1 Correctness subagent on full diff. Never skip independence for own edits. |
| Tiny + explicit `sub=0` | Main agent only. Skip Step 2. Report `Subagents: 0 (forced)`. |
| One coherent concern | N agents, lenses 1..N from the tables above, each gets **full diff** |
| Multiple independent concerns | Partition by domain; 1 agent per domain; leftover budget deepens largest domain with next unused lens |
| Trivially small domain | Merge into adjacent domain |

Domain partition (large diffs):

1. Group touched files by concern (logic, tests, config, UI, docs).
2. One agent per domain (lens defaults to Correctness unless budget allows more).
3. Trivially small domains merge into adjacent domain.

## Workflow

### Step 1 — Collect diff + parse intent

- Determine scope, review focus, and budget (see Input resolution + Dispatch).
- Arbitrary messages: main agent interprets intent → (a) which files/changes, (b) review angle. If scope unclear, ask user.
- No diff → "No changes to review." → stop.
- Explicit `sub=0` only → main agent reviews with this skill's user-facing report format; go to Step 3 (no subagents). State `Subagents: 0 (forced)` in the report. Default tiny diffs still launch 1 independent subagent.

If user specifies a review focus, put that angle in the Focus/Safety lens and sort valid findings in that focus before general findings.

### Step 2 — Launch subagents

Skip only when user explicitly set `sub=0`.

Use the runtime's subagent/delegation tool (`Agent`, `Task`, `task`, or equivalent). Select the most general code-review-capable agent type available (`general-purpose`, `general`, or equivalent). **Launch all in parallel** in one message.

Each subagent prompt MUST include:

1. Assigned **lens name** and that lens's checklist only (not the full multi-lens list).
2. Diff (full or domain slice).
3. Original task description (intended goal).
4. User review focus, if any.
5. If multi-domain: brief note about other domains' key interfaces.

Subagent prompt template:

```
You are an independent code reviewer. Lens: <Correctness|Regression|Focus/Safety|Goal-gap|Hotpath>.
Find real issues in this lens only — not style nits, not other lenses.

Explore the codebase with available read/search tools to verify claims before reporting. Do not guess.

## Task

Original goal: <what the change intends to accomplish>

User focus (if any): <angle or "none">

Lens: <lens name>
Lens checklist:
<only the bullets for this lens — see Lens checklists below>

<If multi-domain:> Domain under review: <domain>. Other changed domains: <list + key interfaces>.

Diff:
<diff content>

## Output format

One compact block per finding:

### F-001 <Critical|Major|Minor>: <short title> (`path/to/file.ext:<line>`)
Problem: <technical problem based on evidence>
Plain: <plain-language consequence, no jargon>
Evidence: <path:line + short original snippet>
Fix: <smallest focused fix idea; unified diff if short and safe>

Severity:
- Critical: security risk, data loss, crash, broken core behavior, production-blocking.
- Major: real bug, incorrect behavior, significant maintainability or performance issue.
- Minor: small correctness edge case or low-risk maintainability — only if it matters; skip pure style.

Rules:
- Assign sequential IDs per subagent: F-001, F-002, ...
- Stay inside your lens. Do not pad with other-lens findings.
- Every finding needs path:line evidence. No evidence → do not report.
- Do not invent findings to fill the report.
- If no issues in this lens: output `PASS: safe to ship for lens <name>.`
- If you explored a concern and found no issue: `Verified: no issue at <location>`.
```

#### Lens checklists

**Correctness**
- Logic errors, off-by-one, wrong variables/branches?
- Edge cases and error paths covered?
- Does the change actually accomplish the original goal?

**Regression**
- Other callers broken?
- Tests outdated or missing for the new behavior?
- Interfaces / contracts with adjacent code still compatible?
- Cross-domain interfaces still line up (if multi-domain)?

**Focus/Safety**
- If user focus set: weight that angle first.
- Else: secrets, injection, authz, data loss, destructive ops, unsafe defaults.

**Goal-gap**
- What would make this change fail its stated goal even if the diff looks locally correct?
- Missing wiring, half-migrated call sites, feature flags, config, docs-only gaps?

**Hotpath**
- Unnecessary work, repeated computation, large allocations on hot paths?
- N+1, unbounded loops, blocking calls in request path?

### Step 3 — Triage + Report to user

Collect all reviewer results (subagents and/or main-agent direct review). Merge findings, de-duplicate, verify each against code.

**Triage every finding**:

| Finding | Action |
|---------|--------|
| Valid, should fix | Keep. Re-assign final severity (`Critical` / `Major` / `Minor`) if needed. |
| Valid but out of scope | Note for user. Do NOT fix tangential things. |
| Invalid / false positive | Discard (state why). |
| Style preference | Discard, unless contradicts project convention. |

No valid findings remain → skip to Step 5 (PASS). Report out-of-scope notes to user as informational.

🔴 CHECKPOINT — STOP before edits. Present findings to user BEFORE applying any fix.

**User-facing report format** (IDs, sections, summary table). Wrap with a Cross-Check header and end with the fix decision:

````md
## Cross-Check Result: FAIL

Subagents: <N> · Lenses: <list> · Round: <R>

**Reviewed Content Summary**
<what the changed code does, in a concise plain-language summary.>

### R-001 <Critical|Major|Minor>: <short title> (`path/to/file.ext:<line>`)

#### Problem
<technical problem description based on the evidence.>

#### Plain Explanation
<same issue explained so a middle school student can understand it, using simple non-jargon language.>

#### Fix
<why this fix resolves the issue.>

```diff
--- a/path/to/file.ext
+++ b/path/to/file.ext
@@ -<old_line>,<old_count> +<new_line>,<new_count> @@
-<old code>
+<new code>
```

#### Evidence
<file path and line number plus the relevant original snippet.>

## Summary

| ID | Severity | One-liner |
|----|----------|-----------|
| R-001 | Critical | <one-line problem> |
| R-002 | Major | <one-line problem> |

Apply fixes? (fix / no)
````

Rules:
- Assign sequential IDs: `R-001`, `R-002`, ... (zero-padded, report order).
- Heading: `### R-00N <severity>: <title> (\`path:line\`)`.
- Every kept issue needs Problem, Plain Explanation, Fix, Evidence.
- Code fixes use unified diff with `@@` line numbers; if no safe fix, say why and omit the patch.
- Summary table lists every reported issue in ID order; One-liner is problem only.
- Discarded / out-of-scope items: one short bullet each under an optional `### Notes` section — not in the Summary table.

Use the runtime's user-question tool (`ask_user_question`, `question`, or equivalent). If no structured question tool exists, ask in plain chat. Wait for an explicit user decision.

### Step 4 — Fix (or not)

| Decision | Action |
|----------|--------|
| fix | Apply fixes, then re-run from Step 1. |
| no | Proceed to Step 5. |

After fixes, always re-verify from Step 1 — fixes can introduce new problems. Re-verify may shrink budget (e.g. only the lens that owned the fixed issues), but still keep ≥1 independent subagent unless the user explicitly set `sub=0`.

### Step 5 — Final result

**If PASS (no valid findings):**

```md
## Cross-Check Result: PASS

No issues found.
Reviewed Content Summary: <what the changed code does, in a concise plain-language summary.>
Reviewed: <file list>
Subagents: <N> · Lenses: <list> · Round: <R>
```

**If issues were found and resolved/skipped (after re-verify or user said no):**

```md
## Cross-Check Result: COMPLETE

Reviewed Content Summary: <what the changed code does, in a concise plain-language summary.>
Reviewed: <file list>
Subagents: <N> · Lenses: <list> · Round: <R>

### Result
- Fixed: <R-00x list or "none">
- Skipped by user: <R-00x list or "none">
- Remaining after max rounds: <R-00x list or "none">

Verdict: <one sentence>
```

If remaining issues still exist after max re-verify rounds, re-emit those issues in this skill's issue format (R-IDs, Problem / Plain Explanation / Fix / Evidence + Summary table) under the COMPLETE header before Verdict.

No decision prompt in final result.

## Failure branches

| Trigger | Action |
|---------|--------|
| Cannot isolate agent's own edits from pre-existing dirty state | Ask user to choose exact files/range before review; do not guess scope. |
| `git diff` or range resolution fails | Report the failing command/error and stop; do not invent a diff. |
| Requested file/path has no matching diff | Say "No changes to review for <path>." and stop without launching subagents. |
| Subagent launch/result fails or times out | Mark review incomplete, report which reviewer/lens failed, and ask user whether to retry or continue with partial results. |
| Subagent output lacks file/line/evidence | Verify manually; discard if evidence cannot be found. |
| Reviewers disagree on a finding | Re-check the referenced code and keep only the evidence-backed conclusion. |
| Fix introduces new failures in re-verify | Report remaining issues after max rounds; do not loop silently. |

## Anti-pattern blacklist

- Do not review unrelated dirty files unless user explicitly includes them.
- Do not launch reviewers sequentially; parallel independence is part of the method.
- Do not launch N clones of the same lens/checklist; `sub=N` is budget for orthogonal lenses.
- Do not pass the main agent's suspected bug list to reviewers; it biases results.
- Do not give every subagent the full multi-lens checklist; each gets only its lens.
- Do not fix anything before the 🔴 CHECKPOINT user decision.
- Do not keep style-only findings unless they violate an existing project convention.
- Do not claim PASS if any reviewer failed and the user chose not to retry.
- Do not self-review the current agent's own edits with budget 0 unless the user explicitly set `sub=0`.

## Constraints

- **Budget, not clones**: Default budget from diff size; override with `sub=N`. Assign distinct lenses (and domain slices). Never duplicate lens+slice.
- **Independence over thrift**: Cross-check may drop lenses; it must not drop independence. Default tiny = 1 independent subagent. Main-agent-only only on explicit `sub=0`, reported as `Subagents: 0 (forced)`.
- **Parallel launch**: All subagents in one message, never sequential.
- **No editing during review**: Collect diff, launch reviews, then act on findings.
- **Report before fixing**: Always show findings to user first. User decides.
- **Max 2 re-verify rounds**: Track rounds. After 2, report remaining issues. Do not loop.
- **Explore, don't guess**: Reviewers must use tools to verify claims.
- **Independent review**: Subagents get diff + their lens only — no bias from main agent.
- **User-facing output**: Follow user's language preference. Final report uses this skill's R-IDs, Problem / Plain Explanation / Fix / Evidence, and Summary table, plus Cross-Check headers, lens list, and the fix decision.
