---
name: update-agents-md
description: "Propose one AGENTS.md change and write only after confirmation. Manual only. Trigger on: update-agents-md, $update-agents-md, or revise/next/yes after a proposal."
---

# Update AGENTS.md

Propose a single coherent change to AGENTS.md and write only after explicit user confirmation.

## TL;DR

```
Understand intent → Pick target AGENTS.md → Gate candidate → Propose one diff → Confirm: write? (revise / next / yes)
```

## When to use

- User wants to update or create AGENTS.md.
- User says "update AGENTS.md", "add rule to AGENTS.md", "修改规则文件".
- User says `revise`, `next`, or `yes` after this skill has an active proposal.

## When not to use

- General coding tasks not involving AGENTS.md.
- Reading AGENTS.md for context (just read it directly).

## Workflow

### Step 1 — Understand intent

- **With arguments**: Use the user's explicit request as the change intent. If the request contains multiple distinct rules, queue them as remaining candidates and propose the first that passes the Admission Gate. An explicit request overrides only the Durable check.
- **Without arguments**: Scan conversation history for recurring patterns worth codifying — conventions the user repeatedly enforced, corrections the user made more than once, implicit preferences surfaced during the session. Synthesize concrete, actionable rules from these observations. Queue all unused candidates. Do not propose a candidate until it passes the Admission Gate.

Then:
- Inspect the codebase structure, conventions, and patterns.
- Choose the target AGENTS.md first (see Admission Gate). Read that file; if it does not exist, treat as create-after-confirm.
- Run every queued candidate through the Admission Gate before proposing.
- Keep unused candidates that still pass or have not been gated in an internal remaining queue for `next`. Do not print the queue.

### Step 2 — Propose one change

- Propose only a candidate that passed the Admission Gate.

- Propose **exactly one** coherent change (may span multiple lines/sections).
- Show proposal in exactly one fenced code block using the `diff` language tag.
- Provide one short reason: `Reason: <one short sentence>`.
- End with the exact confirmation line unless the latest request already selects `yes` or asks for no confirmation.

Reply template:

````
```diff
<diff content>
```
Reason: <one short sentence>

Confirm: write? (revise / next / yes)
````

### Step 3 — Continue only on a named option

- Do **not** modify AGENTS.md until the latest request selects `yes` or otherwise explicitly agrees to write.
- `revise`, `next`, and `yes` are defined below.

## CHECKPOINT

STOP after printing the proposal. Continue only when the latest request contains:

- `revise`: incorporate the user's requested changes and reprint the complete one-change proposal (diff + reason + confirmation line). Do not write.
- `next`: discard the current unwritten proposal; propose the next remaining candidate as a fresh Step 2 reply. After a successful `yes`, propose the next remaining candidate the same way. If the remaining queue is empty, say so in one sentence and stop. Do not write.
- `yes`: write the latest proposed change to AGENTS.md, then stop. Do not auto-advance. Remaining candidates stay queued for a later `next`.
- No-confirmation wording that also authorizes writing: write the latest proposal and stop.

If the user rejects in free text without naming an option, treat it as `revise` when they specify changes, otherwise treat it as `next`.

## Revise Option

1. Treat `revise` as edit-and-reprint only. Do not write.
2. Apply the user's requested changes to the latest proposal. Keep it one coherent change.
3. Re-run the Admission Gate. If the revised text fails, say the failing check in one sentence and reprint a passing rewrite — or the previous proposal if the user insisted on a failing form they did not explicitly override.
4. Reprint the full Step 2 template, including the confirmation line.
5. If the requested change would become a second independent rule, keep the current proposal focused and queue the extra rule for `next` after gating it.

## Next Option

1. Treat `next` as skip-or-advance only. Do not write.
2. Drop the current unwritten proposal from the queue (it was skipped). After a `yes`, the written item is already consumed; just take the next unused candidate.
3. Walk the remaining queue through the Admission Gate. Skip failing candidates without proposing them.
4. Propose the next passing candidate with a fresh Step 2 reply.
5. If no passing candidate remains, say `No remaining AGENTS.md change.` and the last failing check if one existed, then stop.
6. Do not recycle a skipped, failed-gate, or already-written proposal unless the user asks to bring it back.

## Yes Option

1. Write only the latest proposed change. Do not rewrite the whole file.
2. Stop after the write. Do not propose the next change unless the user then says `next`.
3. If no latest proposal exists, return to Step 1 and stop at the checkpoint.

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

- One proposal per reply — no multiple options or full rewrites.
- No silent writes — always propose first, write only on `yes` or explicit agreement.
- Propose only what changes; do not rewrite the entire file.
- Keep the remaining queue internal. Do not list upcoming candidates unless the user asks.

## Common pitfalls

- **Writing without asking**: Never skip the proposal step.
- **Proposing too much**: One coherent change, not a full redesign.
- **Ignoring existing content**: Always read the chosen AGENTS.md first; build on what exists.
- **Skipping the gate**: Never propose a candidate that failed Durable / Novel / Consistent / Actionable / Placed.
- **Wrong file**: Do not dump a local convention into a global AGENTS.md, or the reverse.
- **Sibling on conflict**: Clash → edit the old clause. Do not append a contradicting bullet.
- **Auto-advancing after write**: `yes` stops. `next` is the only way to propose the next change.
- **Losing the queue**: Unused observations stay queued until written, skipped, or the session ends.
