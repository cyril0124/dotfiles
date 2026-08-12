---
name: commit-stage
description: "Validate staged git changes and commit them safely after staged-scope, security, correctness, readability/maintainability, and documentation-drift review. Trigger on: 'commit-stage', 'commit staged', 'review and commit', '提交暂存区', '检查并提交'. Do not use for general git operations or review-only requests without staged-change commit intent."
---

# Commit-Stage

Validate staged git changes and commit only when review passes. During initial review, never modify files, stage files, or widen commit scope.

## TL;DR

```
git status --short + git diff --cached → staged-scope gate → security/correctness/readability-maintainability/doc drift review → final staged-boundary check → commit or report failure
```

## When to use

- User wants to commit staged changes.
- User says "commit-stage", "review and commit", "提交暂存区", "检查并提交".

## When not to use

- General git ops without staged-change review intent.
- Review-only requests where the user does not want a commit.
- Creating, editing, formatting, or staging files.

## Workflow

### Step 1 — Inspect staged changes

Run both commands before review:

```bash
git status --short
git diff --cached
```

If `git diff --cached` is empty → report `Nothing staged for commit.` and stop.
If unstaged or untracked files exist → keep them out of scope; do not inspect them unless needed only as read-only context for the staged diff.
If `./AGENTS.md` or `./CLAUDE.md` exists → read every existing file before review and treat its instructions as constraints on the staged content.

### Step 2 — Line-by-line review

Review every staged line. Do not assume correctness. Apply these gates in order:

1. **Scope gate** — confirm every finding and the eventual commit message refer only to staged content.
2. **Project constraints gate** — when `./AGENTS.md` or `./CLAUDE.md` exists, verify every staged change complies with all applicable instructions in those files.
3. **Security/privacy gate** — stop immediately for staged secrets, credentials, `.env` values, private keys, tokens, personal data, internal hosts/IPs, user absolute paths, machine-local cache/build paths, or staged logs/caches/build outputs.
4. **Correctness gate** — inspect behavior, tests, interfaces, and regressions line by line.
5. **Readability/maintainability gate** — stop only for material maintainability damage in the staged diff (see below). Pure style preference is not a stop.
6. **Documentation drift gate** — compare staged behavior/interface/command changes against tracked markdown.

Look for:

- Logic errors, off-by-one, missing error handling
- Wrong variable names, broken assumptions, race conditions
- API misuse, regressions, behavior-breaking changes
- Security/privacy leaks from the security/privacy gate
- Missing tests for non-trivial behavior changes
- **Material maintainability damage**: misleading names, deep nesting / oversized new logic, dead code, incomplete refactors, non-obvious critical logic with no explanation (see below)
- Commented-out debug left in the staged diff
- **Documentation drift**: repository `.md` files that describe changed behavior/interfaces/commands but were not updated in this commit (see below)

#### Readability / maintainability check

Correctness asks "is the behavior right?". This gate asks "will a later reader struggle to keep it right?". Scope is staged lines only; judge against surrounding code as read-only context.

**Stop (Related or Unclear) when the staged diff introduces material damage:**

- **Misleading names** — identifiers whose names contradict role, type, or side effects (not mere taste).
- **Hard-to-follow structure** — staged addition of deep nesting, very long functions/blocks, or tangled control flow that a later reader cannot scan without re-deriving intent.
- **Dead or leftover code** — unreachable code, unused imports/vars introduced by the diff, or commented-out debug/experiments left staged.
- **Incomplete refactor** — rename/move/extract half-done: old and new paths both present, callers not updated, or temporary shims that should not ship.
- **Opaque critical logic** — non-obvious algorithm, invariant, or protocol handling with no nearby comment or clear structure that explains *why*.

**Do not stop for pure style preference:**

- Brace/indent taste, import order, line-wrapping, quote style, trailing commas
- Naming that is merely different from reviewer taste but still accurate
- Missing comments on obvious code
- "I would have written it differently" without a concrete maintainability failure

Whitespace errors remain under the final `git diff --cached --check` boundary, not this gate.

Classify:

- Clear material damage → **Related** (stop, provide complete fix diff).
- Suspect material damage but evidence incomplete → **Unclear** (stop, state location + one-sentence reason).
- Style-only preference → ignore for commit decision (do not report as Related).

Need context? Inspect nearby code/files as read-only context. Do not guess.
Suspected behavior bug? Reproduce it before confirming when a focused, safe check exists; otherwise classify as **Unclear** and stop.

#### Documentation drift check

1. **Collect candidates** — run `git ls-files '*.md'` to list all tracked markdown files. Always include `./AGENTS.md` and `./CLAUDE.md` when they exist.
2. **Exclude already-staged .md** — if a `.md` is part of the staged changes, treat it as "user already covered"; only verify its sync completeness, do not suggest additional edits beyond what was staged.
3. **Semantic judgment** — for each candidate, determine whether it describes behavior, interfaces, CLI flags, configuration keys, commands, or workflows that the staged diff modifies. A mere lexical mention without semantic conflict (e.g., internal refactor that does not change public behavior) does **not** constitute drift.
4. **Agent rule files** — if `./AGENTS.md` or `./CLAUDE.md` exists, always judge whether the staged diff adds or changes agent conventions, workflows, constraints, or commands those files should document. Stale or missing guidance is documentation drift.
5. **Classify**:
   - High confidence the doc is stale → **Related** (stop commit, provide diff fix).
   - Uncertain whether the doc needs updating → **Unclear** (stop commit, state location + one-sentence reason, do not force a diff).
6. **Failure report label** — prefix the Problem section with `Documentation drift: <file path>` so the user can immediately distinguish doc issues from code bugs.

### Step 2.5 — Parallel subagent review (when warranted)

When the review workload is large (many staged files, many candidate `.md` files, or both), split the work into atomic subtasks and delegate to parallel subagents. Use this explicit trigger: delegate when staged review would exceed the current context budget, when there are more than 5 staged files, or when there are more than 8 plausible documentation candidates. Do **not** split trivially small reviews.

Subagents are advisory and read-only: they must not edit files, stage files, create commits, or write artifacts.

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
evidence: <staged diff line, markdown section, or command output>
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
- [ ] Current-directory AGENTS.md/CLAUDE.md constraints and update need checked
- [ ] Correctness/regression risks checked
- [ ] Security/privacy leaks checked
- [ ] Material readability/maintainability risks checked
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

### Step 5 — Final staged-boundary check

Before committing, rerun:

```bash
git status --short
git diff --cached --check
git diff --cached
```

Stop if the final staged diff differs materially from the reviewed diff, if whitespace errors are reported, or if the commit would require staging additional files.

### Step 6 — Success path

No material problems found after the final staged-boundary check:

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
- [ ] Current-directory AGENTS.md/CLAUDE.md constraints and update need checked
- [ ] Correctness/regression risks checked
- [ ] Security/privacy leaks checked
- [ ] Material readability/maintainability risks checked
- [ ] Related documentation drift checked
- [ ] Commit scope boundary checked

## Commit Message
`<type>: <description>`

## Summary
- <short bullet summarizing why this commit was made>
- <optional short bullet for notable scope or boundary>
```

## Follow-up options

Append this prompt to any stopped result that includes a suggested fix:

```text
Confirm: next action? (fix / fr (fix-recommit) / skip)
```

| Option | Meaning |
|---|---|
| `fix` | Leave commit-stage review and apply the suggested fix only. Do not stage or commit. |
| `fr` | Fix-recommit: run `fix`, stage only the files changed by that fix, then restart the full commit-stage workflow from Step 1. |
| `skip` | Ignore only the currently reported finding(s). Mark them as acknowledged for this run, then continue the remaining commit-stage workflow. Do not edit files. Later gates or later findings still stop as usual; `skip` is not a blanket pass. |

Do not append follow-up options when there is nothing staged, when the final boundary check changed, or when no reliable fix can be proposed.

## Constraints

- **No file modifications during initial review**: do not edit, create, format, or patch source files unless the user chooses `fix` or `fr` after a stopped result.
- **No staging**: do not run `git add`, `git restore --staged`, or any command that changes the index unless explicitly asked by `fr` or a direct user request.
- **No scope widening**: commit only what was reviewed in the staged diff.
- **No .md artifacts**: report failures in chat only.
- **No hidden success path**: if a check cannot run or evidence is insufficient, stop as **Unclear** instead of committing.
- All user-facing chat output in **Chinese**.

## Failure Modes

| Trigger | Action |
|---|---|
| `git diff --cached` is empty | Stop with `Nothing staged for commit.` |
| Staged secret/privacy leak is found | Stop as **Related**, explain the leak type, and provide a removal diff |
| Staged material maintainability damage is found | Stop as **Related** or **Unclear** under the readability/maintainability rules |
| Staged behavior changes but docs may be stale | Stop as **Related** or **Unclear** under the documentation drift rules |
| Reproduction/check command is unsafe, too broad, or unavailable | Stop as **Unclear**; do not commit on assumption |
| Final staged diff differs from reviewed diff | Stop and ask the user to rerun commit-stage after restaging |
| `git diff --cached --check` reports whitespace errors | Stop and report the exact command output |

## Anti-Patterns

- Do not commit first and review afterward.
- Do not fix issues directly during initial review; provide a diff recommendation instead.
- Do not stage documentation updates even when they are obviously needed.
- Do not treat subagent findings as final without main-agent reclassification.
- Do not ignore unstaged files by pretending they were reviewed; state that they are out of commit scope.
- Do not use vague approvals like "looks fine" without checklist evidence.
- Do not stop the commit for pure style preference; only material maintainability damage blocks.
