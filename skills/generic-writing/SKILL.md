---
name: generic-writing
description: "Write reusable, context-light guidance. Use for general wording, abstract guidance, reusable templates, portable explanations, or content not tied to the current repo/task. Do not use for exact local commands, file edits, live debugging, or project-specific decisions."
---
# Generic Writing
Turn local or overly concrete wording into portable guidance without losing intent.

## Contract
- Input: request, concrete context, target audience.
- Output: reusable answer, template, or wording.
- Preserve: intent, constraints, audience, risks.
- Remove: repo names, file paths, one-off commands, local identifiers.
- Resources: no external files or scripts required.

## Workflow
1. **Classify scope** — `generic`, `specific`, or `mixed`.
2. **Extract invariant** — Convert facts into category-level concepts.
3. **Choose form** — Use the lightest format: paragraph, short bullets, or template.
4. **Rewrite** — Replace local nouns with role nouns: "the service", "the configuration", "the caller".
5. **Final gate** — Pass only if another similar project can reuse the answer unchanged.

## 🔴 CHECKPOINT
Stop and switch out of this skill when:
- Exact commands, filenames, code changes, or live debugging are requested.
- Generalizing would remove safety, numeric, legal, or compliance constraints.
- Intent is unclear between reusable wording and project-specific action.
Action: answer the specific request, or ask one focused clarification if a generic answer would mislead.

## Failure Modes
| Trigger | Fix | If Still Failing |
|---|---|---|
| Local names remain | Replace with category terms | Mark concrete detail as `Example` |
| One case sounds universal | Add scope: "For this class..." | Remove the claim |
| Wording becomes vague | Add a short pattern | Restore one minimal example |
| User needs local action | Do not generalize | Use project-specific workflow |
| Output gets format-heavy | Collapse to prose | Keep one short example |

## Output Rules
- Start with reusable principle or wording.
- Use headings only when asked or when parts are independent.
- Label concrete details as examples, not rules.
- Prefer categories over brands: "package manager" before "npm".

## Examples
| Local | Reusable |
|---|---|
| "In `UserController`, call `findByEmail()`" | "In the request handler, look up the account by a unique identifier." |
| "Add `MAX_FILE_SIZE` to `config/upload.ts`" | "Define the upload size limit in the upload configuration." |
| "Run `npm run build && docker compose up`" | "Build the project, then start services with project tooling." |

## Anti-Patterns
Do not present a local workaround as general best practice, mix repo-specific and reusable wording in one sentence, strip correctness/safety constraints, add unasked structure, hide uncertainty behind "best practice", or force this skill onto exact local execution.
