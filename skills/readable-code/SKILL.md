---
name: readable-code
description: Use whenever writing, modifying, or reviewing code, including naming, comments, layout, and hardcoded values.
---

# Readable code

Optimize for a maintainer reading and changing code with no memory of how it was written: spacious and explicit over compact, within requested scope, following language idioms and project conventions.

Repo style doc (`CODE_STYLE.md`, `AGENTS.md`, `CONTRIBUTING.md`) is more specific → outranks this skill. Read it before editing; it settles conflicts.

Rules are numbered so a review comment can cite one directly (`violates 20`). Each rule states the observable behavior, and adds the reasoning behind it where the rule is not self-evident.

## Naming

1. Names state domain meaning, action, unit. The reader infers the value or the effect from the name without opening the definition.
2. Prefer domain + ecosystem term over a coined one: coined names must be learned, conventional ones are already known.
3. Give complex conditions + intermediate results meaningful names.
4. Prefix a name only where it competes for a shared namespace: file names, exported symbols, macros, module-level constants. Members, parameters, and locals are already separated by their container and take no prefix. A prefix there repeats the scope, and the reader strips it back off to find the name.
5. Misleading name = defect: rename it, do not document around it. A name needing a sentence of comment is the wrong name.
6. Parallel operations take parallel names; same behavior under different names reads as different behavior, sending the reader hunting a difference that is not there.
7. One concept, one name. Two routines covering one concept under different names = one routine + one deletion.
8. Equivalent values take one form; mixed styles for one kind of value read as if they differed.
9. Spell out abbreviation at first use, then short form.

## Structure

10. Straightforward control flow: expand nested ternaries, dense chains, multi-action expressions into clear steps. Keep state changes + failure paths visible; guard clauses where they cut nesting.
11. One responsibility per function. Extract helpers for meaningful operations, not to meet a line limit.
12. Call the primitive directly. A helper that only forwards arguments or renames a framework call adds a name to learn, no capability.
13. Reuse before adding: extend an existing routine with a parameter, not a near-identical second one. Two entry points for one behavior drift apart.
14. Keep related logic together; introduce abstractions only for current needs. Keep each increment working end to end.
15. Declare the property the toolchain can check: a routine with no side effects is declared as such, and read-only, immutable, or asynchronous intent takes the matching declaration, so the compiler proves it instead of the reader trusting the name. The property is transitive: convert a whole call chain together, and keep the weaker declaration only where language or framework requires it.
16. Spacious layout: distinct operations on their own lines, logical phases separated by blank lines. Reader's scan is the cost, not line count. Similar branches get consistent structure; layout details go to the project formatter.

## Values

17. Keep environment-, caller-, or deployment-varying values out of the body: identifiers, paths, names, colors, sizes. Take them from caller or configuration, so the same code serves the next environment.
18. Reuse the configuration surface that exists. A variable or knob invented for one value moves the coupling, does not remove it.

## Comments

19. Comment non-obvious logic: intent, assumptions, invariants, units, tradeoffs. Multi-phase routines: section comment per phase. Complex algorithms: explain when names alone fall short.
20. Do not repeat what the signature already declares. The construct states the return type, the read-only-ness, and whether the routine blocks, so the comment carries only the part a reader cannot see.
21. Delete comments that restate code or expose internal mechanics the reader does not need. A test case's comment describes the scenario it verifies, not the logic that makes the check pass.
22. State the observable behavior the code relies on: a comment justifying a check with internal state, a mask, a buffer, or an upstream file and line number describes the implementation, not the protocol- or interface-level fact a reader can see.
23. Counts, sizes, offsets, indexes as digits, in comments and prose: digits read as the value, spelled-out numbers read as prose and drift from the code.
24. Skip decorative markers and generated-sounding filler: "Part 1", "Step 2", a file header listing the obvious, machine-translated phrasing, filler naming what the code plainly does. A section label inside a file names what the section contains, not the order it runs in.
25. Annotate types at callable boundaries where the language supports it: concrete domain type, not a generic container.
26. Document every routine in one line: what it does, its side effects, its failure behavior. A routine whose contract looks evident from its signature still gets the line whenever the line carries intent the signature cannot state; a line that only restates the signature falls under rule 20.
27. Keep comments in sync with changes. One comment language per file: a file with an established non-English convention keeps it, a file opens in one language and continues in it.

## Consistency

28. Match surrounding code: one construct takes one form in the edited file, in sibling files of the same kind, across the project's test cases.
29. Treat the neighbouring implementation as the template, ahead of an idea of how code should read: the repository is the convention.
30. A change touching several files of one kind gives them one section structure + one header shape.

## Final check

Before finishing, reread the changed code: can a maintainer follow the main path, understand the reasoning, find state changes and failure cases without unpacking dense expressions? Simplify or explain unclear parts. Preserve behavior unless the task changes it; verify according to risk.
