---
name: show-diff
description: Preview a proposed solution as a readable diff before applying changes.
disable-model-invocation: true
---

# Show Diff

Preview a concrete patch. Keep project files and the Git index unchanged until the user explicitly authorizes application. This boundary also applies to delegated work. An explicit request to preview and then apply authorizes both.

## Workflow

1. Read relevant source, project instructions, and existing changes. Before drafting or revising, record each target file's digest (or absence) and Git index entry. Use the working tree as the baseline and preserve user edits. If blocked, ask one focused question. If no change is needed, state the evidence and omit the diff.
2. Draft the complete unified diff in memory, including affected files, imports, call sites, configuration, and regression tests within scope. Use read-only inspection. Verify paths, removed and context lines, hunk ranges, and line counts against the baseline.
3. Number all hunks `h1`, `h2`, … in patch order. Select inline hunks, save the complete patch when needed, and list all omitted hunks.
4. Compare the file and index snapshots. Report any differences and what you verified. State whether the proposal was run. Checks on the baseline do not validate the proposal.

## Preview artifact

Save the complete patch to `$PREVIEW_DIR/proposed.patch` when any part is omitted, including when a hunk is excerpted. If the complete patch is inline, skip the artifact. Ensure the temporary directory is outside the checkout.

```bash
PREVIEW_DIR="$(mktemp -d "${TMPDIR:-/tmp}/show-diff-XXXXXXXX")"
```

Use an independently applicable patch with three lines of context, `--- a/<path>` and `+++ b/<path>` headers, accurate `@@` ranges, `/dev/null` for additions or deletions, and explicit rename and binary changes. Without a writable external directory, label the preview as unbacked, send the full hunks in risk order across messages, and identify any still unsent.

## Choosing the inline hunks

- At ≤2 files and ≤20 changed lines, show all hunks. Otherwise, show up to three: the fix mechanism, changes to authentication/security/crypto/migrations/money or public interfaces/defaults/formats, and deletions or removed checks. If more qualify, choose those with the widest impact and name any correctness risk in the omitted-hunk list.
- For hunks over 40 lines, reduce to one context line and label the block as a non-applicable excerpt. Keep the complete hunk in the artifact or use the unbacked fallback.

## Conversation format

Use the user's language for headings and explanations. Start with the proposed, unapplied diff or a one-sentence fix. Give the hunk range, file count, `+added/-removed` totals, and artifact path if saved.

1. Show fenced `diff` blocks by file in patch order. Label each with its hunk ID and location. Copy the patch verbatim except for marked excerpts. Explain only the fix mechanism, trade-offs, or non-obvious behavior next to the relevant hunk.
2. List each omitted hunk by ID, file, and one-line change description. Group mechanical repeats and skip the list when none are omitted.
3. If any change is omitted or excerpted, summarize behavior in patch order as `<path> — <what changes> (<+added/-removed>)`. Group mechanical repeats by naming their files. Keep validation and hunk IDs out of the summary.
4. State the validation result, including whether project files and the index stayed unchanged. End with the checkpoint line.

## Checkpoint

Apply only with explicit authorization and a complete proposal. Requests to see hunks stay in preview.

| Control | Action |
|---|---|
| `expand <hN> ...` | Show the selected complete hunks verbatim from the artifact or conversation. |
| `full` | Show the complete patch as per-file `diff` blocks. |
| `revise` | Resnapshot, revise the patch, refresh the artifact if needed, renumber hunks, and show the new preview. |
| `ask` | Answer from the proposal and local evidence. If the answer changes the solution, identify the affected hunk and leave the proposal intact. |
| `apply` | Apply the whole proposal against currently inspected source, including artifact-only changes. Report the applied changes and validation. |

End each preview response with this exact line unless the user asks to omit it. Omission grants no authorization.

`Confirm: apply? (apply / revise / ask / full / expand <hN>)`
