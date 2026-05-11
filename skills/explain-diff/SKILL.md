---
name: explain-diff
description: Explain a Git diff hunk by hunk and write a Chinese markdown explanation file named explain-<topic>.md. Use when the user asks to explain a diff, uses /explain-diff, or wants a written change explanation from git diff output.
---

# Explain Diff

Explain Git changes in plain Chinese. Group by file + hunk. Write exactly one markdown file in current effective workdir.

## Quick Start

1. Resolve diff scope:
   - No explicit target: inspect `git diff` + `git diff --cached` together as current uncommitted changes.
   - Explicit target after `/explain-diff`: run `git diff <user-argument>` exactly.
   - Natural-language scope/filter: translate intent to proper Git diff scope. Do not run raw text as shell command.
2. Analyze each contiguous diff hunk.
3. Create `explain-<topic-slug>.md`; if exists, use `-2`, `-3`, etc.
4. Reply with created filename + short 2-3 sentence summary only.

## Explanation Rules

- Explain hunk by hunk.
- Group by file.
- Include exact raw diff hunk in diff format before explanation.
- Focus intent, effect, user-visible impact; avoid literal restatement.
- Plain language. Avoid jargon.
- Keep each hunk concise, usually 1-3 sentences.
- Base claims on locally inspected diff results.
- Write generated explanation file in Chinese.

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

#### Bug Check
<brief note describing the obvious bug, risk, or suspicious issue in the user's language>

<short line introducing the suggested fix patch in the user's language>

```diff
<complete modification recommendation in diff format showing how to change it>
```

## Summary
<short 2-3 sentence wrap-up of the overall impact in the user's language>
````

Omit entire `Bug Check` subsection for hunks without obvious issue.
