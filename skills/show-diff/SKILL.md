---
name: show-diff
description: Preview a proposed solution as a readable diff before applying changes.
disable-model-invocation: true
---

# Show Diff

Preview a concrete patch. During preview, leave project files and the Git index untouched, including in delegated work.

## Workflow

1. Read relevant source, project instructions, and existing changes. Before drafting or revising, snapshot each target's digest (or absence) and index entry. Base the patch on the working tree and preserve user edits. If blocked, ask one focused question. If no change is needed, show evidence and omit the diff.
2. Draft the complete unified diff in memory using read-only inspection. Include in-scope files, imports, call sites, config, and regression tests. Check paths, removed and context lines, hunk ranges, and line counts against the baseline.
3. Number all hunks `h1`, `h2`, … in patch order. Select inline hunks, save the patch if needed, and list omissions.
4. Recheck snapshots. Report differences, what you verified, and whether you ran the proposal. Baseline checks validate only the baseline.

## Preview artifact

If any part is omitted or excerpted, save the complete patch to `$PREVIEW_DIR/proposed.patch` outside the checkout. A complete inline patch needs no artifact.

```bash
PREVIEW_DIR="$(mktemp -d "${TMPDIR:-/tmp}/show-diff-XXXXXXXX")"
```

Make the patch independently applicable. Use three context lines, `--- a/<path>` and `+++ b/<path>` headers, accurate `@@` ranges, `/dev/null` for additions or deletions, and explicit rename and binary changes. If no external directory is writable, label the preview `unbacked`, send complete hunks in risk order across messages, and list unsent hunks.

## Choosing the inline hunks

- At ≤2 files and ≤20 changed lines, show all hunks. Otherwise show up to three covering the fix mechanism, authentication/security/crypto/migration/money changes, public interfaces/defaults/formats, or deletions/removed checks. Prefer wider impact and flag correctness risks in the omitted-hunk list.
- For hunks over 40 lines, show one context line and label the block `non-applicable excerpt`. Keep the full hunk in the artifact or use the unbacked fallback.

## Conversation format

Use the user's language for headings and explanations.

1. Lead with the unapplied diff or a one-sentence fix. Give the hunk ID range, file count, `+added/-removed` totals, and artifact path if saved.
2. Show fenced `diff` blocks in patch order. Label each block directly above it with its ID, repository-relative path, and starting line if known (e.g. `h2 — src/auth.ts:42`). Repeat the path for each hunk. Copy the patch verbatim except for marked excerpts. Explain only the fix mechanism, trade-offs, or non-obvious behavior beside the relevant hunk.
3. For each omitted hunk, give its ID, path, and one-line change. Group mechanical repeats. Skip this list if none are omitted.
4. For any omissions or excerpts, summarize behavior in patch order as `<path> — <what changes> (<+added/-removed>)`. Group mechanical repeats by naming their files. Reserve hunk IDs and validation for their own sections.
5. Report validation and whether project files and the index stayed unchanged. End with the checkpoint line.

## Checkpoint

Apply only a complete proposal with explicit authorization. A preview-then-apply request authorizes both. Hunk requests stay in preview.

| Control | Action |
|---|---|
| `expand <hN> ...` | Show selected complete hunks verbatim from the artifact or conversation, with the usual headings. |
| `full` | Show the complete patch with the usual headings. |
| `revise` | Resnapshot, revise, refresh the artifact if needed, renumber, and preview again. |
| `ask` | Answer from the proposal and local evidence. If the answer changes the solution, name the affected hunk and preserve the proposal. |
| `apply` | Inspect current source, apply the whole proposal including artifact-only changes, and report changes and validation. |

End each preview with this exact line unless the user asks to omit it. Application still requires authorization.

`Confirm: apply? (apply / revise / ask / full / expand <hN>)`
