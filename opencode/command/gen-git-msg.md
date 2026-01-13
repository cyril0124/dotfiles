---
description: "用于基于当前 Git Staged Changes 的代码生成 git commit message"
---

用于基于当前 Git Staged Changes 的代码生成 git commit message, 满足以下要求:

- 永远重新读取最新的 Staged 信息, 不使用历史对话记录中的代码信息
- 不要使用未添加(使用 git add 添加的)到 Stage 的代码
- 生成的 git commit message 要参考历史的 git commit message 格式
- 提供三个版本的 message, 不需要其他额外的信息给我
- 生成的 git commit message 是英文的

$ARGUMENTS
