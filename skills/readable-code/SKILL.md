---
name: readable-code
description: Use whenever writing, modifying, or reviewing code, including naming, comments, layout, and hardcoded values.
---

# Readable code

Prefer spacious, explicit, idiomatic code that a maintainer can change without knowing its history. Stay within scope. Read repository style guidance (e.g. `CODE_STYLE.md`, `AGENTS.md`, `CONTRIBUTING.md`) first and follow it on conflicts.

Cite rule numbers in review comments, for example, `violates 20`.

## Code classes

| Class | Examples | Default |
|---|---|---|
| Reusable component | library, driver, shared helper | Consolidate duplicates (11) |
| Procedural sequence | ordered steps that carry state between them | Inline; the same shape with different constants or values is not duplication |
| Glue or generated code | wiring, adapter, generated output | Fix defects only |

## Naming

1. Name the domain value, action, or unit so the reader can infer it at the use site.
2. Use established domain terms. For new concepts, qualify an existing term. Borrow terminology only when the domain already uses it.
3. Name complex conditions and intermediate results. Name literals whose meaning is hidden, such as encoded values or conversion factors. Keep self-explanatory values inline.
4. Prefix names only when they compete in a shared namespace, such as files, exports, macros, or module-level constants. Let the enclosing scope identify members, parameters, and locals.
5. Rename misleading symbols directly. Use comments for design reasons and constraints.
6. Use one name per concept and parallel names for parallel operations.
7. Spell out abbreviation at first use, then short form.

## Structure

8. Expand nested ternaries, dense chains, and multi-action expressions into steps. Expose state changes and failure paths. Use guards to reduce nesting.
9. Give each function one responsibility. Extract meaningful operations rather than splitting by line count. Keep bodies under 10 lines inline when they take at most 3 parameters and have fewer than 4 call sites.
10. Call the primitive directly. A helper that only forwards arguments or renames a framework call adds a name to learn, no capability.
11. Reuse existing behavior first. Consolidate blocks only if they must change together for the same reason. Keep variants with different constants, thresholds, or messages separate. A flag used solely to merge variants indicates separate operations.
12. Keep related logic together; introduce abstractions only for current needs.
13. Declare purity, read-only access, immutability, or async behavior where tools can check it. Update callers only as required by the language or framework.
14. Annotate callable boundaries with concrete domain types where supported.
15. Put distinct operations on separate lines and isolate phases with blank lines. Align similar branches. Use the project formatter for layout details.

## Values

16. Pass values that vary by environment, caller, or deployment through arguments or configuration. This includes identifiers, paths, names, colors, and sizes when they vary.
17. Reuse the configuration surface that exists. A variable or knob invented for one value moves the coupling, does not remove it.

## Comments

18. Comment what code leaves unclear: intent, assumptions, invariants, units, trade-offs, side effects, or failures. Remove restatements. Use one line for a missing routine contract. Label phases only where names and layout leave their purpose unclear.
19. Name the scenario in test comments. For checks, state the protocol or interface fact that makes the check valid. Mention a mask, buffer, or source location only when it helps explain that fact.
20. Name sections by purpose. Omit decorative markers, ordinal labels, and generated-sounding text.
21. Use digits for counts, sizes, offsets, and indexes in comments and prose.
22. Update comments with the code. Use one comment language per file and retain any established non-English convention.

## Consistency

23. Follow comparable implementations. Use consistent forms and value representations across the edited file, sibling files, and tests. Match headings and section structure across files with similar purposes.

## Final check

Reread the change. Verify that the main path, reasoning, state changes, and failures are easy to find. Simplify or explain what remains unclear. Keep each increment working end to end. Preserve behavior unless the task changes it and verify according to risk.

## Good and bad examples

```
Bad(too dense):
<code block>
<code block>
<code block>

Good:
<code block>

<code block>

<code block>
```

```
Bad(useless comment, the intent can be inferred from the code):
// if A is True, then print xxx
if A:
    print(xxx)

Good:
if A:
    print(xxx)
```

