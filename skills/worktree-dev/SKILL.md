---
name: worktree-dev
description: Git worktree creation, isolated parallel development, merging back, cleanup, or explicit worktree-dev finish.
---

# Worktree Development

Parallel development in isolated worktrees at `.worktrees/<branch>` inside the
repo. Every worktree carries an untracked `WORKTREE-README.md` stating why it
exists; read those before creating a new one. `<base-branch>` = branch the work
merges back into.

## Invocation

`worktree-dev finish` runs the finish workflow below and explicitly authorizes
five actions, no separate approval: stage task-related hunks, commit, rebase the
task branch onto the base branch, fast-forward the base branch, remove the
completed worktree. Editing or explaining this skill does not invoke finish.
Other requests authorize only the actions they name.

## Quick start

```bash
git check-ignore .worktrees/ || echo ".worktrees/" >> .gitignore  # once per repo
git worktree list --porcelain |
while IFS= read -r line; do case "$line" in worktree\ *) f="${line#worktree }/WORKTREE-README.md"; [ ! -f "$f" ] || { printf '== %s\n' "$f"; cat "$f"; };; esac; done
git worktree add .worktrees/<branch> -b <branch> <base-branch>
```

Then write `WORKTREE-README.md` (template below), develop, verify. No stage,
commit, sync, merge, or cleanup unless the user explicitly asks.

## Workflow

1. **Ignore check (once per repo)** — `.worktrees/` must be git-ignored:
   ```bash
   git check-ignore .worktrees/ || echo ".worktrees/" >> .gitignore
   ```

2. **Dedup before create** — read every existing worktree's purpose:
   ```bash
   git worktree list --porcelain |
   while IFS= read -r line; do case "$line" in worktree\ *) f="${line#worktree }/WORKTREE-README.md"; [ ! -f "$f" ] || { printf '== %s\n' "$f"; cat "$f"; };; esac; done
   ```
   Reuse a worktree that already covers the goal; create new only when no README
   matches.

3. **Create** the worktree:
   ```bash
   git worktree add .worktrees/<branch> -b <branch> <base-branch>  # new branch
   git worktree add .worktrees/<branch> <branch>                    # existing branch
   ```

4. **Write WORKTREE-README.md** in the worktree root, untracked — never commit
   it:
   ```markdown
   # Worktree: <branch>
   - Purpose: <what this worktree is for, one or two sentences>
   - Created: <date>, from <task / context / issue ref>
   - Base branch: <branch to merge back into>
   - Status: in-progress | merged | abandoned
   ```
   Update `Status` as work progresses.

5. **Develop and verify** inside the worktree. Run repo tests/checks; leave
   changes unstaged and uncommitted by default. Never `git add`/`git commit`
   unless the user explicitly asks.

6. **Commit — only when the user asks.** Inspect status and diff, stage only
   requested hunks, run checks, commit. Creating, developing, or verifying a
   worktree is not permission to commit.

7. **Sync or merge back — only when the user asks for it.** A commit request does
   not authorize sync or merge. After commit: rebase, then fast-forward; never a
   merge commit:
   ```bash
   git -C .worktrees/<branch> rebase <base-branch>
   git merge --ff-only <branch>   # run from the base branch's checkout
   ```

8. **Cleanup — only when the user asks.** Never remove a worktree on your own; a
   merged one may stay for reuse or reference. On request, read the README first
   to confirm purpose fulfilled and merged, then:
   ```bash
   rm .worktrees/<branch>/WORKTREE-README.md
   git worktree remove .worktrees/<branch>
   git branch -d <branch>
   git worktree prune
   ```
   `remove` failing on untracked files: investigate them — no blind `--force`.

## Finish workflow

1. **Identify the target.** Read `git worktree list --porcelain` and the target's
   `WORKTREE-README.md`. Resolve worktree, task scope, base branch, base checkout
   from invocation, README, task context. No base branch in an older README: use
   repository evidence; ask only if still ambiguous. Inspect status, staged and
   unstaged diffs, commits in `<base-branch>..<branch>`; every commit to merge
   must belong to the requested task. Stop on an unfinished merge/rebase or
   unrelated staged changes: preserve them, report the blocker.

2. **Stage related hunks.** Staging stays here: the `commit-stage` skill
   reviews an already-staged diff and never stages. `git add -p -- <paths>` for
   task-related hunks only; split mixed hunks. No interactive terminal: build a
   patch of the selected changes, `git apply --cached`, delete the temp patch.
   Path-level `git add -- <path>` only when the whole change belongs to the task,
   new files included. Never stage `WORKTREE-README.md`. Check `git diff --cached`,
   `git diff --cached --check`; proceed only when the staged diff holds all
   intended changes, nothing unrelated.

3. **Verify and commit.** When a `commit-stage` skill is available, run it for
   this step: it reviews the staged diff and commits, or stops with a report, and
   a stopped commit blocks merge and cleanup like a failed check. Otherwise run
   the inline procedure: run checks for the staged change; isolate the staged
   snapshot if unrelated unstaged edits affect validation. Fix task-caused
   failures, review the staged diff again. Commit with a Conventional Commits
   message, `<type>[optional scope]: <description>`; record the hash. No new task
   changes: skip the empty commit, keep existing task commits.

4. **Rebase the task branch onto the base branch.** Run
   `git -C .worktrees/<branch> rebase <base-branch>` before touching the base
   branch: a task branch not descending from `<base-branch>` is what turns the
   merge into a merge commit. Resolve conflicts where task intent is clear,
   re-run checks on the result. Conflict needing user input, or failed checks:
   `git -C .worktrees/<branch> rebase --abort` restores the pre-rebase state;
   keep the worktree, report the blocker. Confirm the rebase landed:
   `git merge-base --is-ancestor <base-branch> <branch>` succeeds,
   `git log -1 --format=%p <branch>` shows one parent. Rebase rewrites the task
   commits: report the post-rebase hash from
   `git -C .worktrees/<branch> log -1 --format=%H`.

5. **Fast-forward the base branch.** Clean checkout of `<base-branch>`: its
   existing worktree, else a temporary checkout. Dirty base checkout: preserve
   unrelated changes, report the blocker. Then
   `git -C <base-checkout> merge --ff-only <branch>`. Plain `git merge`,
   `git merge -m`, `--no-ff` forbidden here — they produce the extra merge
   commit. `--ff-only` refused: base advanced after the rebase, or step 4 was
   skipped — redo the rebase, retry; never fall back to a merge commit. Continue
   only when checks pass and three proofs hold:
   `git merge-base --is-ancestor <branch> <base-branch>`,
   `git -C <base-checkout> log -1 --format=%p` printing one hash,
   `git rev-list --count <branch>..<base-branch>` printing `0`. Finish is local;
   no push.

6. **Remove the completed worktree.** Inspect tracked, untracked, ignored files
   first. Unrelated edits or files remain: keep the worktree, report cleanup
   blocked; no automatic discard or stash. Remove only the task's untracked
   `WORKTREE-README.md` and known disposable generated outputs, via
   `git worktree remove <worktree-path>` from outside that worktree, no `--force`.
   Remove a temporary base checkout created above once clean. Verify the target is
   gone from `git worktree list`. Finish need not delete the branch. Report the
   post-rebase commit hash, base branch, validation result, whether worktree
   removal completed.

## Rules

- Never stage or commit by default; an explicit user request is required.
- Merging a task branch never creates a merge commit: rebase onto the base branch
  first, then `git merge --ff-only`. Plain `git merge`, `-m`, `--no-ff` not
  allowed. An `ort`/`Merge made by` reflog entry means the rebase was skipped.
- One branch cannot be checked out in two worktrees at once.
- Untracked and ignored files do not transfer: build outputs, `node_modules`,
  venv are per-worktree; recreate them.
- Submodules need `git submodule update --init` inside each new worktree.
- Never commit `WORKTREE-README.md` or anything under `.worktrees/`.
- `git worktree prune` only cleans stale metadata; it does not delete
  directories.
- Worktrees share one object store: cheap on disk, but `gc` runs repo-wide.
