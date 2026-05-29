---
name: explain-diff
description: Explain Git diffs hunk by hunk and write a Chinese explain-<topic>.md report. Use when user asks to explain a diff, run /explain-diff, document staged/unstaged changes, or review change intent.
---

# Explain Diff

Explain Git changes in plain Chinese. Group by file + hunk. Write exactly one markdown file in current effective workdir.

## Quick Start

1. Resolve diff scope:
   - No explicit target: inspect `git diff` + `git diff --cached` together as current uncommitted changes.
   - Explicit target after `/explain-diff`: run `git diff <user-argument>` exactly.
   - Natural-language scope/filter: translate intent to proper Git diff scope. Do not run raw text as shell command.
2. If resolved diff is empty: do not create file. Reply `No diff to explain.`
3. Inspect complete resolved diff before writing. Do not explain from memory or partial output.
4. Analyze each contiguous diff hunk.
5. Create `explain-<topic-slug>.md`; if exists, use `-2`, `-3`, etc.
6. Reply with created filename + short 2-3 sentence summary only.

## Explanation Rules

- Explain hunk by hunk.
- Group by file.
- Include exact raw diff hunk in diff format before explanation.
- If a hunk exceeds 30 lines, split its explanation into logical parts under the same hunk. Each part should reference the relevant line range or changed block and explain that part separately. Still include the full raw diff hunk; never omit diff lines or replace them with ellipses.
- Focus intent, effect, user-visible impact; avoid literal restatement.
- Plain language. Avoid jargon.
- Keep each hunk concise, usually 1-3 sentences.
- Base claims on locally inspected diff results.
- Write generated explanation file in Chinese.

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
  - suggested fix in fenced `diff` block.

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

Always include the `> Necessity: ...` line for every hunk. Omit entire `Bug Check` subsection for hunks without obvious issue.
