---
name: update-agents-md
description: "Propose updates to AGENTS.md in the current workdir after user confirmation. Use when user asks to update AGENTS.md, modify project rules, add conventions, or mentions 'AGENTS.md', 'update agents', '修改规则', '更新规则'."
---

# Update AGENTS.md

Propose a single coherent change to AGENTS.md and write only after explicit user confirmation.

## TL;DR

```
Understand intent → Examine codebase & existing AGENTS.md → Propose one diff → User confirms → Write
```

## When to use

- User wants to update or create AGENTS.md.
- User says "update AGENTS.md", "add rule to AGENTS.md", "修改规则文件".

## When not to use

- General coding tasks not involving AGENTS.md.
- Reading AGENTS.md for context (just read it directly).

## Workflow

### Step 1 — Understand intent

- **With arguments**: Use the user's explicit request as the change intent.
- **Without arguments**: Scan conversation history for recurring patterns worth codifying — conventions the user repeatedly enforced, corrections the user made more than once, implicit preferences surfaced during the session. Synthesize one concrete, actionable rule from these observations. Do not propose trivial or obvious rules.

Then:
- Inspect the codebase structure, conventions, and patterns.
- Read existing AGENTS.md if present; if absent, treat as create-after-confirm.

### Step 2 — Propose one change

- Propose **exactly one** coherent change (may span multiple lines/sections).
- Show proposal in exactly one fenced code block using the `diff` language tag.
- Provide one short reason: `Reason: <one short sentence>`.
- Ask exactly: `Write this to AGENTS.md?`

Reply template:

````
```diff
<diff content>
```
Reason: <one short sentence>

Write this to AGENTS.md?
````

### Step 3 — Write only after confirmation

- Do **not** modify AGENTS.md until user explicitly agrees.
- If user rejects or requests changes, return to Step 2.

## Constraints

- One proposal per reply — no multiple options or full rewrites.
- No silent writes — always propose first, write after confirmation.
- Propose only what changes; do not rewrite the entire file.

## Common pitfalls

- **Writing without asking**: Never skip the proposal step.
- **Proposing too much**: One coherent change, not a full redesign.
- **Ignoring existing content**: Always read current AGENTS.md first; build on what exists.