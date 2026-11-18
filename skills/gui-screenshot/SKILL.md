---
name: gui-screenshot
description: Use Xpra to launch Linux desktop apps, map windows, capture and annotate screenshots, and verify the result. Use for GUI walkthroughs, documentation images, and troubleshooting blank captures or hidden dialogs.
---

# GUI Screenshots

运行 `xpra list`，确认可用会话。按以下 5 步截取目标程序，逐张看图验收。

脚本路径相对于本 Skill 目录；在其他目录执行时，换成绝对路径。

## 1. Launch the App

1. 选未占用的 `DISPLAY_ID`；复用已有会话时，记录原有窗口。
2. 检查依赖：`xpra`、`Xvfb`、Python 3.10+、Pillow；按键需要 `xmodmap`，实时 X11 截图需要 Pillow 的 XCB 支持。缺项时先报告。
3. 将 `APP_COMMAND` 设为应用及参数，选择系统 Xvfb：

```bash
if [ -x /usr/bin/Xvfb ]; then
  XVFB=/usr/bin/Xvfb
else
  XVFB="$(command -v Xvfb)"
fi
```

通过进程管理工具启动下面的前台命令，监听 `xpra is ready`。显式指定独立工作目录，保存 display、进程 ID 和日志。

```bash
xpra start "$DISPLAY_ID" --daemon=no --use-display=no \
  --xvfb="$XVFB -screen 0 1440x1000x24 -nolisten tcp +extension Composite" \
  --resize-display=1440x1000 --pulseaudio=no --audio=no \
  --notifications=no --webcam=no --mdns=no --html=off --dbus=no \
  --start-child="$APP_COMMAND" --terminate-children=yes --exit-with-children=yes
```

需要放大或最大化窗口时，用完整桌面和窗口管理器：

- 将 `xpra start` 换成 `xpra start-desktop`，并额外添加 `--start-child=fluxbox`，保留应用的 `--start-child`。
- 将 `-screen 0` 和 `--resize-display` 的尺寸同时改为所需画布，例如 `1800x1060`。
- 确认 `fluxbox` 可用后，按实时全图中的标题栏位置，用第 3 节的 `click` 聚焦应用，再最大化：

```bash
python3 scripts/xpra_capture.py key "$DISPLAY_ID" Alt_L+F10
```

完整桌面下，Xpra 查询可能只返回桌面 ID；最大化前应聚焦实际应用标题栏。`Alt_L+F10` 对应 Fluxbox 默认的 `Mod1 F10 :Maximize`；若本机改过键位，先核对配置。应用的 `-geometry` 参数不保证生效，以实际窗口尺寸和截图为准。Xpra 会在会话结束时关闭应用和窗口管理器子进程。

复用已有会话时，只单独启动应用：

```bash
env DISPLAY="$DISPLAY_ID" /absolute/path/to/application
```

**完成条件：** 会话就绪，目标应用已启动。

## 2. Show the Target Window

```bash
python3 scripts/xpra_capture.py windows "$DISPLAY_ID"
python3 scripts/xpra_capture.py map "$DISPLAY_ID" <window-id>
```

按 `title` 和 `geometry` 确认目标，再映射当前 ID。`shown=false` 的窗口可能已启动但未显示；菜单的 `shown=null` 不能证明它不可见，先截图确认。

**完成条件：** 截图中能看到正确应用。菜单或对话框出现后，重新查询 ID，只映射画面中缺失的窗口。

## 3. Interact and Capture

1. 截当前画面，打开图片确定下一步。
2. 用命名按键打开目标菜单，已确定的序列合并到一次调用：

```bash
python3 scripts/xpra_capture.py key "$DISPLAY_ID" --window <window-id> Alt_L+f
python3 scripts/xpra_capture.py key "$DISPLAY_ID" Down Right Down
```

`--window` 设置初始焦点；操作已打开的菜单时省略它。脚本按当前 display 的键位映射发送 X11 keysym，每个组合键后释放按键。每展开一级，截图确认位置。文本输入使用应用 API 或已有自动化工具。

点菜单、页签、表格行，或拖列宽时，用鼠标工具：

```bash
python3 scripts/xpra_pointer.py click "$DISPLAY_ID" 200 160
python3 scripts/xpra_pointer.py move "$DISPLAY_ID" 200 240
python3 scripts/xpra_pointer.py drag "$DISPLAY_ID" 400 160 600 160 --duration 0.5
```

坐标取自未裁剪的 `--source x11` 全图，统一相对于 X11 根窗口；裁剪图坐标需加回裁剪偏移。按当前画面替换示例坐标，再操作并看图确认。鼠标工具用 `ctypes` 调用现有 `libX11`、`libXtst`，需要 display 支持 XTEST，无需 C 头文件或编译；拖拽正常结束或抛出异常时会释放按钮。

3. 选择来源，保存图片：

| 来源 | 命令参数 | 画面与坐标 |
|---|---|---|
| Xpra 合成窗口 | 默认，或 `--source xpra` | 可见窗口的合成图；原点可能不同于 X11 根窗口 |
| 实时 X11 根窗口 | `--source x11` | 包含桌面、装饰和其他可见窗口；原点为根窗口左上角 |

```bash
python3 scripts/xpra_capture.py capture "$DISPLAY_ID" /absolute/path/menu.png
python3 scripts/xpra_capture.py capture "$DISPLAY_ID" /absolute/path/live.png --source x11
```

**先等截图命令完成，再用图片读取工具打开文件。两者顺序执行。**

4. 需要裁剪时，先看完整图确定坐标，再用相同来源保存新文件：

```bash
python3 scripts/xpra_capture.py capture "$DISPLAY_ID" /absolute/path/crop.png \
  --source x11 --crop 0 0 520 370
```

输出 JSON 的 `source`、`display` 和 PNG 的 `capture_source`、`capture_display` 记录实际来源。读取失败会报错，不会自动切换来源。文件已存在时换新文件名，工具不会覆盖。

**遇到阻碍，按表处理：**

| 现象 | 下一步 |
|---|---|
| 画面变化，Xpra 图仍旧 | 显式用 `--source x11` 重截并看图 |
| X11 图没有目标窗口 | 确认窗口已映射、可见；seamless 窗口可能被重定向，必要时改用完整桌面会话 |
| 点击或按键无效 | 查窗口和焦点，重新看图；坐标点击前核对 X11 窗口位置 |
| 空图、全透明、单色或裁剪越界 | 修正窗口状态或裁剪范围；失败图片不会发布 |
| 命令或窗口信息格式不符 | 查本机命令帮助及 `xpra info` 输出 |

## 4. Annotate and Review

需要批注时，先打开待批注的截图，在图上定位，再输出到新的 PNG 路径。原图保留，已有文件不会被覆盖。批注可离线执行。坐标是当前图片的像素位置，左上角为 `(0, 0)`。如果输入是裁剪图，直接使用裁剪后的坐标。

```bash
python3 scripts/xpra_capture.py annotate crop.png marked.png \
  --rect 30 40 270 86 --circle 290 32 350 96 \
  --arrow 230 140 175 92 --number 210 156 1 --text 240 146 'Open menu'
```

框和圈使用外接矩形的左上角和右下角，箭头使用起点和尖端，数字徽标使用中心，文字使用左上角。各标记参数可以重复。中文标签请通过 `--font` 指定覆盖中文的 `.ttf`、`.otf` 或 `.ttc` 字体文件，字体选择和样式参数见 `annotate --help`。

打开**每张最终文件，包括裁剪图和批注图**，核对：

- 程序、输入数据、页面正确。
- 目标菜单或对话框已展开，关键文字完整清晰。
- 画面无遮挡。若有批注，检查箭头尖端和框线位置，并确认标记避开需要阅读的内容。
- 图片与文字步骤一致；入 PDF 或网页时，检查实际渲染尺寸下的可读性。

**通过条件：** 以上全部符合。程序的非空检查不能判断页面是否正确或被遮挡；不合格就重截，再看最终文件。

## 5. Clean Up and Deliver

1. 自建会话：执行 `xpra stop "$DISPLAY_ID"`，关闭应用及会话。复用会话：只关闭本次启动的应用，保留原有窗口。
2. 保留最终图片与必要复现记录，删除临时操作脚本和中间图。
3. 交付图片路径、逐张审核结果和未验证部分。若仍受阻，明确指出失败位置及下一步诊断动作。
