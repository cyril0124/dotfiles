---
description: "用于基于当前 Git Staged Changes 的代码生成 git commit message"
---

用于基于当前 Git Staged Changes 的代码生成 git commit message, 满足以下要求:

- **永远重新读取**最新的 Staged 信息, 不使用历史对话记录中的代码信息
- 不要使用未添加(使用 git add 添加的)到 Stage 的代码
- 生成的 git commit message 要参考历史的 git commit message 格式
- 提供**三个版本的 message**, 不需要其他额外的信息给我
- 生成的 git commit message 是**英文**的
- **重要**：不需要帮我执行 git commit 命令，不要执行任何会改变 Git Staged 代码的命令，你的任务只是生成 git commit message

你的输出格式为：
```text
# Version 1
<git commit message>

# Version 2
<git commit message>

# Version 3
<git commit message>
```
除此之外不要有多余的输出，除非我有另外要求你

$ARGUMENTS
