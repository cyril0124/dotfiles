---
name: clone-pr
description: "Clone a GitHub PR into ./tmp/pr<N>-<slug> on the exact PR head branch for local edits."
---

# Clone PR

Clone a PR into `./tmp/pr<N>-<slug>` on the **same branch as the PR head**.

## Steps

1. Resolve PR (prefer URL; bare number needs cwd repo or `owner/repo`):

```bash
gh pr view <pr-url|number> [--repo owner/repo] \
  --json number,title,headRefName,headRepository,headRepositoryOwner,url
```

2. Build the dir name `pr<number>-<slug>` — slug short, readable, from branch/title/intent. Never overwrite an existing path: if `./tmp/pr<N>-<slug>` exists, append `-1`, then `-2`, … until free.

```bash
base=./tmp/pr<number>-<slug>; dir=$base; i=1
while [ -e "$dir" ]; do dir=$base-$i; i=$((i+1)); done; echo "$dir"
```

3. Clone the **head** repo on the **head branch**:

```bash
mkdir -p ./tmp
gh repo clone <headOwner>/<headRepo> "$dir" -- --branch <headRefName> --single-branch
```

4. Verify branch matches PR head:

```bash
git -C "$dir" branch --show-current   # must equal headRefName
```

Mismatch → stop and report. Do not fall back to detached `pull/N/head` unless the named head branch is gone and the user accepts it.

5. Report: path, branch, PR URL. Do further work inside that path.

## After clone

Edit code as requested. **Do not** `git commit` or `git push` (or `gh pr create` / force-push) unless the user explicitly asks.

## Notes

- Needs authenticated `gh`.
- Head repo may be a fork — always clone head, not only base.
