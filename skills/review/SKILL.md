---
name: review
description: Reviews user-specified content and reports evidence-based issues with severity, plain-language explanation, and per-issue fixes (code diffs or text rewrites). Use when the user asks to review, audit, check, inspect, or critique code, diffs, files, documents, plans, or pasted content.
---

# Review

Review only the content the user specified. Keep findings evidence-based, actionable, and concise.

## Workflow

1. Identify the review target: diff, file, pasted content, document, or plan.
2. Inspect for real issues only; do not invent findings to fill the report.
3. Assign severity by impact:
   - `Critical`: security risk, data loss, crash, broken core behavior, or production-blocking failure.
   - `Major`: real bug, incorrect behavior, significant maintainability risk, or meaningful performance issue.
   - `Minor`: small correctness edge case, naming, readability, style, or low-risk maintainability issue.
4. For every issue, include exact evidence from visible content: file path and line number when available.
5. Provide the smallest focused fix for each issue: unified diff for code; rewrite or added text for docs/plans/pasted prose. If no safe fix can be produced, say so and omit a fake patch.
6. Follow the user's language for explanations; keep identifiers, code, and diffs in their original language.

## Large Reviews

When the review target is too large for one high-quality pass, use read-only subagents to review separate files or independent sections. Subagent findings are advisory only: the main agent must deduplicate them, verify the evidence, set final severity, and produce the final report in this skill's output format.

## Output Format

If issues exist, start with the reviewed content summary, then use this format for each issue.
Assign each issue a sequential ID: `R-001`, `R-002`, ... (zero-padded, in report order). Every issue must have an ID.

````md
**Reviewed Content Summary**
<what the reviewed code or content does, in a concise plain-language summary.>

### R-001 <Critical|Major|Minor>: <short title> (`path/to/file.ext:<line>`)

#### Evidence
<file path and line number plus the relevant original snippet; for pasted content, use a locatable section or quoted snippet.>

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
````

If no issues are found:

```md
No issues found.
Reviewed Content Summary: <what the reviewed code or content does, in a concise plain-language summary.>
Reviewed: <target summary>
```

## Fix Rules

- The fix must be per issue, minimal, and focused on that issue only.
- Use a unified diff for code issues. Use a short rewrite or added text for documents, plans, and pasted prose.
- The issue heading must start with an ID (`R-001`, `R-002`, ...) then severity, title, and `path:line` when available.
- The issue heading must include `path:line` when a line number is available.
- Every issue must include an `Evidence` field with a file path and line number plus the relevant original snippet; for pasted content, use a locatable section or quoted snippet.
- Code diff hunks must include line numbers in the `@@` header.
- If no safe fix can be produced, say why and omit the patch; do not invent an approximate diff.
- Do not combine unrelated fixes into one fix block.

## Common Pitfalls

- Do not report an issue without visible evidence from the reviewed content.
- Do not report style preferences as issues unless they affect readability, maintenance, or consistency.
- Do not repeat the same root cause across multiple severities.
- Do not review unrelated files or code paths unless the user included them in scope.
- Do not force a unified diff onto non-code targets, and do not invent approximate diffs when the fix is unsafe or unclear.
