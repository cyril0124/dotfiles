---
name: show-diff
description: Preview a proposed solution as a readable diff before applying changes.
disable-model-invocation: true
---

# Show diff

Present a concrete proposed patch in the conversation so the user can review the solution before implementation. This invocation is a preview request. Keep project files and the Git index unchanged; do not apply the patch to produce the preview. Implement only when the user explicitly requests application, including an explicit instruction to preview and then apply in the same request.

The conversation carries the change index plus the hunks that need a human decision, and the complete patch goes to a preview artifact outside the checkout whenever part of it stays out of the conversation. A long diff then cannot bury the decision inside itself.

## Workflow

1. Establish the problem and scope from the request and available context. Read the relevant source, project instructions, and existing changes. Use current working-tree content as the patch baseline, preserving the user's edits. Ask one focused question only if missing information prevents a concrete solution.
2. Work out the complete solution before shortening its presentation. Account for all required files, imports, call sites, configuration, and relevant regression tests. Keep changes within the requested scope.
3. Construct the proposed unified diff in memory. Check removed and context lines against the source, and check that paths, hunk ranges, and line counts match the proposal. Use read-only inspection commands; avoid formatters, generators, or other commands that write project files. Any delegated work must follow the same preview boundary.
4. Number every hunk in patch order across the whole patch: `h1`, `h2`, and so on. The numbering is per preview, and these ids are the handle for the inline hunks, the omitted-hunk list, and later `expand` or `full` requests.
5. Print the preview, then the modification summary, then the validation status, and finish with the confirmation line. Stop at the checkpoint.

## Preview artifact

Write the complete patch to `$PREVIEW_DIR/proposed.patch`, with `PREVIEW_DIR` created by:

```bash
PREVIEW_DIR="$(mktemp -d "${TMPDIR:-/tmp}/show-diff-XXXXXXXX")"
```

- Write the artifact whenever any hunk stays out of the conversation. When every hunk is printed inline, skip the artifact and print the complete patch.
- Never write the artifact into the repository. A preview artifact inside the checkout changes the working tree under review and can end up in the user's next commit.
- The artifact holds the complete patch: standard three-line context, `--- a/<path>`, `+++ b/<path>`, accurate `@@` hunk headers, `/dev/null` for an added or deleted file, and explicit identification of renames and binary changes. It stays applyable on its own.
- Report the artifact path with the file count and the `+added/-removed` totals.
- If no writable temporary directory exists, print the hunks in risk order across consecutive messages, say which hunks remain unsent, and label the preview as unbacked. Never drop a hunk silently.

## Conversation format

```
<one sentence naming what the change does, or nothing beyond it when the fix is obvious>
Preview: h1-h7 — 3 files, +58/-19
Artifact: /tmp/show-diff-a1b2c3d4/proposed.patch

<fenced diff blocks for the inline hunks, each introduced by its id and location:
 h3 src/auth.ts:42 — verifyToken: timing-safe compare>

Not shown inline: h1 h2 (src/auth.ts:12-18 imports), h4 h5 (src/auth.ts:120-160 mechanical renames), h6 (src/session.ts:44 retry cap), h7 (tests/auth.test.ts:60 regression case)
```

Then the modification summary, the validation status, and the confirmation line.

- Lead with the diff or the one-sentence fix line, labeled as proposed and unapplied.
- Group inline hunks by file in patch order. Copy them verbatim from the artifact, so they carry the same context and headers.
- List every hunk left out of the conversation by id, file, and a one-line description of what changes. That list is the reader's map of the artifact: an unlisted hunk reads as no change. Group mechanical repeats of the same change into one entry, and omit the list entirely when every hunk is inline.
- Keep explanations close to the relevant hunk and limited to why the change resolves the problem, tradeoffs, or non-obvious behavior. A prose plan or an existing Git diff does not substitute for the proposed solution. Use the user's language for explanations.

## Choosing the inline hunks

Inline a hunk when it is the mechanism that resolves the reported problem, or when it changes behavior on an authentication, security, crypto, data-migration, or money path, or when it changes a public interface, a default, or a file format, or when it deletes code or removes a check.

- Inline at most three hunks. If more qualify, inline the three with the widest blast radius and list the rest.
- When the whole patch covers at most two files and 20 changed lines, this rule overrides the three-hunk cap: inline every hunk.
- When an inline hunk exceeds 40 lines, print it with one line of context and label the block outside the fence as an excerpt that is not applyable.
- Never hide a correctness concern to fit the inline budget. A hunk whose risk the user cannot judge from the list belongs inline, or in the list with its risk named.

## Modification summary

Close every preview with a short modification summary between the diff and the completion statement. Match the user's language in the heading and in each line.

1. One line per proposed file change, in patch order: `<path> — <what changes> (<+added/-removed>)`. Omit files with no proposed change.
2. Describe the behavior change, not the diff structure. No hunk numbers, repeated code, or validation detail.
3. Keep it short. Group mechanical repeats of the same change into one line that names the affected files.
4. Do not restate an inline diff in prose. A preview whose changes are all visible inline needs no per-file lines beyond its header line.

The summary restates the proposal in one screen. It never introduces a change that no hunk in the artifact covers.

## Checkpoint

After a preview, STOP before implementation unless the latest request explicitly authorizes applying the patch and a complete proposal is available. A request for hunks continues the preview; it does not authorize application.

| Control | Action | Where to stop |
|---|---|---|
| `expand <hN> ...` | Print those hunks verbatim from the artifact, or from the conversation when the preview is unbacked. | At the checkpoint. |
| `full` | Print the complete patch as one sequence of per-file `diff` blocks. | At the checkpoint. |
| `revise` | Incorporate the requested changes, rewrite the artifact, and reprint the conversation format and its summary with renumbered hunks. | At the checkpoint. |
| `ask` | Answer the question from the proposal and relevant local evidence. If the answer changes the solution, identify the affected hunk without silently revising it. | After the answer and confirmation line. No implementation. |
| `apply` | Implement the previewed solution against the currently inspected source, including changes held only in the artifact. | After reporting the applied changes and their validation status. |

Omit the confirmation line only when the user requests no confirmation. Omission alone does not authorize application.

End every preview response with exactly this line, last, after the modification summary and the completion statement:

`Confirm: apply? (apply / revise / ask / full / expand <hN>)`

## Completion

State that project files remain unchanged, and give the artifact path so the user can open, diff, or delete it. If the proposed code has not run, say so explicitly; passing checks on the original code do not validate the proposal. When blocked, name the missing fact and ask for that fact instead of inventing a patch. If inspection shows no change is needed, state the evidence and produce no artificial diff.
