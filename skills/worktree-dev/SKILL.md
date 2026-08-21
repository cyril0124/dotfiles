---
name: worktree-dev
description: Parallel development with git worktrees inside the repo at `.worktrees/<branch>`, each tracked by an untracked WORKTREE-README.md stating its purpose, with a dedup check before creation and read-before-cleanup. Use when user mentions "worktree", "parallel development", "parallel branch", wants isolated branch work without stashing, or asks to create, merge back, or clean up worktrees.
---

# Worktree Development

Parallel development in isolated worktrees at `.worktrees/<branch>` inside the
repo. Every worktree carries an untracked `WORKTREE-README.md` stating why it
exists; read those files before creating a new one. `<base-branch>` means the
branch the work will merge back into.

## Quick start

```bash
git check-ignore .worktrees/ || echo ".worktrees/" >> .gitignore  # once per repo
git worktree list --porcelain |
while IFS= read -r line; do case "$line" in worktree\ *) f="${line#worktree }/WORKTREE-README.md"; [ ! -f "$f" ] || { printf '== %s\n' "$f"; cat "$f"; };; esac; done
git worktree add .worktrees/<branch> -b <branch> <base-branch>
```

Then write `WORKTREE-README.md` (template below), develop, sync, and merge
back. Clean up only when the user asks.

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
   - Status: in-progress | merged | abandoned
   ```
   Update `Status` as work progresses.

5. **Develop** inside the worktree; commit as usual:
   ```bash
   git -C .worktrees/<branch> add ... && git -C .worktrees/<branch> commit
   ```

6. **Sync and verify** in the worktree before merging:
   ```bash
   git -C .worktrees/<branch> rebase <base-branch>   # or merge <base-branch>
   # then run the repo's tests/checks inside the worktree
   ```

7. **Merge back** from the base branch's checkout:
   ```bash
   git merge <branch>   # or push from the worktree and open a PR
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

## Rules

- One branch cannot be checked out in two worktrees at once.
- Untracked and ignored files do not transfer: build outputs, `node_modules`,
  venv are per-worktree; recreate them.
- Submodules need `git submodule update --init` inside each new worktree.
- Never commit `WORKTREE-README.md` or anything under `.worktrees/`.
- `git worktree prune` only cleans stale metadata; it does not delete
  directories.
- Worktrees share one object store: cheap on disk, but `gc` runs repo-wide.
