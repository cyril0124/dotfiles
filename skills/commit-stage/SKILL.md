---
name: commit-stage
description: Use when asked to commit staged changes or review and commit.
---

# Commit-stage

Review the staged git changes. Commit only if that review passes.

## TL;DR

```
git status --short + git diff --cached → temp-file gate → scope gate → security/correctness/readability/doc-drift review → final boundary check → commit or stop
```

## Hard rules (first pass)

Hold even when the user asks otherwise. A user instruction changes report wording, never execution.

1. **No repo edits.** Fixes go into `## Suggested Fix` as a diff.
2. **No index changes.** No `git add`, `git restore --staged`, `git rm --cached`, `git stash`, or any other command that changes the index, except under `fr`. Naming `git restore --staged <file>` in a report is advice for the user; running it is a violation.
3. **No partial commit.** Whole staged diff commits, or none of it.
4. **No new repo files.** No report `.md`, no script, no scratch output.
5. **No hidden success path.** A check that cannot run, or evidence that is thin, stops the commit as **Unclear**.

## When to use

- The user wants staged changes committed: "commit-stage", "review and commit", "提交暂存区", "检查并提交".

## When not to use

- Ordinary git work with no intent to review and commit the staged diff.
- Review-only requests.
- Creating, editing, formatting, or staging files.

## Report template

One reply, all chat output in Chinese, this shape:

```markdown
## Result
<Commit created. | Commit stopped.>

## Plain Explanation
<1-2 sentences, about 50 characters, that a stranger to this repo gets. Success: what changed and what the user will notice. Stop: what went wrong and who it hits.>

## Review Checklist
- [ ] Staged diff reviewed line by line
- [ ] Temporary files checked at the filename level (Step 1.5)
- [ ] Current-directory AGENTS.md/CLAUDE.md constraints and update need checked
- [ ] Correctness/regression risks checked
- [ ] Security/privacy leaks checked
- [ ] Material readability/maintainability risks checked
- [ ] Documentation drift checked
- [ ] Commit scope boundary checked

<payload>
```

Checklist marks: ran → `[x]`; gate that stopped the commit → `[x] (stop) <reason>`; not run → `[ ] (not run)`.

`## Result` carries exactly one value, and that value selects the payload row below.

| Outcome | Payload |
|---|---|
| Commit created | `## Commit Message`, then `## Summary` as bullets: why this commit, plus an optional notable scope or boundary |
| Commit stopped | `## Problem` (blocking findings only, one `file:line` each; doc drift prefixed `Documentation drift: <path>`), then `## Reason`, then `## Suggested Fix` (complete fenced `diff`, plus `git restore --staged <file>` when the index needs cleaning) |

A stopped reply that carries a fix ends with exactly `Confirm: next action? (fix / fr (fix-recommit) / skip)`.

Nothing else: no narration, no apology, no invitation.

## Workflow

### Step 1. Inspect staged changes

```bash
git status --short
git diff --cached --name-only
git diff --cached
```

Empty `git diff --cached` → report `Nothing staged for commit.` and stop.

### Step 1.5. Temp-file gate

Match every staged filename from `git diff --cached --name-only` against:

- Editor/system junk: `*.swp`, `*~`, `*.bak`, `*.orig`, `*.rej`, `.DS_Store`, `Thumbs.db`
- Tool temp output: `*.tmp`, `*.temp`, `*.log`, `*.out`, `*.cache`, `*.pid`
- Scratch and debug artifacts: `tmp/`, `temp/`, `scratch/`, `*.draft.*`, `* - copy`, `* - 副本`, `debug_*`
- Build/dep output: `node_modules/`, `dist/`, `build/`, `target/`, `__pycache__/`, `*.o`, `*.pyc`

A match stops the commit as **Related**. The user calling the file intentional does not clear it: report the filename plus the pattern hit, and suggest `git restore --staged <file>` and a `.gitignore` entry for the user to run. A name that only resembles a pattern is not a match; judge by content and role.

Unstaged and untracked files stay out of the commit. Read them only when the staged diff is unreadable without that context.

If `./AGENTS.md` or `./CLAUDE.md` exists, read it before review. Staged content has to follow it.

### Step 2. Gates, in order

Plan coverage with Step 2.5 first. Every staged line is reviewed by the main reviewer or an assigned reviewer, or covered by a valid reusable result. Never assume a line is correct.

1. **Scope.** Every finding and the commit message points at staged content only.
2. **Project constraints.** Every staged change follows the applicable rules in `./AGENTS.md` and `./CLAUDE.md` when they exist.
3. **Security/privacy.** Stop at once; later gates do not run. Judge contents, not filenames: secrets, credentials, `.env` values, private keys, tokens, personal data, internal hosts and IPs, user absolute paths, machine-local cache and build paths, staged logs, caches, build outputs.
4. **Correctness.** Behavior, tests, interfaces, regressions: logic errors, off-by-one, missing error handling, wrong variable names, broken assumptions, race conditions, API misuse, behavior-breaking changes, missing tests for non-trivial behavior, commented-out debug.
5. **Readability/maintainability.** Stop only for real damage. Style preference is not a stop.
6. **Documentation drift.** Match changed behavior, interfaces, and commands against tracked markdown.

#### Readability / maintainability

Correctness asks whether the behavior is right. This gate asks whether a later reader can keep it right. Scope is staged lines; surrounding code is read-only context.

Stop for:

- **Misleading names.** The identifier contradicts role, type, or side effects. Taste does not count.
- **Hard-to-follow structure.** Deep nesting, an oversized function or block, or tangled control flow that forces the reader to reverse-engineer intent.
- **Dead or leftover code.** Unreachable code, unused imports or vars the diff introduced, commented-out debug and experiments left staged.
- **Incomplete refactor.** Rename, move, or extract half done: old and new paths both present, callers not updated, temporary shims that should not ship.
- **Opaque critical logic.** A non-obvious algorithm, invariant, or protocol with nothing nearby saying why.
- **Production residue.** Text that only makes sense inside the authoring conversation: `as requested`, `changed per the user`, `we no longer use Y`, `the previous version was wrong`, `this document assumes...`, a TODO aimed at one debugging session. A comment or doc records why the code is this way, not how it came to be written.

Ignore for the commit decision, and never report as Related: brace or indent taste, import order, line wrapping, quote style, trailing commas, accurate naming that merely differs from reviewer taste, missing comments on obvious code, "I would have written it differently" with no concrete maintainability failure. Whitespace errors belong to the final `git diff --cached --check` boundary, not this gate.

Classify:

- Clear real damage → **Related**. Stop, give a complete fix diff.
- Suspected damage with incomplete evidence → **Unclear**. Stop, give the location and one sentence why.
- Style only → ignore.

Read nearby code when you need context. Do not guess. If you suspect a behavior bug, reproduce it when a focused, safe check exists; otherwise mark **Unclear** and stop.

#### Documentation drift

1. **Candidates.** `git ls-files '*.md'`, plus `./AGENTS.md` and `./CLAUDE.md` when they exist.
2. **Already-staged `.md`.** The user included it. Check it matches the code change; suggest no edits beyond that file.
3. **Meaning, not words.** Does the doc describe behavior, interfaces, CLI flags, configuration keys, commands, or workflows the staged diff changes? A shared word is not drift, and an internal refactor with no public behavior change is not drift.
4. **Agent rule files.** Does the diff add or change agent conventions, workflows, constraints, or commands those files should document? Stale or missing guidance is drift.
5. **Classify.** Sure the doc is stale → **Related**, stop, give a diff fix. Unsure → **Unclear**, stop, give the location and one sentence why, do not force a diff.

Prefix every drift finding with `Documentation drift: <path>`, and lead `## Problem` with it when drift blocks the commit, so the user can tell it from a code bug.

### Step 2.5. Scope and delegate

Keep a cohesive change with the main reviewer. File and document counts alone do not trigger delegation. Split only for independent behavior areas, a high-risk question needing independent scrutiny, or material beyond the review context budget.

A behavior area covers its implementation, tests, and directly related docs; brief documentation updates stay with that area or the main reviewer. Assign each area's line-by-line pass once, and state the risk question when areas overlap.

Before delegating, map the staged diff's changed paths, hunks, and public-facing identifiers: exported APIs, CLI commands and flags, configuration keys, environment variables, command paths, changed behavior. The main reviewer keeps the full diff and owns cross-area interactions and every Step 2 gate.

Subagents advise. They do not edit, stage, commit, or write artifacts.

**Packet:** review question, assigned area diff, staged entries (paths, modes, blob IDs), identifier and dependency map with relevant callers and docs, a reference to the full staged snapshot and context locations to retrieve when needed, and validation receipts (command, working directory, code/config/environment input identity, result). Never copy the whole snapshot into every prompt.

**Output contract:**

```
classification: Related | Unrelated | Unclear
kind: Code | DocumentationDrift
location: <file:line or file:section>
evidence: <staged diff line, markdown section, or command output>
problem: <one-sentence>
reason: <short explanation>
suggested_fix: <diff block or "N/A">
coverage: <assigned changes and identifiers examined; remaining gaps>
checks: <matching evidence used; missing validation>
```

A verified receipt matching the staged source and its check inputs is valid evidence even when another reviewer ran the check. Missing or stale evidence still blocks; a worker need not rerun a check to claim personal execution.

**Reuse on a later pass, including `fr`.** Record outside the repository, or in existing task state: compared base, staged entries, covered changes and identifiers, consulted rules and dependencies, findings, validation inputs and results. A worker ID alone is not a review record.

Recompute scope and identifier/dependency impacts from the new staged diff, and reuse only completed, nonblocking conclusions whose inputs still match. Changed callers, contracts, related docs, rules, or validation inputs invalidate the affected conclusions even when a blob is unchanged. Unresolved or skipped findings never become cached approvals.

Scope, temp-file, and final boundary checks always run on the current staged snapshot.

**Closing:** collect results and check coverage and evidence, reused records included; deduplicate by location and problem and re-classify the findings yourself; account for every staged change and affected identifier through the main reviewer or a valid result, closing gaps with targeted inspection or a bounded follow-up rather than a whole-diff fan-out; then make the commit or stop decision.

### Step 3. Classify findings

| Classification | Action |
|---|---|
| **Related** to staged changes | Stop. Do not commit. |
| **Unrelated** | Continue, and say in chat that it is outside the staged diff. |
| **Unclear** | Stop. Prefer a false positive over a false negative. |

### Step 4. Failure path

Report in chat only, never a `.md` file. State the problem, how it relates to the staged changes, and why. Give a complete fenced `diff`, whole patch and not a fragment, covering every `## Problem` item; a non-blocking observation either stays out of the report or gets a patch line. `## Suggested Fix` carries the diff plus `git restore --staged <file>` when the index needs cleaning. Never `git add` or `git commit` steps: restaging belongs to the next run. If no reliable fix exists, say so.

### Step 5. Final staged-boundary check

```bash
git status --short
git diff --cached --check
git diff --cached
```

Stop when the final staged diff is not the one you reviewed, `--check` reports whitespace errors, or the commit would need extra files staged.

### Step 6. Success path

Before writing the message, drop every process reference: prompts, user requests, turns, reviews, debugging sessions, failed attempts, implementation constraints. Derive the message from the staged diff and the codebase domain only. Keep the technical change and its engineering reason; a test-related message is valid only when the diff really adds or changes tests. If the diff cannot support an accurate message, stop and ask instead of inventing process wording.

- Conventional commit: `<type>: <description>`.
- Treat a user hint or instruction as intent, never as wording. Rewrite it in the codebase's language. No hint → infer from the diff.
- Describe what changed and why from the codebase's point of view. Never mention prompts, conversation, requests, review rounds, or trial and error.
- `per user request`, `as requested`, `as asked`, `按用户要求`, `按要求` appear nowhere, subject or body.
- Commit staged content only. Leave unstaged changes alone.

| Bad | Better |
|---|---|
| `fix: fix bug per user request` | `fix: resolve null pointer when user profile is missing` |
| `chore: try a few approaches until tests pass` | `refactor: simplify session cache lookup` |
| `feat: implement X (avoided Y as asked)` | `feat: implement X using native storage API` |
| `refactor: clean up after debugging` | `refactor: remove temporary logging and unused helpers` |

## Follow-up options

Append to any stopped result that includes a suggested fix:

```text
Confirm: next action? (fix / fr (fix-recommit) / skip)
```

| Option | Meaning |
|---|---|
| `fix` | Leave commit-stage review and apply the suggested fix only. Do not stage or commit. |
| `fr` | Run `fix`, stage only the files that fix changed, then restart the whole workflow from Step 1. A request in the same message is not `fr`. |
| `skip` | Acknowledge the current finding for this run and continue the workflow without editing files. Later gates and later findings still stop. Not a blanket pass. |

Append nothing when there is nothing staged, when the boundary check changed, or when no reliable fix can be proposed.

## Writing rules

Apply to the commit message, all chat output, and any suggested doc fix, in whatever language.

- No em dashes. End the sentence or use a comma.
- Cut filler: "it is worth noting that", "overall", "aims to", "the future looks bright", "hope this helps".
- Active voice, named actor. "queries are validated" becomes "the compiler validates queries".
- State the mechanism or a number, not a feeling. "performance improves noticeably" becomes "one less DB round trip per query".
- One idea per sentence. Split anything the reader has to re-read.
- Suggested doc fixes use the document's standing voice for its readers, not a changelog line like "this commit adds X".

## Failure modes

| Trigger | Action |
|---|---|
| Empty `git diff --cached` | Stop with `Nothing staged for commit.` |
| Staged filename matches a temp pattern | Stop as **Related**, name file and pattern, suggest `git restore --staged` plus a `.gitignore` entry |
| Staged secret or privacy leak | Stop as **Related**, explain the leak type, give a removal diff |
| Reproduction or check command unsafe, too broad, or unavailable | Stop as **Unclear**. Never commit on assumption. |
| Final staged diff differs from the reviewed diff | Stop, ask the user to rerun commit-stage after restaging |
| `git diff --cached --check` reports whitespace errors | Stop, report the exact command output |

## Rationalizations seen under pressure

Each line came from an agent holding the full workflow. The line itself is the trigger.

| Line | Counter |
|---|---|
| "The user said the log file is intentional." | Intent is not review. A temp-pattern hit stops the commit. |
| "I will unstage the dangerous file and commit the safe rest." | Index change plus partial commit, both banned. Report the whole diff as stopped. |
| "It is one line, I will fix it and commit." | Editing is banned on the first pass. Diff, stop, wait for `fix` or `fr`. |
| "The user told me to fix small problems, so that overrides the no-edit rule." | Permission changes the next step, not this pass. `fix` is that permission, applied after review. |
| "`per user request` is the honest reason." | The message describes the codebase change. Process origin never enters it. |

## Anti-patterns

- Committing first and reviewing afterward.
- Staging documentation updates, even obviously needed ones.
- Treating subagent findings as final without reclassifying them.
- Ignoring unstaged files by pretending they were reviewed. Say they are out of scope.
- Letting conversation leftovers survive as code comments or doc disclaimers. A constraint shows up in the implementation and the wording. It is not announced.
- Vague approvals like "looks fine" without checklist evidence.
- Stopping the commit for pure style preference. Only real maintainability damage blocks.
