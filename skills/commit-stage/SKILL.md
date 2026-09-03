---
name: commit-stage
description: "Review staged git changes, then commit if they pass. Trigger on: 'commit-stage', 'commit staged', 'review and commit', '提交暂存区', '检查并提交'. Skip general git ops, and skip reviews that do not ask for a commit."
---

# Commit-stage

Review the staged git changes. Commit only if that review passes. On the first pass, do not edit files, stage files, or add extra files to the commit.

## TL;DR

```
git status --short + git diff --cached → temp-file gate → staged-scope gate → security/correctness/readability-maintainability/doc drift review → final staged-boundary check → commit or report failure
```

## When to use

- The user wants to commit staged changes.
- The user says "commit-stage", "review and commit", "提交暂存区", or "检查并提交".

## When not to use

- Ordinary git work with no intent to review and commit the staged diff.
- Review-only requests. The user does not want a commit.
- Creating, editing, formatting, or staging files.

## Workflow

### Step 1. Inspect staged changes

Run both commands before review:

```bash
git status --short
git diff --cached --name-only
git diff --cached
```

If `git diff --cached` is empty, report `Nothing staged for commit.` and stop.

### Step 1.5. Temp-file gate

Match every staged filename from `git diff --cached --name-only` against temporary-file patterns:

- Editor/system junk: `*.swp`, `*~`, `*.bak`, `*.orig`, `*.rej`, `.DS_Store`, `Thumbs.db`
- Tool temp output: `*.tmp`, `*.temp`, `*.log`, `*.out`, `*.cache`, `*.pid`
- Scratch and debug artifacts: `tmp/`, `temp/`, `scratch/`, `*.draft.*`, `* - copy`, `* - 副本`, `debug_*`
- Build/dep output: `node_modules/`, `dist/`, `build/`, `target/`, `__pycache__/`, `*.o`, `*.pyc`

A match stops the commit as **Related**. Report the filename and the pattern it hit. Suggested fix: unstage the file (`git restore --staged <file>`) and, if the pattern can recur, add it to `.gitignore`. A staged file whose name only resembles a pattern is not a match. Judge by its actual content and role.
Unstaged and untracked files stay out of the commit. Read them only when the staged diff is unreadable without that context.
If `./AGENTS.md` or `./CLAUDE.md` exists, read each one before review. The staged content has to follow them.

### Step 2. Line-by-line review

Review every staged line. Do not assume it is correct. Run these gates in order:

1. **Scope gate.** Every finding and the commit message must point at staged content only.
2. **Project constraints gate.** If `./AGENTS.md` or `./CLAUDE.md` exists, check that every staged change follows the applicable rules in those files.
3. **Security/privacy gate.** Stop at once for staged secrets, credentials, `.env` values, private keys, tokens, personal data, internal hosts/IPs, user absolute paths, machine-local cache/build paths, or staged logs, caches, or build outputs. The Step 1.5 temp-file gate covers filenames. This gate covers file contents.
4. **Correctness gate.** Walk behavior, tests, interfaces, and regressions line by line.
5. **Readability/maintainability gate.** Stop only for real maintainability damage in the staged diff. Style preference is not a stop.
6. **Documentation drift gate.** Match staged behavior, interface, and command changes against tracked markdown.

Look for:

- Logic errors, off-by-one, missing error handling
- Wrong variable names, broken assumptions, race conditions
- API misuse, regressions, behavior-breaking changes
- Missing tests for non-trivial behavior changes
- **Real maintainability damage.** Misleading names, deep nesting or oversized new logic, dead code, incomplete refactors, non-obvious critical logic with no explanation, production residue. Details below.
- Commented-out debug left in the staged diff
- **Documentation drift.** Tracked `.md` files that describe changed behavior, interfaces, or commands but were not updated in this commit. Details below.

#### Readability / maintainability check

Correctness asks "is the behavior right?". This gate asks "will a later reader struggle to keep it right?". Scope is staged lines only. Surrounding code is read-only context.

Stop when the staged diff actually makes the code harder to keep:

- **Misleading names.** Identifiers that contradict role, type, or side effects. Taste does not count.
- **Hard-to-follow structure.** The staged addition is deeply nested, a very long function or block, or tangled control flow. A later reader has to reverse-engineer intent just to scan it.
- **Dead or leftover code.** Unreachable code, unused imports or vars the diff introduced, or commented-out debug and experiments left staged.
- **Incomplete refactor.** Rename, move, or extract is half-done. Old and new paths both present, callers not updated, or temporary shims that should not ship.
- **Opaque critical logic.** A non-obvious algorithm, invariant, or protocol with no nearby comment or structure that says why.
- **Production residue.** Comments or docs that only make sense to people in the authoring conversation: `as requested`, `changed per the user`, `we no longer use Y`, `the previous version was wrong`, `this document assumes...`, a TODO pointing at one debugging session. A comment records why the code is this way, not how it came to be written.

Do not stop for pure style preference:

- Brace or indent taste, import order, line-wrapping, quote style, trailing commas
- Naming that is merely different from reviewer taste but still accurate
- Missing comments on obvious code
- "I would have written it differently" with no concrete maintainability failure

Whitespace errors belong to the final `git diff --cached --check` boundary, not this gate.

Classify:

- Clear real damage → **Related**. Stop and give a complete fix diff.
- Suspect real damage but evidence is incomplete → **Unclear**. Stop. Give the location and one sentence why.
- Style-only preference → ignore for the commit decision. Do not report it as Related.

If you need context, read nearby code. Do not guess.
If you suspect a behavior bug, reproduce it when a focused, safe check exists. If you cannot, mark it **Unclear** and stop.

#### Documentation drift check

1. **Collect candidates.** Run `git ls-files '*.md'` for tracked markdown. Always include `./AGENTS.md` and `./CLAUDE.md` when they exist.
2. **Skip already-staged .md.** If a `.md` is already in the staged changes, the user already included it. Check that the staged markdown actually matches the code change. Do not suggest extra edits beyond the staged file.
3. **Judge meaning, not words.** For each candidate, ask whether it describes behavior, interfaces, CLI flags, configuration keys, commands, or workflows that the staged diff changes. If the doc's meaning still matches the code, a shared word is not drift. An internal refactor that does not change public behavior is not drift.
4. **Agent rule files.** If `./AGENTS.md` or `./CLAUDE.md` exists, check whether the staged diff adds or changes agent conventions, workflows, constraints, or commands those files should document. Stale or missing guidance is documentation drift.
5. **Classify.**
   - You are sure the doc is stale → **Related**. Stop the commit and give a diff fix.
   - You are not sure the doc needs updating → **Unclear**. Stop the commit. Give the location and one sentence why. Do not force a diff.
6. **Failure report label.** Start the Problem section with `Documentation drift: <file path>` so the user can tell a doc issue from a code bug.

### Step 2.5. Split a large review

Split into parallel subagents when the review would blow the current context budget, when more than 5 files are staged, or when more than 8 docs look relevant. Do not split a small review.

Subagents advise. They do not edit, stage, commit, or write artifacts.

**Splitting rules:**

| Dimension | Unit |
|---|---|
| Code review | One staged file = one subtask |
| Documentation drift | One candidate `.md` = one subtask |

**Give every subagent:**

- The full staged diff (`git diff --cached`).
- An identifier list. Before splitting, extract from the diff every public-facing identifier: exported API names, CLI commands/flags, configuration keys, environment variables, command paths, behavioral keywords. Without that list a subagent only sees one file and will miss a renamed API.

**Subagent output contract:**

```
classification: Related | Unrelated | Unclear
kind: Code | DocumentationDrift
location: <file:line or file:section>
evidence: <staged diff line, markdown section, or command output>
problem: <one-sentence>
reason: <short explanation>
suggested_fix: <diff block or "N/A">
```

**How you close the review:**

1. Collect every subagent result.
2. Deduplicate by location and problem summary.
3. Re-classify each finding yourself. Subagent labels are advice, not the call.
4. Check identifier coverage. Every item in the identifier list must have been examined by at least one subagent. If not, do a targeted follow-up for the ones nobody touched.
5. Make the final commit or stop decision.

### Step 3. Classify findings

| Classification | Action |
|---|---|
| **Related** to staged changes | Stop. Do not commit. |
| **Unrelated** | Continue. Say in chat that it is outside the staged diff. |
| **Unclear** | Stop. Prefer a false positive over a false negative. |

### Step 4. Failure path

When stopping:

1. Report in chat only. Do not write a .md file.
2. State the problem, how it relates to the staged changes, and why.
3. Give a complete `diff`-formatted fix in a fenced code block. The whole patch, not a fragment.
4. If you cannot propose a reliable fix, say that.

Failure output format:

```markdown
## Result
Commit stopped.

## Plain Explanation
<1-2 short sentences a stranger to this repo would get, about 50 characters. What went wrong, and who it hits.>

## Review Checklist
- [ ] Staged diff reviewed line by line
- [ ] Temporary files checked at the filename level (Step 1.5)
- [ ] Current-directory AGENTS.md/CLAUDE.md constraints and update need checked
- [ ] Correctness/regression risks checked
- [ ] Security/privacy leaks checked
- [ ] Material readability/maintainability risks checked
- [ ] Related documentation drift checked
- [ ] Commit scope boundary checked

## Problem
<what you found. For documentation drift, prefix with "Documentation drift: <path>">

## Reason
<short explanation>

## Suggested Fix
````diff
<complete diff recommendation>
````
```

### Step 5. Final staged-boundary check

Before committing, rerun:

```bash
git status --short
git diff --cached --check
git diff --cached
```

Stop if the final staged diff is not the one you reviewed, if whitespace errors are reported, or if the commit would need extra files staged.

### Step 6. Success path

Nothing that should stop the commit after the final staged-boundary check:

Before writing the commit message, apply this contamination gate:

- Derive the message from the staged diff and codebase domain only.
- Remove process references to the prompt author or conversation: prompts, user requests, turns, reviews, debugging sessions, failed attempts, or implementation constraints.
- Keep the technical change and its engineering reason. A test-related change is valid when the staged diff actually adds or changes tests.
- If the staged diff does not support an accurate message, stop and ask instead of inventing process wording.

- Write a conventional commit: `<type>: <description>`.
- Treat a user hint as intent, not as wording. Rewrite it in the codebase's language.
- No hint → infer from the staged changes.
- Describe **what** changed and **why** from the codebase's point of view. Never mention prompts, conversation, requests, review rounds, or trial-and-error.
- Commit only staged content. Leave unstaged changes alone.

| Bad | Better |
|---|---|
| `fix: fix bug per user request` | `fix: resolve null pointer when user profile is missing` |
| `chore: try a few approaches until tests pass` | `refactor: simplify session cache lookup` |
| `feat: implement X (avoided Y as asked)` | `feat: implement X using native storage API` |
| `refactor: clean up after debugging` | `refactor: remove temporary logging and unused helpers` |

Success output format:

```markdown
## Result
Commit created.

## Plain Explanation
<1-2 short sentences a stranger to this repo would get, about 50 characters. What changed, and what the user will notice.>

## Review Checklist
- [ ] Staged diff reviewed line by line
- [ ] Temporary files checked at the filename level (Step 1.5)
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
| `skip` | Ignore only the currently reported finding(s). Mark them as acknowledged for this run, then continue the remaining commit-stage workflow. Do not edit files. Later gates or later findings still stop as usual. `skip` is not a blanket pass. |

Do not append follow-up options when there is nothing staged, when the final boundary check changed, or when no reliable fix can be proposed.

## Writing rules

These apply to the commit message, all chat output, and any suggested doc fix, in whatever language the output uses.

- No em dashes. End the sentence or use a comma.
- Cut filler and stock phrases: "it is worth noting that", "overall", "aims to", "the future looks bright", "hope this helps".
- Active voice. Name the actor. "queries are validated" becomes "the compiler validates queries".
- State the mechanism or a number, not a feeling. "performance improves noticeably" becomes "one less DB round trip per query".
- One idea per sentence. Split anything the reader has to re-read.
- Suggested doc fixes use the document's own standing voice for its readers, not a changelog line like "this commit adds X".

## Constraints

- **No file modifications during the first review.** Do not edit, create, format, or patch source files unless the user chooses `fix` or `fr` after a stopped result.
- **No staging.** Do not run `git add`, `git restore --staged`, or any command that changes the index unless `fr` or a direct user request says so.
- **No extra files.** Commit only what was reviewed in the staged diff.
- **No .md artifacts.** Report failures in chat only.
- **No hidden success path.** If a check cannot run or evidence is thin, stop as **Unclear**. Do not commit on a missing check.
- All user-facing chat output in **Chinese**.

## Failure modes

| Trigger | Action |
|---|---|
| `git diff --cached` is empty | Stop with `Nothing staged for commit.` |
| Staged filename matches a temporary-file pattern | Stop as **Related**, name the file and pattern, suggest `git restore --staged` plus a `.gitignore` entry |
| Staged secret/privacy leak is found | Stop as **Related**, explain the leak type, and provide a removal diff |
| Staged maintainability damage is found | Stop as **Related** or **Unclear** under the readability/maintainability rules |
| Staged behavior changes but docs may be stale | Stop as **Related** or **Unclear** under the documentation drift rules |
| Reproduction/check command is unsafe, too broad, or unavailable | Stop as **Unclear**. Do not commit on assumption. |
| Final staged diff differs from reviewed diff | Stop and ask the user to rerun commit-stage after restaging |
| `git diff --cached --check` reports whitespace errors | Stop and report the exact command output |

## Anti-patterns

- Do not commit first and review afterward.
- Do not fix issues during the first review. Give a diff recommendation instead.
- Do not stage documentation updates even when they are obviously needed.
- Do not treat subagent findings as final without reclassifying them yourself.
- Do not ignore unstaged files by pretending they were reviewed. Say they are out of commit scope.
- Do not use vague approvals like "looks fine" without checklist evidence.
- Do not let conversation leftovers survive as code comments or doc disclaimers. A constraint shows up in the implementation and the wording. It is not announced.
- Do not stop the commit for pure style preference. Only real maintainability damage blocks.
