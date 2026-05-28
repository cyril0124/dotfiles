---
name: explain-diff-visual
description: Explain Git diffs hunk by hunk + add ASCII visuals in Chinese explain-<topic>.md report. Use when user asks visualize diff, run /explain-diff-visual, wants visual overview + hunk explanation, or document staged/unstaged changes visually.
---

# Explain Diff Visual

Explain Git changes in plain Chinese: full hunk-by-hunk analysis + ASCII diagrams for change structure, blast radius, before/after impact. Not visualization-only.

## Quick Start

1. Resolve diff scope:
   - No explicit target: inspect `git diff` + `git diff --cached` together as current uncommitted changes.
   - Explicit target after `/explain-diff-visual`: run `git diff <user-argument>` exactly.
   - Natural-language scope/filter: translate intent to proper Git diff scope. Do not run raw text as shell command.
2. Empty resolved diff: create no file. Reply `No diff to explain.`
3. Inspect complete resolved diff before writing. No memory/partial-output explanation or visualization.
4. Analyze each contiguous diff hunk, changed-file relations, impact scope.
5. Create `explain-<topic-slug>.md`; if exists, use `-2`, `-3`, etc.
6. Reply created filename + short 2-3 sentence summary only.

## Explanation Rules

- Include complete hunk-by-hunk explanations grouped by file.
- Include exact raw diff hunk in diff format before each hunk explanation.
- If hunk >30 lines, split explanation into logical parts under same hunk. Each part references relevant line range or changed block. Still include full raw diff hunk; never omit diff lines or use ellipses.
- Focus intent, effect, user-visible impact; avoid literal restatement.
- Plain language. Avoid jargon.
- Keep each hunk concise, usually 1-3 sentences.
- Base claims on locally inspected diff results.
- Write generated explanation file in Chinese.

## ASCII Visualization Rules

- Add `## Visual Overview` before hunk-by-hunk file explanations.
- Choose diagrams that best explain this diff. Do not force fixed diagram types or headings.
- Prefer one compact, high-signal visual over many boilerplate diagrams.
- Useful options: changed-file map, dependency/data flow, before/after shape, call path, lifecycle/state change, blast radius, risk hotspot map.
- Include file paths and change labels when helpful: `[A]`, `[M]`, `[D]`, `+/-`, `!!` risk.
- Use ASCII/box drawing only when it improves understanding; otherwise use concise bullets/table inside `Visual Overview`.
- Keep visuals readable in terminal. Prefer under 80 chars wide, but clarity wins.
- Diagram labels may use English for paths + technical terms.

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
- Write file directly without asking confirmation.

## Output Template

Use exact structure in generated file:

````markdown
# Change Explanation: <brief overall summary>

## Overview
<one short paragraph summarizing the overall change in the user's language>

## Visual Overview

<one or more concise ASCII diagrams, bullets, or tables chosen for this diff>

<omit forced subheadings; add only headings that clarify the chosen visuals>

## <file-path>

### <file-path> Hunk 1: <short label>
```diff
<exact diff hunk for this change block>
```

<plain-language explanation of what changed, why it matters, and what effect it has>

[For hunks over 30 lines, repeat as needed]
**Part <n>: <short label>**
<plain-language explanation for this logical part>

#### Bug Check
<brief note describing the obvious bug, risk, or suspicious issue in the user's language>

<short line introducing the suggested fix patch in the user's language>

```diff
<complete modification recommendation in diff format showing how to change it>
```

## Summary
<short 2-3 sentence wrap-up of the overall impact in the user's language>
````

Keep `Visual Overview` flexible and non-boilerplate. Omit entire `Bug Check` subsection for hunks without obvious issue.
