---
description: "优化 xmake.lua 的文件的编写风格"
---

优化当前工程的 xmake.lua（只有一个 xmake.lua，所有其他的 xmake.lua 不需要优化），满足下面的要求：

## 在 xmake.lua 的最开头添加类型注释设置
需要在文件开头添加：
```lua
---@diagnostic disable: undefined-global, undefined-field
```
否则 Lua 的 LSP 会报错。

不能只用 `---@diagnostic disable`

## target 和 task 要用 function 包起来
Bad:
```lua
target("name")
    set_kind("phony")
    on_run(function()
        print("hello")
    end)
```

Good:
```lua
target("name", function()
    set_kind("phony")
    on_run(function()
        print("hello")
    end)
end)
```

其他注意点：
- 不要保留 task\_end() 这种显式结束 xmake 作用域的语法，因为 function 包起来后已经有这个功能了

## 使用 path.join 而不是字符串拼接路径
Bad:
```lua
local some_path = "./path/to" .. "/" .. "another"
```

Good:
```lua
local some_path = path.join("path", "to", "another")
```

注意有些并不是真正的路径拼接，例如：
`os.exec("git -C " .. xxx_dir .. " pull origin master")`
这种情况下不需要进行替换

## 修改完成后，执行格式化

### 步骤 1：检测 CodeFormat 是否可用

按以下优先级检测 CodeFormat：
1. 检查 PATH 中是否存在 CodeFormat 命令
2. 检查 ~/.cache/optimize-xmake/linux-x64/bin/CodeFormat 是否存在且可执行

### 步骤 2：安装 CodeFormat（如需要）

如果以上检测都失败，需要手动安装：

```bash
# 创建缓存目录
mkdir -p ~/.cache/optimize-xmake

# 下载最新版本（linux-x64）
cd ~/.cache/optimize-xmake
curl -L -o codeformat.tar.gz https://github.com/CppCXY/EmmyLuaCodeStyle/releases/download/1.6.0/linux-x64.tar.gz

# 解压
tar -xzf codeformat.tar.gz

# 设置可执行权限
chmod +x linux-x64/bin/CodeFormat

# 清理压缩文件（可选）
rm codeformat.tar.gz
```

**注意：**
- 下载链接中的版本号（1.6.0）可以根据需要更新
- 解压后可执行文件位于 `~/.cache/optimize-xmake/linux-x64/bin/CodeFormat`

### 步骤 3：执行格式化

```bash
# 如果 CodeFormat 在 PATH 中
CodeFormat format --file xmake.lua --overwrite

# 或使用绝对路径
~/.cache/optimize-xmake/linux-x64/bin/CodeFormat format --file xmake.lua --overwrite
```

### 自动化脚本（可选）

如果需要自动化检测和安装，可以使用以下逻辑：

```bash
#!/bin/bash

# 检测 CodeFormat
if command -v CodeFormat &>/dev/null; then
    CODEFORMAT_CMD="CodeFormat"
elif [[ -x "$HOME/.cache/optimize-xmake/linux-x64/bin/CodeFormat" ]]; then
    CODEFORMAT_CMD="$HOME/.cache/optimize-xmake/linux-x64/bin/CodeFormat"
else
    echo "CodeFormat 未找到，开始安装..."
    mkdir -p ~/.cache/optimize-xmake
    cd ~/.cache/optimize-xmake
    curl -L -o codeformat.tar.gz https://github.com/CppCXY/EmmyLuaCodeStyle/releases/download/1.6.0/linux-x64.tar.gz
    tar -xzf codeformat.tar.gz
    chmod +x linux-x64/bin/CodeFormat
    rm codeformat.tar.gz
    CODEFORMAT_CMD="$HOME/.cache/optimize-xmake/linux-x64/bin/CodeFormat"
fi

# 执行格式化
$CODEFORMAT_CMD format --file xmake.lua --overwrite
```

## 注意
- 确保不要去除原有文件中就存在的注释
- 完成所有修改后，需要重复校验一遍，确保上面所有的规则你都符合
- 确保修改完成后，还是符合原有的 xmake.lua 的功能逻辑

---

$ARGUMENTS
