---
name: worktree-dev
description: Use for Git worktree creation, isolated parallel development, merging back, cleanup, or explicit worktree-dev finish.
---

# Worktree Development

Parallel development in isolated worktrees at `.worktrees/<branch>` inside the
repo. Every worktree carries an untracked `WORKTREE-README.md` stating why it
exists; read those files before creating a new one. `<base-branch>` means the
branch the work will merge back into.

## Invocation

`worktree-dev finish` runs the finish workflow below. This invocation explicitly
authorizes staging task-related hunks, committing, merging into the base branch,
and removing the completed worktree. Proceed through all four actions without
asking for separate approval. A request to edit or explain this skill does not
invoke finish. Other requests authorize only the actions they name.

## Quick start

```bash
git check-ignore .worktrees/ || echo ".worktrees/" >> .gitignore  # once per repo
git worktree list --porcelain |
while IFS= read -r line; do case "$line" in worktree\ *) f="${line#worktree }/WORKTREE-README.md"; [ ! -f "$f" ] || { printf '== %s\n' "$f"; cat "$f"; };; esac; done
git worktree add .worktrees/<branch> -b <branch> <base-branch>
```

Then write `WORKTREE-README.md` (template below), develop, and verify. Do not
stage, commit, sync, merge, or clean up unless the user explicitly asks for
that action.

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
   If an existing worktree already covers the goal, reuse it instead of
   creating a duplicate. Create a new one only when no README matches.

3. **Create** the worktree:
   ```bash
   git worktree add .worktrees/<branch> -b <branch> <base-branch>  # new branch
   git worktree add .worktrees/<branch> <branch>                    # existing branch
   ```

4. **Write WORKTREE-README.md** in the worktree root. Keep it untracked —
   never commit it:
   ```markdown
   # Worktree: <branch>
   - Purpose: <what this worktree is for, one or two sentences>
   - Created: <date>, from <task / context / issue ref>
   - Base branch: <branch to merge back into>
   - Status: in-progress | merged | abandoned
   ```
   Update `Status` as work progresses.

5. **Develop and verify** inside the worktree. Run the repo's tests/checks and
   leave all changes unstaged and uncommitted by default. Never run `git add`
   or `git commit` unless the user explicitly asks.

6. **Commit — only when the user asks.** Inspect status and diff, stage only
   the requested hunks, run relevant checks, then commit. A request to create,
   develop, or verify a worktree is not permission to commit.

7. **Sync or merge back — only when the user asks for that action.** A commit
   request does not authorize syncing or merging. After work is committed:
   ```bash
   git -C .worktrees/<branch> rebase <base-branch>
   git merge <branch>   # run from the base branch's checkout
   ```

8. **Cleanup — only when the user asks.** Never remove a worktree on your
   own initiative; a merged worktree may stay for later reuse or reference.
   When the user asks for cleanup, read the README first to confirm the
   purpose is fulfilled and merged, then:
   ```bash
   rm .worktrees/<branch>/WORKTREE-README.md
   git worktree remove .worktrees/<branch>
   git branch -d <branch>
   git worktree prune
   ```
   If `remove` still fails on untracked files, investigate them — do not
   blindly `--force`.

## Finish workflow

1. **Identify the target.** Read `git worktree list --porcelain` and the target's
   `WORKTREE-README.md`. Resolve the worktree, task scope, base branch, and base
   checkout from the invocation, README, and current task context. For older
   READMEs without a base branch, use repository evidence; ask only if the target
   or base remains ambiguous. Inspect status, staged and unstaged diffs, and
   commits in `<base-branch>..<branch>`. Every commit being merged must belong to
   the requested task. Stop on an unfinished merge/rebase or unrelated staged
   changes; preserve them and report the blocker.

2. **Stage related hunks.** Use `git add -p -- <paths>` to select only task-related
   hunks, splitting mixed hunks as needed. Without an interactive terminal,
   construct a patch containing only the selected changes and apply it with
   `git apply --cached`; remove the temporary patch afterward. Use path-level
   `git add -- <path>` only when the entire change belongs to the task, including
   new files. Never stage `WORKTREE-README.md`. Inspect `git diff --cached` and
   `git diff --cached --check`; proceed only when the staged diff contains all
   intended changes and no unrelated changes.

3. **Verify and commit.** Run the checks appropriate to the staged change. If
   unrelated unstaged edits would affect validation, isolate the staged snapshot
   for checks. Fix failures caused by the task and review the staged diff again.
   Commit with a Conventional Commits message, `<type>[optional scope]: <description>`,
   and record the commit hash. If there are no new task changes, skip the empty
   commit and continue with existing task commits. A failed check or commit blocks
   merging and cleanup.

4. **Merge into the base branch.** Use a clean checkout of `<base-branch>`; locate
   its existing worktree or create a temporary checkout if it has none. Preserve
   unrelated changes in a dirty base checkout and report the blocker. Merge with
   `git -C <base-checkout> merge -m "chore: merge <branch>" <branch>`; no rebase is required.
   Resolve conflicts when task intent is clear, then run relevant checks on the
   merged result. If resolution needs user input or checks fail, report the state
   and keep the task worktree. Continue only after checks pass and
   `git merge-base --is-ancestor <branch> <base-branch>` succeeds. Finish is local;
   it does not authorize pushing.

5. **Remove the completed worktree.** Inspect tracked, untracked, and ignored
   files before removal. If unrelated edits or files remain, keep the worktree
   and report that cleanup is blocked; do not discard or stash them automatically.
   Remove only the task's untracked `WORKTREE-README.md` and known disposable
   generated outputs. Run `git worktree remove <worktree-path>` from outside that
   worktree, without `--force`. Remove a temporary base checkout created above
   once it is clean. Verify the target is absent from `git worktree list`.
   Finish does not require deleting the branch. Report the commit hash, base
   branch, validation result, and whether worktree removal completed.

## Rules

- Never stage or commit by default; an explicit user request is required.
- One branch cannot be checked out in two worktrees at once.
- Untracked and ignored files do not transfer: build outputs, `node_modules`,
  venv are per-worktree; recreate them.
- Submodules need `git submodule update --init` inside each new worktree.
- Never commit `WORKTREE-README.md` or anything under `.worktrees/`.
- `git worktree prune` only cleans stale metadata; it does not delete
  directories.
- Worktrees share one object store: cheap on disk, but `gc` runs repo-wide.
