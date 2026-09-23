---
name: review
description: Use when asked to review code, diffs, documents, plans, or pasted content.
---

# Review

Review only user-specified content. Findings evidence-based, actionable, concise.

## Workflow

1. Identify review target: diff, file, pasted content, document, plan. Record contents + in-scope items not reviewed (binary, generated, lock file, vendored, oversized) + reason each.
2. Inspect for real issues only. Never invent findings to fill the report.
3. Admit a candidate issue only when it passes every gate below. Drop any candidate that fails one, even when it looks real.
   - Concrete impact: name the specific affected code path. No speculation.
   - Actionable: a discrete fix exists, not "consider improving X".
   - Unintentional: not a deliberate design choice.
   - Introduced by the reviewed content: pre-existing issues out of scope.
   - No unstated assumptions: none about the codebase or the author's intent.
   - Proportionate rigor: fix does not demand rigor absent elsewhere in the codebase.
4. Trace every value reviewed content introduces across a boundary — event, message, command, enum variant, config key, IPC payload, queue item. Find its consuming dispatch point (switch, router, handler registry, filter chain); confirm it handles the new value. Silent drop or no-op = issue.
5. Severity by impact:
   - `Critical`: security risk, data loss, crash, broken core behavior, production-blocking failure.
   - `Major`: real bug, incorrect behavior, significant maintainability risk, meaningful performance issue.
   - `Minor`: small correctness edge case, naming, readability, style, low-risk maintainability issue.
6. Every issue: exact evidence from visible content, file path + line number when available. Diff or patch: cited line range must intersect a changed hunk.
7. Smallest focused fix per issue: unified diff for code; rewrite or added text for docs, plans, pasted prose. No safe fix → say so, omit fake patch.
8. Explanations in the user's language; identifiers, code, diffs in original language.

## Large Reviews

Too big for one high-quality pass → read-only subagents review separate files or independent sections. Subagent findings advisory only: main agent dedupes them, verifies evidence, sets final severity, writes final report in the output format below.

## Output Format

Issues exist → reviewed content summary first, then this format per issue. ID each issue sequentially: `R-001`, `R-002`, ... (zero-padded, report order). Every issue must have an ID.

````md
**Reviewed Content Summary**
<what the reviewed code or content does, in a concise plain-language summary.>

**Coverage:** <what was reviewed, then every item in scope that was not reviewed as `path (reason)`; write `none` when nothing was skipped.>

### R-001 <Critical|Major|Minor>: <short title> (`path/to/file.ext:<line>`)

#### Problem
<technical problem description based on the evidence.>

#### Plain Explanation
<same issue explained so a middle school student can understand it, using simple non-jargon language.>

#### Fix
<why this fix resolves the issue.>

```diff
--- a/path/to/file.ext
+++ b/path/to/file.ext
@@ -<old_line>,<old_count> +<new_line>,<new_count> @@
-<old code>
+<new code>
```

For non-code targets, replace the diff block with a short rewrite or added text that applies the fix.

#### Evidence
<file path and line number plus the relevant original snippet; for pasted content, use a locatable section or quoted snippet.>
````

After all issues, end with summary table of every finding:

```md
## Summary

| ID | Severity | One-liner |
|----|----------|-----------|
| R-001 | Critical | <one-line problem> |
| R-002 | Major | <one-line problem> |
| R-003 | Minor | <one-line problem> |
```

Summary table rules:
- Include every issue, same order as IDs.
- `One-liner` = one short sentence of the problem only; no fix, no evidence, no path.
- Table headers stay English even when the rest of the report is not.
- No issues found → omit summary table.

No issues found:

```md
No issues found.
Reviewed Content Summary: <what the reviewed code or content does, in a concise plain-language summary.>
Reviewed: <target summary>
Coverage: <what was reviewed, then every item in scope that was not reviewed as `path (reason)`; write `none` when nothing was skipped.>
```

## Fix Rules

- One fix per issue, minimal, focused on that issue only.
- Never combine unrelated fixes into one fix block.
- Unified diff for code. Short rewrite or added text for documents, plans, pasted prose.
- Issue heading: ID (`R-001`, `R-002`, ...) first, then severity, title, `path:line` when available.
- Every issue must have an `Evidence` field: file path + line number + relevant original snippet; pasted content → locatable section or quoted snippet.
- Code diff hunks must carry line numbers in the `@@` header.
- No safe fix → say why, omit the patch. Never invent an approximate diff.

## Common Pitfalls

- Never report an issue without visible evidence from the reviewed content.
- Never report a style preference as an issue unless it affects readability, maintenance, or consistency.
- Never repeat one root cause across multiple severities.
- Never review unrelated files or code paths not in scope.
- Never silently drop part of the target: every unreviewed file or section must appear in `Coverage` with its reason.
- Diff or patch: never cite a line range that does not touch a changed hunk.
- Never force a unified diff onto non-code targets; never invent approximate diffs when the fix is unsafe or unclear.
