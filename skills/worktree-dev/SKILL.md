---
name: worktree-dev
description: Use when creating or reusing Git worktrees for isolated parallel development, committing or integrating task branches on request, cleaning up worktrees, or running `worktree-dev finish`.
---

# Worktree Development

Develop at `.worktrees/<branch>` inside the repo. `<base-branch>` receives the
finished task. Every task worktree has an untracked `WORKTREE-README.md` stating
its purpose and lifecycle.

## Invocation

`worktree-dev finish` reads [the finish workflow](references/finish.md) and
explicitly authorizes five actions without separate approval: stage task-related
hunks, commit, rebase the task branch, fast-forward `<base-branch>`, and remove
the completed worktree. Finish is local; no push.

Other requests authorize only the actions they name. Editing or explaining this
skill performs no worktree action.

## Workflow

1. **Ignore once per repo:**
   ```bash
   git check-ignore .worktrees/ || echo ".worktrees/" >> .gitignore
   ```

2. **Deduplicate before creation.** List every worktree and read its purpose;
   inspect any missing README manually:
   ```bash
   git worktree list --porcelain |
   while IFS= read -r line; do
     case "$line" in worktree\ *)
       root="${line#worktree }"
       printf '\n== %s\n' "$root"
       cat "$root/WORKTREE-README.md" 2>/dev/null ||
         printf 'README missing; inspect this worktree before creating another\n'
     ;;
     esac
   done
   ```
   Reuse a worktree that covers the goal; create one only when none matches.

3. **Create:**
   ```bash
   git worktree add .worktrees/<branch> -b <branch> <base-branch>  # new branch
   git worktree add .worktrees/<branch> <branch>                    # existing branch
   ```

4. **Write `WORKTREE-README.md` in the worktree root:**
   ```markdown
   # Worktree: <branch>
   - Purpose: <what this worktree is for, one or two sentences>
   - Created: <date>, from <task / context / issue ref>
   - Base branch: <branch to merge back into>
   - Status: in-progress | merged | abandoned
   ```
   Update `Status` as work progresses.

5. **Develop and verify.** Run repo checks; leave changes unstaged and
   uncommitted by default. Recreate untracked and ignored dependencies such as
   build outputs, `node_modules`, and venvs in each worktree. Run
   `git submodule update --init` when the repo uses submodules.

6. **Commit only on request.** Inspect status and diff, stage only requested
   task hunks, run checks, and commit with a Conventional Commits message.
   Committing does not authorize integration.

7. **Integrate only on request.** Rebase the task branch, then fast-forward from
   a clean `<base-branch>` checkout:
   ```bash
   git -C .worktrees/<branch> rebase <base-branch>
   git -C <base-checkout> merge --ff-only <branch>
   ```
   Preserve and report a dirty base checkout. If `--ff-only` refuses, rebase
   again and retry; only `--ff-only` is allowed for the merge.

8. **Clean up only on request.** Read the README, confirm the work is merged or
   abandoned, and inspect tracked, untracked, and ignored files before deleting
   anything. Preserve unknown or unrelated work and report the blocker. Remove
   only the task README and known disposable outputs, then run from outside the
   worktree:
   ```bash
   rm .worktrees/<branch>/WORKTREE-README.md
   git worktree remove .worktrees/<branch>
   git branch -d <branch>
   git worktree prune
   ```
   If removal or branch deletion fails, investigate and preserve the remainder;
   no `--force`, `-D`, automatic discard, or stash.

## Constraints

- One branch cannot be checked out in two worktrees at once.
- Never commit `WORKTREE-README.md` or anything under `.worktrees/`.
- `git worktree prune` cleans stale metadata, not directories.
- Worktrees share one object store: `gc` runs repo-wide.
