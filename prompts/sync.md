---
description: 同步最新 master 并更新 PR
argument-hint: "[base-branch]"
---

把当前分支同步到最新 `${1:-master}`，然后更新到 PR。

- `git fetch origin`，先确认 `${1:-master}` 的最新提交
- `git rebase ${1:-master}`；冲突自己解决，解完 `git rebase --continue`，不要用 merge commit 绕过
- 两边重复实现了同一功能时，保留 `${1:-master}` 的版本
- `git push --force-with-lease` 更新 PR；推不动就报告原因，不要换分支
- 报告：rebase 前后的 HEAD、冲突文件、push 结果
