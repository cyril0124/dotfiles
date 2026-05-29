---
name: explain-diff
description: Explain code in plain Chinese — Git diff hunk by hunk (default), or whole-file natural blocks when no diff is in scope. Use when user asks to explain a diff or existing code, runs /explain-diff or /explain-code, documents staged/unstaged changes, or walks through code without a diff.
---

# Explain Code

Explain code in plain Chinese. Two modes share one workflow: diff mode groups by file + hunk, code mode groups by file + natural semantic block. Write exactly one markdown file in current effective workdir.

## Quick Start

1. Resolve mode and scope:
   - Diff mode (default when git has uncommitted changes, target is a git ref/range, or invoked as `/explain-diff`):
     - No explicit target: inspect `git diff` + `git diff --cached` together as current uncommitted changes.
     - Explicit target after `/explain-diff`: run `git diff <user-argument>` exactly.
     - Natural-language scope/filter: translate intent to proper Git diff scope. Do not run raw text as shell command.
   - Code mode (target is a file path or function/class name, or invoked as `/explain-code`):
     - No explicit target: ask the user which file to explain.
     - Explicit file/range: read the file (or limited range) directly. Do not run git.
2. If resolved input is empty (no diff in diff mode, or target file missing in code mode): do not create file. Reply `No diff to explain.` (diff mode) or `No code to explain.` (code mode).
3. Inspect complete input before writing. Do not explain from memory or partial output.
4. Analyze each contiguous diff hunk (diff mode) or each natural semantic block (code mode).
5. Create `explain-<topic-slug>.md`; if exists, use `-2`, `-3`, etc.
6. Reply with created filename + short 2-3 sentence summary only.

## Diff Mode Explanation Rules

- Explain hunk by hunk.
- Group by file.
- Include exact raw diff hunk in diff format before explanation.
- If a hunk exceeds 30 lines, split its explanation into logical parts under the same hunk. Each part should reference the relevant line range or changed block and explain that part separately. Still include the full raw diff hunk; never omit diff lines or replace them with ellipses.
- Focus intent, effect, user-visible impact; avoid literal restatement.
- Plain language. Avoid jargon.
- Keep each hunk concise, usually 1-3 sentences.
- Base claims on locally inspected diff results.
- Write generated explanation file in Chinese.

## Code Mode Rules

- Block unit: split by natural semantic units — function, method, class, top-level statement group (imports, constants, main expression). Do not use fixed line counts. Do not merge unrelated blocks.
- Block rendering: precede each block with a fenced ```<language>``` code block instead of the diff-mode raw diff hunk. Derive `<language>` from the file extension; leave the tag empty when the extension does not map.
- Block explanation reuses the diff-mode style: focus intent and effect, plain language, no jargon, 1-3 sentences per block, base claims on the actually-read source, write the generated file in Chinese.
- Value (replaces Necessity in code mode): add exactly one `> Value: <valuable | removable (<reason>)>` blockquote per block, placed in the same position as the diff-mode necessity line. `valuable` is the default and is written as a bare tag with no reason. `removable` must include a parenthesized reason explaining why this block provides no unique value or duplicates other blocks. Value asks whether the block could be deleted; Bug Check asks whether the block is wrong. Keep them separate.
- The Necessity Rules do not apply in code mode; the Value rule above takes their place.

## Necessity Rules

- Add exactly one necessity blockquote per hunk, placed after the intent explanation and before any `Bug Check`.
- Two fixed tags only: `needed` or `unneeded`. No other tag is allowed.
- `needed` is the default and is written as a bare tag with no reason.
- Mark `unneeded` only when the hunk clearly exceeds task scope, adds defensive code unrelated to intent, refactors something unrelated to the stated intent, or duplicates another hunk. When in doubt, prefer `needed`.
- `unneeded` must include a parenthesized reason explaining why the change is redundant or out-of-scope.
- Necessity asks whether the hunk could be omitted. Bug Check asks whether the hunk is wrong. Keep the two responsibilities separate; do not move quality concerns into Necessity.
- For hunks split into multiple parts (>30 lines), write only one overall necessity line after all parts. Never write per-part necessity.
- Output format: `> Necessity: needed` or `> Necessity: unneeded (<reason>)`.

## Bug Check Rules

- Add `Bug Check` only when hunk has obvious bug, risk, or suspicious issue.
- No `Bug Check` means no obvious bug found in that hunk.
- `Bug Check` must include:
  - problem summary,
  - complete fix recommendation,
  - short line before diff block introducing suggested patch,
  - suggested fix in fenced `diff` block (diff mode) or `<language>` block matching the main block (code mode).

## Filename Rules

- Create exactly one file named `explain-<topic-slug>.md`.
- `<topic-slug>`: short lowercase ASCII summary, letters/digits/hyphens only.
- Never overwrite existing file. If needed, use `explain-<topic-slug>-2.md`, then `-3.md`, etc.
- Write the file directly without asking for confirmation.

## Output Template

Use exact structure in generated file:

````markdown
# Change Explanation: <brief overall summary>

## Overview
<one short paragraph summarizing the overall change in the user's language>

## <file-path>

### <file-path> Hunk 1: <short label>
```diff
<exact diff hunk for this change block>
```

<plain-language explanation of what changed, why it matters, and what effect it has>

[For hunks over 30 lines, repeat as needed]
**Part <n>: <short label>**
<plain-language explanation for this logical part>

> Necessity: <needed | unneeded (<reason>)>

#### Bug Check
<brief note describing the obvious bug, risk, or suspicious issue in the user's language>

<short line introducing the suggested fix patch in the user's language>

```diff
<complete modification recommendation in diff format showing how to change it>
```

## Summary
<short 2-3 sentence wrap-up of the overall impact in the user's language>
````

In diff mode, always include the `> Necessity: ...` line for every hunk. In code mode, always include the `> Value: ...` line for every block. Omit entire `Bug Check` subsection for hunks/blocks without obvious issue.

For code mode, use this structure instead of the diff-mode template:

````markdown
# Code Explanation: <brief overall summary>

## Overview
<one short paragraph summarizing what this code does in the user's language>

## <file-path>

### <file-path> Block 1: <short label>
```<language>
<original code for this semantic block>
```

<plain-language explanation of what this block does, why it exists, and how it fits the file's purpose>

[For blocks over 30 lines, repeat as needed]
**Part <n>: <short label>**
<plain-language explanation for this logical part>

> Value: <valuable | removable (<reason>)>

#### Bug Check
<brief note describing the obvious bug, risk, or suspicious issue in the user's language>

<short line introducing the suggested fix in the user's language>

```<language>
<corrected code snippet>
```

## Summary
<short 2-3 sentence wrap-up of the file's overall design in the user's language>
````
