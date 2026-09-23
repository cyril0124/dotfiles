---
name: readable-code
description: Use whenever writing, modifying, or reviewing code, including naming, comments, layout, and hardcoded values.
---

# Readable code

Optimize for a maintainer reading and changing the code: someone arriving with no memory of how it was written. Prefer spacious, explicit code over compact code. Apply this within the requested scope, following language idioms and project conventions.

## Naming

- Use names that state the domain meaning, the action, and the unit.
- Give complex conditions and intermediate results meaningful names.
- Treat a misleading name as a defect: rename it rather than documenting around it. A name that needs a sentence of comment to be understood is the wrong name.
- Give parallel operations parallel names. Similar behavior under different names reads as different behavior, and sends the reader looking for a difference that is not there.

## Structure

- Write straightforward control flow. Expand nested ternaries, dense chains, and multi-action expressions into clear steps. Keep state changes and failure paths visible; use guard clauses where they reduce nesting.
- Keep one coherent responsibility per function. Extract helpers for meaningful operations, not to meet an arbitrary line limit.
- Call the primitive directly. A helper that only forwards arguments, or that renames a framework call, adds a name to learn without adding a capability.
- Keep related logic together, and introduce abstractions only for current needs.
- Use spacious layout: separate distinct operations onto their own lines, and separate logical phases with blank lines. Line count is not the cost you are minimizing; the reader's scan is. Use consistent structure for similar branches and the project's formatter for layout details.

## Values

- Keep values that vary by environment, caller, or deployment out of the body: identifiers, paths, names, colors, sizes. Take them from the caller or from configuration, so the same code serves the next environment.
- Reuse the configuration surface that already exists. A dedicated variable or knob invented for one value moves the coupling rather than removing it.

## Comments

- Add comments before non-obvious logic explaining intent, assumptions, invariants, units, or tradeoffs. For multi-phase routines, add short section comments explaining each phase's purpose; explain complex algorithms when names alone are insufficient.
- Delete comments that restate the code or expose internal mechanics the reader does not need. A test case's comment describes the scenario it verifies, not the logic that makes the check pass.
- Skip decorative markers that carry no information: "Part 1", "Step 2", a file header listing the obvious.
- Annotate types at callable boundaries wherever the language supports it, naming the concrete domain type rather than a generic container.
- Document callable interfaces whose contracts are not evident from their signatures, including relevant side effects and failure behavior.
- Keep comments synchronized with changes, and useful beyond restating statements.
- Use one comment language throughout a file. A file with an established non-English convention keeps it; a file opens in one language and continues in it.

## Consistency

- Match the surrounding code: one construct takes one form in the file you are editing, in sibling files of the same kind, and across the project's test cases.
- Treat the neighbouring implementation as the template, ahead of an idea of how the code should read. The repository is the convention.
- When a change touches several files of one kind, give them one section structure and one header shape.

## Final check

Before finishing, reread the changed code: can a maintainer follow the main path, understand the reasoning, and find state changes and failure cases without mentally unpacking dense expressions? Simplify or explain unclear parts. Preserve behavior unless the task changes it, and verify according to risk.
