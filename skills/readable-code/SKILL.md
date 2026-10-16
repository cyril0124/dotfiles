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
2. Use the term the current domain already uses. A coined name must be learned, and a term imported from another domain arrives carrying that domain's meaning, so the reader applies the wrong mental model. When the domain has no word for the concept, extend an existing term with a qualifier; take a foreign term only when the domain itself has adopted it.
3. Give complex conditions + intermediate results meaningful names.
4. Prefix a name only where it competes for a shared namespace: file names, exported symbols, macros, module-level constants. Members, parameters, and locals are already separated by their container and take no prefix. A prefix there repeats the scope, and the reader strips it back off to find the name.
5. Fix misleading names directly. A comment needed to correct a name's meaning signals a naming defect; design reasons and constraints can still need explanation.
6. One concept, one name; parallel operations take parallel names. Different names imply different meanings, sending the reader hunting a difference that is not there.
7. Spell out abbreviation at first use, then short form.

## Structure

8. Straightforward control flow: expand nested ternaries, dense chains, multi-action expressions into clear steps. Keep state changes + failure paths visible; guard clauses where they cut nesting.
9. One responsibility per function. Extract helpers for meaningful operations, not to meet a line limit.
10. Call the primitive directly. A helper that only forwards arguments or renames a framework call adds a name to learn, no capability.
11. Reuse existing behavior before adding an implementation. Consolidate duplicate or near-identical routines; choose a reuse mechanism that preserves clear responsibilities instead of requiring an extra parameter in every case.
12. Keep related logic together; introduce abstractions only for current needs.
13. Express pure, read-only, immutable, or asynchronous properties with declarations the language and toolchain support, so tools can check the contract. Propagate changes through callers only as required by that property's actual language and framework rules.
14. Annotate types at callable boundaries where the language supports it: concrete domain type, not a generic container.
15. Spacious layout: distinct operations on their own lines, logical phases separated by blank lines. Reader's scan is the cost, not line count. Similar branches get consistent structure; layout details go to the project formatter.

## Values

16. Keep environment-, caller-, or deployment-varying values out of the body: identifiers, paths, names, colors, sizes. Take them from caller or configuration, so the same code serves the next environment.
17. Reuse the configuration surface that exists. A variable or knob invented for one value moves the coupling, does not remove it.

## Comments

18. Comment only what names, signatures, and code structure leave unclear: intent, assumptions, invariants, units, tradeoffs, side effects, or failure behavior. Leave evident code blocks and routine contracts uncommented; remove comments that merely restate them. Use a one-line routine comment when it adds missing contract information, and section comments in multi-phase routines or complex algorithms only where names and layout leave a phase's purpose unclear.
19. Explain the behavior a reader needs to understand: test comments describe the scenario verified; comments justifying checks state the protocol- or interface-level fact relied on. Include internal mechanics only when needed to explain that behavior; an internal mask, buffer, or upstream file and line number alone does not explain why a check is valid.
20. Skip decorative markers and generated-sounding filler: "Part 1", "Step 2", machine-translated phrasing. A section label names what the section contains, not the order it runs in.
21. Counts, sizes, offsets, indexes as digits, in comments and prose: digits read as the value, spelled-out numbers read as prose and drift from the code.
22. Keep comments in sync with changes. One comment language per file: a file with an established non-English convention keeps it, a file opens in one language and continues in it.

## Consistency

23. Use neighbouring implementations as the template, following the repository's conventions over personal style. Apply the same form to equivalent constructs and value representations in the edited file, comparable sibling files, and tests. When changing several files with comparable content and purpose, keep their section structure and header shape consistent.

## Final check

Before finishing, reread the changed code: can a maintainer follow the main path, understand the reasoning, find state changes and failure cases without unpacking dense expressions? Simplify or explain unclear parts. Keep each increment working end to end. Preserve behavior unless the task changes it; verify according to risk.
