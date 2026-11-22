---
name: gui-screenshot
description: Launch Linux desktop apps on Xvfb or Xpra, drive them with XTEST, capture and annotate screenshots, and verify the result. Use for GUI walkthroughs, documentation images, and troubleshooting unresponsive clicks, blank captures, or hidden dialogs.
---

# GUI Screenshots

先选通路，再决定依赖：

- **单机 Xvfb 直连**（默认）：只需在本机抓图，不需要浏览器或远程查看。用 Xvfb + XTEST，输入按 X11 原生语义投递。
- **Xpra 会话**：需要远程/浏览器查看同一桌面，或要复用已有会话的窗口状态。此路需要 `xpra`，先运行 `command -v xpra`；找不到时告知用户流程需要它，仅在用户明确同意后协助安装。

按以下 5 步截取目标程序，逐张看图验收。

脚本路径相对于本 Skill 目录；在其他目录执行时，换成绝对路径。

## 1. Launch the App

1. 选未占用的 `DISPLAY_ID`；复用已有会话时，记录原有窗口。
2. 按所选通路检查依赖：`Xvfb`、Python 3.10+、Pillow 为公共项，Xpra 会话另需 `xpra`；按键需要 `xmodmap`，实时 X11 截图需要 Pillow 的 XCB 支持。缺项时先报告。
3. 将 `APP_COMMAND` 设为应用及参数，选定 Xvfb 可执行文件：

```bash
# Prefer the Xpra-bundled Xvfb: the system one can fail with
# "could not open default font 'fixed'" and refuses to start.
for candidate in "$HOME/.local/share/xpra-web/xvfb/Xvfb" /usr/bin/Xvfb; do
  [ -x "$candidate" ] && XVFB=$candidate && break
done
XVFB=${XVFB:-$(command -v Xvfb)}
```

### 单机 Xvfb 直连（默认）

不需要远程查看时优先用这条，它省掉 Xpra 的合成与输入转发。选未占用的 `DISPLAY_ID`，用进程管理工具启动前台命令：

```bash
"$XVFB" "$DISPLAY_ID" -screen 0 1800x1060x24 -nolisten tcp
```

系统或其他 Xvfb 都可能报 `could not open default font 'fixed'`。第 1 步的候选顺序已优先 Xpra 自带的 Xvfb，仍失败时再核对 `-fp` 字体路径。确认 Xvfb 就绪后再把应用拉起：

```bash
env DISPLAY="$DISPLAY_ID" /absolute/path/to/application
```

无窗口管理器时，应用按自身请求的尺寸贴在根窗口左上角，而尺寸可能来自应用自己的配置文件（命令行 `-geometry` 常被忽略）。按实际截图确认尺寸；要改大小用 `xwininfo` 取窗口 ID 后调 `XMoveResizeWindow`，再重新截图看布局是否跟随。

### Xpra 会话

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

Xpra 会话用查询和映射：

```bash
python3 scripts/xpra_capture.py windows "$DISPLAY_ID"
python3 scripts/xpra_capture.py map "$DISPLAY_ID" <window-id>
```

按 `title` 和 `geometry` 确认目标，再映射当前 ID。`shown=false` 的窗口可能已启动但未显示；菜单的 `shown=null` 不能证明它不可见，先截图确认。

单机 Xvfb 下没有映射概念，用 `xwininfo -root -children` 取真实窗口 ID 和绝对坐标；子窗口（含对话框、菜单弹层）要单独列出，必要时对子窗口再截一次。

**完成条件：** 截图中能看到正确应用。菜单或对话框出现后，重新查询 ID，只映射画面中缺失的窗口。

## 3. Interact and Capture

1. 截当前画面，打开图片确定下一步。
2. 按键和文本输入：单机 Xvfb 用 XTEST 工具，Xpra 会话用 `xpra_capture.py key`。

```bash
python3 scripts/xlib_input.py keysym "$DISPLAY_ID" Down Escape Alt_L+f
python3 scripts/xlib_input.py type "$DISPLAY_ID" /abs/path/file.txt

python3 scripts/xpra_capture.py key "$DISPLAY_ID" --window <window-id> Alt_L+f
python3 scripts/xpra_capture.py key "$DISPLAY_ID" Down Right Down
```

`keysym` 接收命名键和 `修饰键+键` 组合；`type` 逐字符发送，含大写时自动加 Shift。Xpra 的 `--window` 设置初始焦点；操作已打开的菜单时省略它。每展开一级，截图确认位置。

点菜单、页签、表格行，或拖列宽时，用鼠标工具（两条通路通用）：

```bash
python3 scripts/xpra_pointer.py click "$DISPLAY_ID" 200 160
python3 scripts/xpra_pointer.py move "$DISPLAY_ID" 200 240
python3 scripts/xpra_pointer.py drag "$DISPLAY_ID" 400 160 600 160 --duration 0.5
```

单机 Xvfb 下另有带按住时长和滚轮的形式：

```bash
python3 scripts/xlib_input.py click "$DISPLAY_ID" 200 160 --hold 0.2
python3 scripts/xlib_input.py wheel "$DISPLAY_ID" 400 400 --button 5 --count 20
```

`wheel` 用于滚动长列表（按钮 4 上、5 下）。

菜单栏和弹出菜单常在**按下**时展开、松开时关闭，普通 click 会一闪即过：用 `press` → 截图 → `release` 观察条目位置，再对条目发 click。

坐标取自未裁剪的 `--source x11` 全图，统一相对于 X11 根窗口；裁剪图坐标需加回裁剪偏移。按当前画面替换示例坐标，再操作并看图确认。两个输入工具都用 `ctypes` 调用现有 `libX11`、`libXtst`，需要 display 支持 XTEST，无需 C 头文件或编译；拖拽正常结束或抛出异常时会释放按钮。

3. 选择来源，保存图片：

| 来源 | 命令参数 | 画面与坐标 |
|---|---|---|
| Xpra 合成窗口 | 默认，或 `--source xpra` | 可见窗口的合成图；原点可能不同于 X11 根窗口 |
| 实时 X11 根窗口 | `--source x11` | 包含桌面、装饰和其他可见窗口；原点为根窗口左上角 |

单机 Xvfb 只有一种来源：`--source x11`。

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
| 能选中列表行或文本框，但页签、菜单、展开框全无响应 | Xpra 输入通路退化，不是坐标问题。核对坐标正确后直接换单机 Xvfb 直连 |
| 坐标核对无误却点不动 | 先查指针实际落点（`XQueryPointer`）与窗口绝对坐标；两者一致即换通路 |
| 菜单按下即关 | 用 `press` → 截图 → `release`，不要用 click |
| 系统 Xvfb 报 `could not open default font 'fixed'` | 换 Xpra 自带的 Xvfb 可执行文件 |
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

1. 自建会话：Xpra 会话执行 `xpra stop "$DISPLAY_ID"`；单机 Xvfb 停掉 Xvfb 进程，同时关闭应用。复用会话：只关闭本次启动的应用，保留原有窗口。
2. 保留最终图片与必要复现记录，删除临时操作脚本和中间图。
3. 交付图片路径、逐张审核结果和未验证部分。若仍受阻，明确指出失败位置及下一步诊断动作。
