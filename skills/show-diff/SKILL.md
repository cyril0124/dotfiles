---
name: show-diff
description: Preview a proposed solution as a readable diff before applying changes.
disable-model-invocation: true
---

# Show diff

Present a concrete proposed patch in the conversation so the user can review the solution before implementation. This invocation is a preview request. Keep project files and the Git index unchanged; do not apply the patch to produce the preview. Implement only when the user explicitly requests application, including an explicit instruction to preview and then apply in the same request.

## Workflow

1. Establish the problem and scope from the request and available context. Read the relevant source, project instructions, and existing changes. Use current working-tree content as the patch baseline, preserving the user's edits. Ask one focused question only if missing information prevents a concrete solution.
2. Work out the complete solution before shortening its presentation. Account for all required files, imports, call sites, configuration, and relevant regression tests. Keep changes within the requested scope.
3. Construct the proposed unified diff in memory. Check removed and context lines against the source, and check that paths, hunk ranges, and line counts match the proposal. Use read-only inspection commands; avoid formatters, generators, or other commands that write project files. Any delegated work must follow the same preview boundary.
4. Show the diff using the rules below. Finish with a brief validation status and any unresolved assumption that affects correctness. Distinguish checks actually performed from checks suggested for after application. The preview is complete when the user can assess the solution and every omitted change is accounted for.

## Diff presentation

- Lead with the proposed diff, or one short sentence identifying the fix. Label it as proposed and unapplied. Use the user's language for explanations.
- Group changes by file in fenced `diff` blocks. Include `--- a/<path>`, `+++ b/<path>`, and accurate `@@` hunk headers. Use `/dev/null` for an added or deleted file. Identify renames and binary changes explicitly.
- Default to the complete patch, including supporting changes and tests when needed. Show executable code rather than pseudocode, TODOs, or placeholders. Include enough unchanged context to locate and understand each change, usually three lines around a changed block.
- Keep explanations close to the relevant diff and limited to why the change resolves the problem, tradeoffs, or non-obvious behavior. Do not substitute a prose plan or an existing Git diff for the proposed solution.

## Long patches

Preserve completeness unless the patch is long enough to impede review or exceed the response budget. There is no fixed hunk or line cap.

1. Reduce excess unchanged context first, keeping hunk headers accurate.
2. If still too long, omit whole repetitive or mechanical hunks, such as repeated call-site updates or generated output. Retain the core fix, distinct behavior changes, public interface changes, and representative regression coverage. Never hide a correctness concern or a risky change to save space.
3. Mark each omission outside the diff fence with its file, affected symbols or region, and a concrete description of the omitted change. If an entire file's diff is omitted, list that file explicitly. Label the overall preview as abbreviated and unsuitable for direct application.
4. Keep displayed hunks intact. Never insert ellipses or omission prose into a diff block as if they were source lines. When one large hunk must be shortened, split at unchanged regions into valid smaller hunks where possible. If only an excerpt fits, label it outside the fence as a non-applyable excerpt and identify exactly what is missing.

A request to expand omitted hunks continues the preview. Show those hunks without applying changes. If the user requests application later, recheck the current source and apply the complete solution, including changes omitted from the preview.

## Completion

State that project files remain unchanged. If the proposed code has not run, say so explicitly; passing checks on the original code do not validate the proposal. When blocked, name the missing fact and ask for that fact instead of inventing a patch. If inspection shows no change is needed, state the evidence and produce no artificial diff.
