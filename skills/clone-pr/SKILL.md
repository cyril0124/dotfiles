---
name: clone-pr
description: "Clone a GitHub PR into ./tmp/<slug> on the exact PR head branch for local edits."
---

# Clone PR

Clone a PR into `./tmp/<slug>` on the **same branch as the PR head**.

## Steps

1. Resolve PR (prefer URL; bare number needs cwd repo or `owner/repo`):

```bash
gh pr view <pr-url|number> [--repo owner/repo] \
  --json number,title,headRefName,headRepository,headRepositoryOwner,url
```

2. Pick `./tmp/<slug>` yourself — short, readable, from branch/title/intent. Not required to include the PR number. If the path exists, stop (no overwrite).

3. Clone the **head** repo on the **head branch**:

```bash
mkdir -p ./tmp
gh repo clone <headOwner>/<headRepo> ./tmp/<slug> -- --branch <headRefName> --single-branch
```

4. Verify branch matches PR head:

```bash
git -C ./tmp/<slug> branch --show-current   # must equal headRefName
```

Mismatch → stop and report. Do not fall back to detached `pull/N/head` unless the named head branch is gone and the user accepts it.

5. Report: path, branch, PR URL. Do further work inside that path.

## After clone

Edit code as requested. **Do not** `git commit` or `git push` (or `gh pr create` / force-push) unless the user explicitly asks.

## Notes

- Needs authenticated `gh`.
- Head repo may be a fork — always clone head, not only base.
