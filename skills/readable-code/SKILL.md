---
name: readable-code
description: Use whenever writing or modifying code.
---

# Readable code

Optimize for a maintainer reading and changing the code. Prefer spacious layout and explanatory comments over compact, minimally commented code. Apply this within the requested scope, following language idioms and project conventions.

## Code

- Use names that explain domain meaning, actions, and units. Give complex conditions and intermediate results meaningful names.
- Write straightforward control flow. Expand nested ternaries, dense chains, and multi-action expressions into clear steps. Keep state changes and failure paths visible; use guard clauses where they reduce nesting.
- Keep one coherent responsibility per function. Extract helpers for meaningful operations, not to meet an arbitrary line limit. Keep related logic together and introduce abstractions only for current needs.
- Use spacious layout: separate distinct operations onto their own lines and logical phases with blank lines. Use consistent structure for similar branches and the project's formatter for layout details.

## Comments

- Add comments before non-obvious logic explaining intent, assumptions, invariants, units, or tradeoffs. For multi-phase routines, add short section comments explaining each phase's purpose; explain complex algorithms when names alone are insufficient.
- Document callable interfaces whose contracts are not evident from their signatures, including relevant side effects and failure behavior.
- Keep comments synchronized with changes and useful beyond restating statements. Write them in English unless the file has a clear non-English convention.

## Final check

Before finishing, reread the changed code: can a maintainer follow the main path, understand the reasoning, and find state changes and failure cases without mentally unpacking dense expressions? Simplify or explain unclear parts. Preserve behavior unless the task changes it, and verify according to risk.
