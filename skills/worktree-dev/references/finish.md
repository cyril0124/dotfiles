# Finish worktree-dev

Use this workflow only for the `worktree-dev finish` invocation defined in
`../SKILL.md`. `<worktree>` is the target path; `<base-checkout>` is the clean
checkout of `<base-branch>`.

1. **Identify the target.** Read `git worktree list --porcelain` and the target's
   `WORKTREE-README.md`. Resolve worktree, task scope, base branch, and base
   checkout from the invocation, README, and task context. If an older README
   lacks a base branch, use repository evidence; ask only if still ambiguous.
   Inspect status, staged and unstaged diffs, and commits in
   `<base-branch>..<branch>`. Every commit must belong to the requested task.
   Stop on an unfinished merge/rebase, unrelated staged changes, or unrelated
   commits; preserve them and report the blocker.

2. **Stage related hunks.** Use `git add -p -- <paths>` and split mixed hunks.
   Without an interactive terminal, apply a patch of selected changes with
   `git apply --cached`, then delete the temporary patch. Use path-level
   `git add -- <path>` only when the whole file belongs to the task, including
   new files. Never stage `WORKTREE-README.md`. Continue only when
   `git diff --cached` contains every intended change and nothing unrelated, and
   `git diff --cached --check` passes.

3. **Verify and commit.** If no new task changes exist, skip the empty commit
   and keep existing task commits. Otherwise, when a `commit-stage` skill is
   available, run it on the staged diff; a stopped commit blocks merge and
   cleanup. Without it, review every staged line for scope, project rules,
   temporary artifacts, security/privacy, correctness, readability, and doc
   drift. Run checks for the staged snapshot, isolating it if unrelated unstaged
   edits affect validation. Fix task-caused failures, restage, and review again;
   unresolved failures block merge and cleanup. Commit with
   `<type>[optional scope]: <description>` and record the hash.

4. **Rebase the task branch.** Record the pre-rebase hash, then run:
   ```bash
   git -C <worktree> rebase <base-branch>
   ```
   Resolve conflicts where task intent is clear, continue the rebase, and rerun
   checks on the result. If resolution needs user input, abort while the rebase
   is still in progress; keep the worktree and report the blocker. If checks fail
   after the rebase completes, stop, preserve the rewritten branch and worktree,
   and report both hashes; `rebase --abort` cannot restore a completed rebase.
   Continue only when the base is an ancestor and the task tip has one parent:
   ```bash
   git merge-base --is-ancestor <base-branch> <branch>
   git -C <worktree> log -1 --format='%H %p'
   ```
   Record the post-rebase hash for the final report.

5. **Fast-forward the base branch.** Use its existing clean checkout or create a
   temporary one. Preserve and report a dirty base checkout. Then run:
   ```bash
   git -C <base-checkout> merge --ff-only <branch>
   ```
   If refused, the base advanced or the rebase was skipped: rebase again and
   retry; no other merge mode is allowed. Run checks on the base result.
   Continue only when base `HEAD` equals `<branch>` and its tip has one parent:
   ```bash
   test "$(git -C <base-checkout> rev-parse HEAD)" = "$(git rev-parse <branch>)"
   git -C <base-checkout> log -1 --format=%p
   ```

6. **Remove the completed worktree.** Inspect tracked, untracked, and ignored
   files again. Unknown or unrelated files block cleanup; preserve them without
   discarding or stashing. Delete only the task README and known disposable
   outputs, recheck the remaining files, then run from outside the worktree:
   ```bash
   rm -- <worktree>/WORKTREE-README.md
   git worktree remove <worktree>
   ```
   Never use `--force`. Remove a temporary base checkout once clean. Verify the
   target is absent from `git worktree list`; the task branch may remain. Report
   the post-rebase hash, base branch, validation result, and cleanup outcome.
