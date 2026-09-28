---
name: readable-code
description: Use whenever writing, modifying, or reviewing code, including naming, comments, layout, and hardcoded values.
---

# Readable code

Optimize for a maintainer reading and changing code with no memory of how it was written: spacious and explicit over compact, within requested scope, following language idioms and project conventions.

Repo style doc (`CODE_STYLE.md`, `AGENTS.md`, `CONTRIBUTING.md`) is more specific → outranks this skill. Read it before editing; it settles conflicts.

## Naming

- Names state domain meaning, action, unit.
- Prefer domain + ecosystem term over a coined one: coined names must be learned, conventional ones are already known.
- Give complex conditions + intermediate results meaningful names.
- Misleading name = defect: rename it, do not document around it. A name needing a sentence of comment is the wrong name.
- Parallel operations take parallel names; same behavior under different names reads as different behavior, sending the reader hunting a difference that is not there.
- One concept, one name. Two routines covering one concept under different names = one routine + one deletion.
- Equivalent values take one form; mixed styles for one kind of value read as if they differed.
- Spell out abbreviation at first use, then short form.

## Structure

- Straightforward control flow: expand nested ternaries, dense chains, multi-action expressions into clear steps. Keep state changes + failure paths visible; guard clauses where they cut nesting.
- One responsibility per function. Extract helpers for meaningful operations, not to meet a line limit.
- Call the primitive directly. A helper that only forwards arguments or renames a framework call adds a name to learn, no capability.
- Reuse before adding: extend an existing routine with a parameter, not a near-identical second one. Two entry points for one behavior drift apart.
- Keep related logic together; introduce abstractions only for current needs.
- Spacious layout: distinct operations on their own lines, logical phases separated by blank lines. Reader's scan is the cost, not line count. Similar branches get consistent structure; layout details go to the project formatter.

## Values

- Keep environment-, caller-, or deployment-varying values out of the body: identifiers, paths, names, colors, sizes. Take them from caller or configuration, so the same code serves the next environment.
- Reuse the configuration surface that exists. A variable or knob invented for one value moves the coupling, does not remove it.

## Comments

- Comment non-obvious logic: intent, assumptions, invariants, units, tradeoffs. Multi-phase routines: section comment per phase. Complex algorithms: explain when names alone fall short.
- Delete comments that restate code or expose internal mechanics the reader does not need. A test case's comment describes the scenario it verifies, not the logic that makes the check pass.
- State the observable behavior the code relies on: a comment justifying a check with internal state, a mask, a buffer, or an upstream file and line number describes the implementation, not the protocol- or interface-level fact a reader can see.
- Counts, sizes, offsets, indexes as digits, in comments and prose: digits read as the value, spelled-out numbers read as prose and drift from the code.
- Skip decorative markers carrying no information: "Part 1", "Step 2", a file header listing the obvious.
- Annotate types at callable boundaries where the language supports it: concrete domain type, not a generic container.
- Document callable interfaces whose contracts are not evident from their signatures, including side effects + failure behavior.
- Keep comments in sync with changes, useful beyond restating statements.
- One comment language per file. A file with an established non-English convention keeps it; a file opens in one language and continues in it.

## Consistency

- Match surrounding code: one construct takes one form in the edited file, in sibling files of the same kind, across the project's test cases.
- Treat the neighbouring implementation as the template, ahead of an idea of how code should read: the repository is the convention.
- A change touching several files of one kind gives them one section structure + one header shape.

## Final check

Before finishing, reread the changed code: can a maintainer follow the main path, understand the reasoning, find state changes and failure cases without unpacking dense expressions? Simplify or explain unclear parts. Preserve behavior unless the task changes it; verify according to risk.
