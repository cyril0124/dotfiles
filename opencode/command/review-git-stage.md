---
description: "Review 当前 Git Staged Changes 的代码"
---

Review 当前 Git Staged Changes 的代码，满足以下要求：

- 不需要 Review 未使用 git add 添加到 Stage 的代码, 但为了获得完整的代码内容以便完整评估修改的内容是否合理，在需要的时候你可以读取相关的其他代码内容
- 永远都要重新读取你要 Review 的内容，不要使用历史对话信息中的代码
- 如果这是 Bug 的修复，同时要确保项目中的其他代码不会出现其他类似的问题
- 你还可以检查 Stage 的中的拼写、变量命名是否合理(此时不需要管其他非 Stage 的代码内容)
- 注意需要关注代码的性能、质量、注释是否足够且清晰

$ARGUMENTS
