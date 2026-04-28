---
name: generic-writing
description: "Write in a reusable, context-light way. Use when the user asks for a general solution, abstract wording, reusable guidance, or requests writing that is less coupled to the current task."
---
# Generic Writing
Use this skill when user wants wording that stays portable instead of being tied to current task, repo, file, or framework.

## Workflow
1. **Identify intent** — Default to generic when unclear.
2. **Abstract the context** — Replace concrete names with "this kind of component" / "a typical setup".
3. **Choose presentation** — Answer directly without headings unless asked.
4. **Strip local specifics** — Remove filenames, variable names, one-off configs.
5. **Final check** — Could this answer apply to another project?

## Principles
1. Start from principle, not current implementation.
2. Avoid current file names, tool names, repo details, and one-off workarounds.
3. Do not force extra structure. Answer directly unless user asks for sections.
4. Keep wording reusable. Prefer "this kind of system" over concrete local names.
5. Keep examples short and clearly just examples, not universal rules.

## Edge Cases
| Situation | Response |
| User asks concrete details | Provide but frame as illustrative example |
| Specific tool needed | Use general category first: "container tooling (e.g. Docker)" |
| Project-specific question | Start with principles, note "adapt to your setup" |
| Mixed generic/specific request | Answer generic with principles; flag specifics as one-off |
| User shows their code | Reference as "your code" / "this case", not general advice |

## Examples
> "In our `UserController`, call `findByEmail()`" → "In a typical controller layer, look up by unique identifier"
> "Add `MAX_FILE_SIZE = 10485760` to `config/upload.ts`" → "Set max file size in upload configuration"
> "Run `npm run build && docker compose up -d`" → "Build and start services using project tooling"

## Avoid
- Mixing general advice with current-task details in same sentence.
- Treating one local fix as best practice everywhere.
- Adding headings or format rules that user did not ask for.
