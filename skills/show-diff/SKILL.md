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
4. Show the diff using the rules below, then give the modification summary. Finish with a brief validation status and any unresolved assumption that affects correctness. Distinguish checks actually performed from checks suggested for after application. The preview is complete when the user can assess the solution and every omitted change is accounted for.

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

## Modification summary

Close every preview with a short modification summary between the diff and the completion statement. Match the user's language in the heading and in each line.

1. One line per proposed file change, in patch order: `<path> — <what changes> (<+added/-removed>)`. Omit files with no proposed change.
2. Describe the behavior change, not the diff structure. No hunk numbers, repeated code, or validation detail.
3. Keep it short. Group mechanical repeats of the same change into one line that names the affected files.
4. When the preview omits or abbreviates regions, say so in the summary line for those files, so the summary never reads as complete when it is not.

The summary restates the proposal in one screen. It never introduces a change that no displayed or listed hunk covers.

## Checkpoint

After a preview, STOP before implementation unless the latest request explicitly authorizes applying the patch and a complete proposal is available.

| Control | Action | Where to stop |
|---|---|---|
| `revise` | Incorporate the requested changes and reprint the complete diff and its summary. | At the checkpoint. |
| `ask` | Answer the question from the proposal and relevant local evidence. If the answer changes the solution, identify the affected hunk without silently revising it. | After the answer and confirmation line. No implementation. |
| `apply` | Implement the previewed solution against the currently inspected source. | After reporting the applied changes and their validation status. |

Omit the confirmation line only when the user requests no confirmation. Omission alone does not authorize application.

End every preview response with exactly this line, last, after the modification summary and the completion statement:

`Confirm: apply? (revise / ask / apply)`

## Completion

State that project files remain unchanged. If the proposed code has not run, say so explicitly; passing checks on the original code do not validate the proposal. When blocked, name the missing fact and ask for that fact instead of inventing a patch. If inspection shows no change is needed, state the evidence and produce no artificial diff.
