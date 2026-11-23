---
name: update-agents-md
description: Propose targeted AGENTS.md changes for review and write only the selected change.
disable-model-invocation: true
---

# Update AGENTS.md

Use for explicit requests to update or create `AGENTS.md` (including `update-agents-md` or `c=<N>` invocations) and replies to an active proposal. Propose one coherent change per candidate, even across sections. Show only changed parts of the target file. Get explicit authorization after showing the diff before writing.

## Build the queue

1. Parse and remove `c=<N>` from a fresh request or queue rebuild. `N` must be a positive integer. Invalid value → explain in one sentence and stop. Continuation options without a new `c=` retain the active mode and queue.
2. Queue distinct rules from explicit arguments. Without arguments, look for recurring corrections, conventions, and preferences in the conversation. If explicit arguments yield fewer than `N` passing candidates, fill vacancies from those observations.
3. Inspect relevant codebase conventions. Choose and read the owning `AGENTS.md` before drafting. Apply the Admission Gate before showing each candidate. Keep unused candidates and overflow internal unless asked.

## Admission Gate

Pick the nearest existing `AGENTS.md` that owns the convention. Use the repo root for repo-wide rules and the already visible governing global file for global rules. If the owning file is missing, propose creating it. Determine ownership by scope, never by cwd alone. Use visible files for global scope and skip recursive `$HOME` searches.

| Check | Rule |
|---|---|
| Durable | Require a concrete convention for future sessions. Drop generic advice and session-only leftovers. An explicit change request can waive this check alone. |
| Novel | Drop rules already covered by the target file or a skill that owns the workflow. |
| Consistent | Resolve a conflict by editing the existing clause in place. |
| Actionable | Use one imperative an agent can follow directly. Rewrite or drop vague candidates. |
| Placed | Draft the diff against the selected owning file. |

## Propose

Without `c`, show exactly one passing candidate. With `c=<N>`, show up to `N` passing candidates as full diffs. If fewer pass, show only those. Number from 1 with short imperative titles and list every displayed number in the prompt. End the reply at the prompt unless the latest request selects a write or asks to omit confirmation. Omitting the prompt alone grants no write permission.

Without `c`:

````
```diff
<diff content>
```
Reason: <one short sentence>

Confirm: write? (revise / next / yes)
````

With `c=<N>`:

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

## Continue

| Reply | Action |
|---|---|
| `revise` | Edit the active candidate or the candidates clearly targeted on the page. If the request targets the whole page, edit every candidate. `revise <k>` targets one candidate. Reapply the gate to edited candidates. On failure, name the check in one sentence and show a passing rewrite, or retain the previous candidate if the user insists on a form that still fails. Gate and queue independent extra rules, adding them to the page only if a slot is free. Renumber after drops and reprint the active template. |
| `next` | Skip the current unwritten candidate or page. After a write, start with the other unwritten candidates on that page, then take overflow. Gate candidates as you go and show the next single candidate or page of up to `N`. When exhausted, say `No remaining AGENTS.md change.` Include the last failing check if any. Reuse skipped, rejected by the gate, or written candidates only on request. |
| `yes` | In single mode, write the active candidate. If no proposal is active, start at Build the queue and stop at the proposal. In page mode, say `Pick a candidate number.` and repeat the prompt. |
| `1` … `<n>` | In page mode, write only the numbered candidate. With no active page or an out-of-range number, explain in one sentence and repeat the prompt if a proposal is active. |
| Explicit write authorization | Apply the active single diff or the explicitly named candidate on a page. A page requires a number even if the user waives confirmation. |

Treat free-text rejection as `revise` if it specifies changes, otherwise as `next`. Both operations only reprint a proposal. Apply only the selected diff within the target file. After a write, stop and retain other unwritten candidates for a later `next`.
