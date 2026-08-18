---
name: update-agents-md
description: "Propose AGENTS.md change(s) and write only after confirmation. Manual only. Trigger on: update-agents-md, $update-agents-md, c=<N>, a candidate number after c=<N>, or revise/next/yes after a proposal."
---

# Update AGENTS.md

Propose a single coherent change to AGENTS.md and write only after explicit user confirmation.

## TL;DR

```
Understand intent (optional c=<N>) → Pick target AGENTS.md → Gate candidates → Propose (one diff, or N diffs when c=<N>) → Confirm
```

## When to use

- User wants to update or create AGENTS.md.
- User says "update AGENTS.md", "add rule to AGENTS.md", "修改规则文件".
- User says `c=<N>` to prepare and print N passing candidates as full diffs.
- User says `revise`, `next`, or `yes` after this skill has an active proposal.
- User says a candidate number after a `c=<N>` proposal to write that diff.

## When not to use

- General coding tasks not involving AGENTS.md.
- Reading AGENTS.md for context (just read it directly).

## Workflow

### Step 1 — Understand intent

Parse optional `c=<N>` from the latest request and strip it from the change intent before drafting. `N` is a positive integer meaning: after the Admission Gate, prepare at most `N` passing candidates and print all of them as full diffs. If fewer pass, print only those. Omit `c` → one-diff mode: no cap on the internal remaining queue. If `c` is present but not a positive integer, say so in one sentence and stop.

Honor `c=<N>` only when building or rebuilding the queue (a fresh start, or a request that is not solely `revise` / `next` / `yes` / a candidate number). Named options without a new `c=` keep the existing page or queue.

- **With arguments**: Use the user's explicit request as the change intent. If the request contains multiple distinct rules, queue them as remaining candidates. An explicit request overrides only the Durable check. If `c=<N>` is set and the explicit request yields fewer than `N` passing candidates, fill the remaining slots from conversation observations that pass the Admission Gate.
- **Without arguments**: Scan conversation history for recurring patterns worth codifying — conventions the user repeatedly enforced, corrections the user made more than once, implicit preferences surfaced during the session. Synthesize concrete, actionable rules from these observations. Queue unused passing candidates. When `c=<N>` is set, print at most `N` and keep overflow in the remaining queue; when `c` is omitted, keep the unused queue internal for `next`. Do not propose a candidate until it passes the Admission Gate.

Then:
- Inspect the codebase structure, conventions, and patterns.
- Choose the target AGENTS.md first (see Admission Gate). Read that file; if it does not exist, treat as create-after-confirm.
- Run every queued candidate through the Admission Gate before proposing. When `c=<N>` is set, stop filling the printed page once `N` passing candidates are collected. Overflow stays in the internal remaining queue.
- Without `c`, keep unused passing candidates in an internal remaining queue for `next`. Do not print that queue.

### Step 2 — Propose

- Propose only candidates that passed the Admission Gate.
- Each candidate is **exactly one** coherent change (may span multiple lines/sections).
- Each change is a fenced code block using the `diff` language tag.
- End with the matching confirmation line unless the latest request already selects a write or asks for no confirmation.

Without `c` — print exactly one candidate:

````
```diff
<diff content>
```
Reason: <one short sentence>

Confirm: write? (revise / next / yes)
````

With `c=<N>` — print every passing candidate on this page (at most `N`). Number from 1. Title is one short imperative. No `Reason:` line. List every shown number on the confirmation line:

````
## 1  <short title>
```diff
<diff content>
```

## 2  <short title>
```diff
<diff content>
```

Confirm: write which? (1 / 2 / … / <n> / revise)
````

### Step 3 — Continue only on a named option

- Do **not** modify AGENTS.md until the latest request selects a write.
- Without `c`: `revise`, `next`, and `yes` are defined below.
- With `c=<N>`: a candidate number writes that diff; `revise` and `next` are defined below. Bare `yes` does not write.

## CHECKPOINT

STOP after printing the proposal. Continue only when the latest request contains:

- `revise`: incorporate the user's requested changes and reprint the same Step 2 template that is active (one-diff, or the full `c=<N>` page). Do not write.
- `next`: discard the current unwritten proposal or page; propose the next remaining candidate (one-diff mode) or the next page of up to `N` (c= mode) as a fresh Step 2 reply. After a successful write, take the next unused candidate or page the same way. If nothing remains, say so in one sentence and stop. Do not write.
- `yes`: one-diff mode only. Write the latest proposed change to AGENTS.md, then stop. Do not auto-advance. Remaining candidates stay queued for a later `next`.
- A candidate number (`1` … `<n>`): `c=<N>` page only. Write that numbered diff, then stop. Do not auto-advance. Other unwritten candidates on the page stay queued for a later `next`. Out of range or a number when no `c=<N>` page is active: say so in one sentence and reprint the confirmation line. Do not write.
- Bare `yes` while a `c=<N>` page is active: say `Pick a candidate number.` and reprint the confirmation line. Do not write.
- No-confirmation wording that also authorizes writing: write the latest one-diff proposal, or the named candidate on a `c=<N>` page, then stop. If a `c=<N>` page is active and no number is named, do not write.

If the user rejects in free text without naming an option, treat it as `revise` when they specify changes, otherwise treat it as `next`.

## Revise Option

1. Treat `revise` as edit-and-reprint only. Do not write.
2. One-diff mode: apply the user's requested changes to the latest proposal. Keep it one coherent change.
3. `c=<N>` page: `revise <k>` edits candidate `k`. Bare `revise` edits every candidate the requested changes clearly target; if that is still the whole page, edit the whole page. Keep each candidate one coherent change. Renumber 1…n after any drop.
4. Re-run the Admission Gate on every edited candidate. If a revised text fails, say the failing check in one sentence and reprint a passing rewrite — or the previous text of that candidate if the user insisted on a failing form they did not explicitly override.
5. Reprint the same Step 2 template that is active, including the confirmation line.
6. If the requested change would become a second independent rule, keep the current candidate focused and queue the extra rule for `next` after gating it. On a `c=<N>` page, add it to this page only when a free slot remains under `N`.

## Next Option

1. Treat `next` as skip-or-advance only. Do not write.
2. One-diff mode: drop the current unwritten proposal from the queue (it was skipped). After a `yes`, the written item is already consumed; just take the next unused candidate. Propose the next passing candidate with a fresh one-diff Step 2 reply.
3. `c=<N>` page: drop every currently shown unwritten candidate (this page was skipped). After a numbered write, the written item is already consumed; keep other unwritten candidates from that page. Fill a new page of up to `N` from those leftover unwritten candidates plus unused overflow. Print it with the `c=<N>` Step 2 template.
4. Walk candidates through the Admission Gate. Skip failing candidates without proposing them.
5. If no passing candidate remains, say `No remaining AGENTS.md change.` and the last failing check if one existed, then stop.
6. Do not recycle a skipped, failed-gate, or already-written proposal unless the user asks to bring it back.

## Yes Option

1. One-diff mode only. Write only the latest proposed change. Do not rewrite the whole file.
2. Stop after the write. Do not propose the next change unless the user then says `next`.
3. If no latest proposal exists, return to Step 1 and stop at the checkpoint.
4. If a `c=<N>` page is active, do not write; say `Pick a candidate number.` and reprint the confirmation line.

## Number Option

1. Active `c=<N>` page only. Write only the numbered candidate. Do not rewrite the whole file. Do not write any other candidate on the page.
2. Stop after the write. Do not propose the next page unless the user then says `next`.
3. If no `c=<N>` page is active, or the number is out of range, say so in one sentence and reprint the confirmation line if a proposal is active. Do not write.

## Admission Gate

Choose the target file before drafting a rule:

1. Nearest existing AGENTS.md that owns the convention.
2. Repo-wide convention → repo-root AGENTS.md.
3. User/agent-global convention → the AGENTS.md that already governs this agent. Use files already visible in the session or project; do not recurse from `$HOME`.
4. If none exists, propose creating that owning file. Do not default to cwd just because it is cwd.

A candidate may be proposed only if all of these hold:

| Check | Pass | Fail → |
|---|---|---|
| Durable | Will bind future sessions, not only this task's leftover | Drop. User-explicit request is the only override. |
| Novel | Target AGENTS.md and any skill that already owns this workflow do not already say it | Drop. |
| Consistent | No clash with an existing clause | Do not add a sibling. Propose an edit of the old clause. |
| Actionable | One imperative an agent can follow without interpretation | Rewrite to one imperative, or drop. |
| Placed | Target file is chosen; the diff is against that file | Choose the file first. |

Do not propose generic software advice, a one-off session preference, or a second copy of a rule that already lives in a skill.

## Constraints

- Without `c`: one candidate per reply — no multiple options or full rewrites.
- With `c=<N>`: one page of at most `N` full diffs per reply. Write only the selected number.
- No silent writes — always propose first, write only on `yes`, a candidate number, or explicit agreement that names what to write.
- Propose only what changes; do not rewrite the entire file.
- Without `c`: keep the remaining queue internal. Do not list upcoming candidates unless the user asks.
- With `c=<N>`: print this page only. Do not list overflow beyond `N` unless the user asks.

## Common pitfalls

- **Writing without asking**: Never skip the proposal step.
- **Proposing too much**: One coherent change, not a full redesign.
- **Ignoring existing content**: Always read the chosen AGENTS.md first; build on what exists.
- **Skipping the gate**: Never propose a candidate that failed Durable / Novel / Consistent / Actionable / Placed.
- **Wrong file**: Do not dump a local convention into a global AGENTS.md, or the reverse.
- **Sibling on conflict**: Clash → edit the old clause. Do not append a contradicting bullet.
- **Auto-advancing after write**: `yes` or a candidate number stops. `next` is the only way to propose the next change or page.
- **Losing the queue**: Unused observations stay queued until written, skipped, or the session ends.
- **Ignoring `c=<N>`**: Print every passing candidate on the page (at most `N`). Do not fall back to one-diff mode. Do not treat `c=<N>` as a rule to write into AGENTS.md.
- **Writing the whole page**: A number writes one candidate. Never write all printed diffs because they were shown together.
- **Bare yes on a page**: `yes` without a number does not pick candidate 1.
