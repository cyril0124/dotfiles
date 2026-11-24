---
name: cross-check
description: Use when asked to cross-check changes just made by the current agent.
disable-model-invocation: true
---

# Cross-Check

Recent changes → independent orthogonal review → triage → report → user decision → fix → re-verify.

Use after code changes, before declaring done, or for "cross-check", "review changes", "check my changes", "审查改动", "交叉检查". Do not use for unrelated existing PR reviews or exploration without changes.

## Inputs

| Input | Scope | Focus / budget |
|-------|-------|----------------|
| None | Agent's edits this conversation only | General; auto budget |
| `cross-check HEAD~3..HEAD` | `git diff <range>` | General; auto budget |
| `cross-check src/foo.ts` | Uncommitted changes in those files | General; auto budget |
| `cross-check 刚才改的认证逻辑` | Main agent infers files/changes | Main agent infers angle |
| `cross-check 性能问题` | Main agent infers scope | Focus/Safety prioritizes performance |
| `cross-check sub=5` | Same scope rules | Budget 5 |

Exclude pre-existing dirty state by default; use conversation history to isolate the agent's own edits.

## Reviewers

`sub=N` is a budget for distinct lens+diff-slice assignments, never N clones. It overrides the defaults. Explicit `sub=0` alone permits main-agent-only review; report `Subagents: 0 (forced)`.

| Diff | Default budget |
|------|----------------|
| Tiny: ~1 file, ≲50 changed lines, single concern | 1 independent Correctness reviewer on the full diff |
| Normal: one coherent concern | 3: base lenses below |
| Large / multi-domain | `max(3, domain count)`; one per domain first, leftovers deepen |

| # | Lens | Checklist |
|---|------|-----------|
| 1 | Correctness | Logic, edge cases, error paths, original goal |
| 2 | Regression | Callers, tests, interfaces, adjacent behavior |
| 3 | Focus/Safety | User focus; otherwise security, data loss, destructive operations, secrets |
| 4 | Goal-gap | Why locally correct changes could miss the goal |
| 5 | Hotpath | Repeated work, large allocations, hot-path waste |
| 6+ | Deepen largest remaining risk | Alternate Goal-gap/Hotpath-style probes with distinct prompts |

Assignment:
- One coherent concern: assign lenses 1..N; every reviewer gets the full diff.
- Multiple domains: group files by concern (logic, tests, config, UI, docs), assign one reviewer per domain up to N, defaulting to Correctness; merge trivially small domains into adjacent ones.
- Leftover budget: deepen the largest domain/full diff with the next unused lens. Never duplicate lens+slice.
- Tiny diffs still require one independent reviewer unless the user explicitly set `sub=0`.

## Workflow

### 1. Collect diff and intent

Determine scope, focus, and budget. For arbitrary messages, infer files/changes and angle; ask if scope remains unclear. No diff → `No changes to review.` and stop. With explicit `sub=0`, skip Step 2 and review directly using Step 3's report format. Put user focus in Focus/Safety and sort valid focused findings before general ones.

### 2. Launch reviewers in parallel

Use the runtime's most general code-review-capable delegation tool/agent type (`Agent`, `Task`, `general-purpose`, or equivalent). Launch all reviewers in one message. Give each only its assigned lens/checklist, its diff slice, the original goal, any user focus, and other domains' key interfaces. Do not pass suspected findings.

Prompt template:

```text
You are an independent code reviewer. Lens: <Correctness|Regression|Focus/Safety|Goal-gap|Hotpath>.
Find real issues in this lens only: no style nits or other lenses.
Verify claims with read/search tools. Do not guess.

## Task
Original goal: <intended accomplishment>
User focus: <angle or "none">
Lens: <lens name>
Lens checklist:
<only this lens's checklist below>
<If multi-domain:> Domain: <domain>. Other changed domains: <list + key interfaces>.
Diff:
<diff content>

## Output
One compact block per finding:

### F-001 <Critical|Major|Minor>: <short title> (`path/to/file.ext:<line>`)
Problem: <evidence-based technical problem>
Plain: <plain-language consequence>
Evidence: <path:line + short original snippet>
Fix: <smallest focused fix; unified diff if short and safe>

Severity:
- Critical: security risk, data loss, crash, broken core behavior, production-blocking.
- Major: real bug, incorrect behavior, significant maintainability or performance issue.
- Minor: meaningful small correctness edge case or low-risk maintainability issue; skip pure style.

Rules:
- Sequential IDs per reviewer: F-001, F-002, ...
- Every finding needs path:line evidence; no padding or invented findings.
- No issues: `PASS: safe to ship for lens <name>.`
- Explored concern without an issue: `Verified: no issue at <location>`.
```

Lens checklists:
- **Correctness:** Logic errors, off-by-one, wrong variables/branches? Edge cases/error paths? Original goal achieved?
- **Regression:** Other callers broken? Tests outdated/missing? Adjacent and cross-domain interfaces/contracts compatible?
- **Focus/Safety:** Prioritize user focus; otherwise secrets, injection, authz, data loss, destructive operations, unsafe defaults.
- **Goal-gap:** Missing wiring, half-migrated call sites, flags, config, or docs-only gaps that defeat the goal?
- **Hotpath:** Repeated computation, large allocations, N+1, unbounded loops, blocking request-path calls?

### 3. Triage and report

Merge reviewer/main-agent results, de-duplicate, and verify every finding against code.

| Finding | Action |
|---------|--------|
| Valid, in scope | Keep; reassess `Critical`/`Major`/`Minor` |
| Valid, out of scope | Note; do not fix |
| Invalid/false positive | Discard with reason |
| Style preference | Discard unless it violates project convention |

No valid findings → Step 5 (PASS); still report out-of-scope notes as informational.

🔴 **CHECKPOINT:** report findings before edits. Required FAIL format:

````md
## Cross-Check Result: FAIL

Subagents: <N> · Lenses: <list> · Round: <R>

**Reviewed Content Summary**
<concise plain-language summary of changed behavior>

### R-001 <Critical|Major|Minor>: <short title> (`path/to/file.ext:<line>`)

#### Problem
<evidence-based technical problem>

#### Plain Explanation
<middle-school-level, jargon-free consequence>

#### Fix
<why this resolves it>

```diff
--- a/path/to/file.ext
+++ b/path/to/file.ext
@@ -<old_line>,<old_count> +<new_line>,<new_count> @@
-<old code>
+<new code>
```

#### Evidence
<path:line + relevant original snippet>

## Summary

| ID | Severity | One-liner |
|----|----------|-----------|
| R-001 | Critical | <problem only> |
| R-002 | Major | <problem only> |

Confirm: apply fixes? (fix / no)
````

Report rules:
- Sequential zero-padded `R-00N` IDs in report order; heading exactly `### R-00N <severity>: <title> (\`path:line\`)`.
- Every kept issue needs Problem, Plain Explanation, Fix, Evidence. Use unified diffs with `@@` line numbers; if no safe fix, explain and omit the patch.
- Summary lists every issue in ID order. Optional `### Notes` holds one bullet per discarded/out-of-scope item, outside Summary.
- End FAIL reports with the exact `Confirm:` line. Do not use structured question tools. Wait for explicit chat reply `fix` or `no`; do not edit first.

### 4. Decide and re-verify

| Reply | Action |
|-------|--------|
| `fix` | Apply fixes, restart at Step 1 |
| `no` | Go to Step 5 |

Re-verification may shrink to the lenses owning fixed issues, but retains ≥1 independent reviewer unless explicit `sub=0`. Maximum 2 re-verify rounds; then report remaining issues instead of looping.

### 5. Final result

PASS (no valid findings):

```md
## Cross-Check Result: PASS

No issues found.
Reviewed Content Summary: <concise plain-language summary>
Reviewed: <file list>
Subagents: <N> · Lenses: <list> · Round: <R>
```

COMPLETE (issues resolved/skipped, after re-verify or user `no`):

```md
## Cross-Check Result: COMPLETE

Reviewed Content Summary: <concise plain-language summary>
Reviewed: <file list>
Subagents: <N> · Lenses: <list> · Round: <R>

### Result
- Fixed: <R-00x list or "none">
- Skipped by user: <R-00x list or "none">
- Remaining after max rounds: <R-00x list or "none">

Verdict: <one sentence>
```

After maximum rounds, re-emit remaining issues under COMPLETE using the full R-ID Problem/Plain Explanation/Fix/Evidence format and Summary table before Verdict. Final results have no decision prompt.

## Failure branches

| Trigger | Action |
|---------|--------|
| Own edits cannot be isolated from dirty state | Ask for exact files/range; do not guess |
| `git diff`/range resolution fails | Report failing command/error and stop; never invent a diff |
| Requested path has no matching diff | `No changes to review for <path>.`; stop without reviewers |
| Reviewer launch/result fails or times out | Mark incomplete, name failed reviewer/lens, ask retry vs partial results |
| Reviewer lacks file/line/evidence | Verify manually; discard if evidence cannot be found |
| Reviewers disagree | Re-check code; keep only evidence-backed conclusions |
| Fix causes new failures | Report remaining issues after max rounds; do not loop silently |

## Invariants

- Review only requested changes; never unrelated dirty files.
- Preserve independent review: distinct lens+slice assignments; no clones, sequential launches, or reviewer bias from suspected bugs.
- Each reviewer receives only its lens checklist and must verify claims with tools.
- Review is read-only until the user's explicit fix decision.
- Skip pure style unless project convention makes it a real finding.
- Never claim PASS after a failed reviewer when the user declined retry.
- Main-agent-only review requires explicit `sub=0`, reported as forced.
- User-facing reports follow the user's language and the required headers, R-IDs, fields, Summary, lens list, and fix decision.
