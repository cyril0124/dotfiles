---
name: gui-screenshot
description: Launch Linux desktop apps on Xvfb or Xpra, drive them with XTEST, capture and annotate screenshots, and verify the result. Use for GUI walkthroughs, documentation images, and troubleshooting unresponsive clicks, blank captures, or hidden dialogs.
---

# GUI Screenshots

脚本路径相对于技能目录。换目录执行时用绝对路径。

## 1. Launch the App

- **本机抓图**默认用 Xvfb 直连，经 XTEST 投递输入。
- **远程或浏览器查看、复用窗口状态**用 Xpra。先运行 `command -v xpra`。缺少 `xpra` 时报告，得到用户明确同意后再协助安装。
- 检查 Xvfb、Python 3.10+、Pillow。按键需要 `xmodmap`，实时 X11 抓图需要 Pillow 的 XCB 支持。报告缺项。鼠标工具依赖 `libX11`、`libXtst` 和显示会话的 XTEST 扩展，可直接运行。

新建会话选空闲的 `DISPLAY_ID`，设置应用及参数 `APP_COMMAND`，用进程管理工具运行前台命令。优先选 Xpra 附带的 Xvfb，避免系统版本找不到 `fixed` 字体。仍报 `could not open default font 'fixed'` 时检查 `-fp`。

```bash
for candidate in "$HOME/.local/share/xpra-web/xvfb/Xvfb" /usr/bin/Xvfb; do
  [ -x "$candidate" ] && XVFB=$candidate && break
done
XVFB=${XVFB:-$(command -v Xvfb)}
```

**Xvfb 直连**

```bash
"$XVFB" "$DISPLAY_ID" -screen 0 1800x1060x24 -nolisten tcp
```

显示会话就绪后，用 `env DISPLAY="$DISPLAY_ID" /absolute/path/to/application` 启动应用。无窗口管理器时，窗口通常位于根窗口左上角，尺寸可能取自应用配置。用 `geometry` 获取可见顶层窗口的 `id` 和根窗口坐标。调整后重截，核对实际布局。

```bash
python3 scripts/xwin.py geometry "$DISPLAY_ID"
python3 scripts/xwin.py resize "$DISPLAY_ID" <window-id> 1800 1060 --x 0 --y 0
python3 scripts/xwin.py move "$DISPLAY_ID" <window-id> 0 0
```

**Xpra 会话**

指定独立工作目录，记录 display、进程 ID 和日志。等待 `xpra is ready`。

```bash
xpra start "$DISPLAY_ID" --daemon=no --use-display=no \
  --xvfb="$XVFB -screen 0 1440x1000x24 -nolisten tcp +extension Composite" \
  --resize-display=1440x1000 --pulseaudio=no --audio=no \
  --notifications=no --webcam=no --mdns=no --html=off --dbus=no \
  --start-child="$APP_COMMAND" --terminate-children=yes --exit-with-children=yes
```

- 需要放大或最大化窗口时，确认 `fluxbox` 可用，改用 `xpra start-desktop`，加 `--start-child=fluxbox`，保留应用子进程。同步调整 `-screen 0` 和 `--resize-display` 的尺寸。
- 完整桌面下查询可能只返回桌面 ID。根据实时全图点击应用标题栏，再用 `python3 scripts/xpra_capture.py key "$DISPLAY_ID" Alt_L+F10` 最大化。该键对应 Fluxbox 默认 `Mod1 F10 :Maximize`，自定义配置以本机为准。应用 `-geometry` 是否生效以窗口尺寸和截图为准。
- 复用会话时先记录原有窗口，再用 `env DISPLAY="$DISPLAY_ID" /absolute/path/to/application` 单独启动应用。

**完成条件**　显示会话就绪，应用已启动。

## 2. Show the Target Window

- Xpra 用 `python3 scripts/xpra_capture.py windows "$DISPLAY_ID"` 查询。按 `title` 和 `geometry` 确认目标，再用 `python3 scripts/xpra_capture.py map "$DISPLAY_ID" <window-id>` 映射缺失的窗口。`shown=false` 可能表示已启动但未显示，`shown=null` 的菜单先看图确认。
- Xvfb 用 `DISPLAY="$DISPLAY_ID" xwininfo -root -children` 查窗口 ID 和绝对坐标。对话框、菜单等子窗口单独查询，必要时补拍。

**完成条件**　截图可见目标应用。打开菜单或对话框后重新查询 ID，只映射画面中缺失的 Xpra 窗口。

## 3. Interact and Capture

1. 用 `--source x11` 截未裁剪全图作为输入坐标基准，等命令完成再打开 PNG。裁剪图坐标加回裁剪偏移。Xpra 默认 `--source xpra` 输出可见窗口合成图，原点可能不同。Xvfb 只用 `--source x11`。
2. 按当前画面操作，每次展开一级菜单都重截确认。Xpra 的 `--window` 只用于设置初始焦点，菜单打开后省略。`keysym` 接受命名键和组合键，`type` 逐字符发送 ASCII，大写自动加 Shift。
3. 用新文件名保存结果。裁剪时先看全图，再用相同来源指定 `--crop X Y WIDTH HEIGHT`。JSON 的 `source`、`display` 与 PNG 的 `capture_source`、`capture_display` 记录实际来源。失败时工具报错，不切换来源或覆盖文件。

```bash
python3 scripts/xpra_capture.py capture "$DISPLAY_ID" /abs/live.png --source x11
python3 scripts/xpra_capture.py capture "$DISPLAY_ID" /abs/crop.png --source x11 --crop 0 0 520 370

python3 scripts/xlib_input.py keysym "$DISPLAY_ID" Down Escape Alt_L+f
python3 scripts/xlib_input.py type "$DISPLAY_ID" /abs/path/file.txt
python3 scripts/xpra_capture.py key "$DISPLAY_ID" --window <window-id> Alt_L+f

python3 scripts/xpra_pointer.py click "$DISPLAY_ID" 200 160
python3 scripts/xpra_pointer.py move "$DISPLAY_ID" 200 240
python3 scripts/xpra_pointer.py drag "$DISPLAY_ID" 400 160 600 160 --duration 0.5
python3 scripts/xlib_input.py click "$DISPLAY_ID" 200 160 --hold 0.2
python3 scripts/xlib_input.py wheel "$DISPLAY_ID" 400 400 --button 5 --count 20
```

`xpra_pointer.py` 的鼠标命令适用于两条通路，拖拽结束或异常时释放按钮。Xvfb 可用 `xlib_input.py` 调整按住时长或滚动长列表，按钮 4 向上、5 向下。

| 现象 | 处理 |
|---|---|
| Xpra 合成图滞后 | 用 `--source x11` 重截并打开图片 |
| X11 图缺目标 | 核对映射和可见性。Xpra seamless 窗口可能被重定向，必要时改用完整桌面 |
| 坐标正确，页签或菜单仍点不动 | 用 `XQueryPointer` 对照落点和窗口绝对坐标。若一致，从 Xpra 切到 Xvfb 直连。列表行或文本框能选中时，仍可能是 Xpra 输入退化 |
| 菜单一闪即逝 | 用 `xlib_input.py press "$DISPLAY_ID" X Y` 按住，截图看条目位置，再用 `xlib_input.py release "$DISPLAY_ID"` 松开，最后点击目标条目 |
| 空图、全透明、单色或裁剪越界 | 修正窗口状态或裁剪范围，失败图片不交付 |
| 参数或窗口信息格式不符 | 查本机命令帮助和 `xpra info` |

## 4. Annotate and Review

批注可离线执行。先打开原图，按当前图片左上角为 `(0, 0)` 定位，裁剪图直接用裁剪后的坐标。输出到新 PNG，保留原图。标记参数可重复。

```bash
python3 scripts/xpra_capture.py annotate crop.png marked.png \
  --rect 30 40 270 86 --circle 290 32 350 96 \
  --arrow 230 140 175 92 --number 210 156 1 --text 240 146 'Open menu'
```

框和圈用外接矩形两角，箭头用起点和尖端，数字用中心，文字用左上角。中文标签通过 `--font` 指定覆盖中文的 `.ttf`、`.otf` 或 `.ttc` 字体，样式参数见 `annotate --help`。

**完成条件**　逐张打开最终文件，包括裁剪图和批注图。以下全部通过才交付，否则重截复查。

- 程序、输入数据、页面正确，目标菜单或对话框已展开。
- 关键文字完整清晰，窗口无遮挡。批注位置准确且避开关键内容。
- 图片与文字步骤一致。用于 PDF 或网页时，按实际渲染尺寸检查可读性。

## 5. Clean Up and Deliver

1. 自建 Xpra 用 `xpra stop "$DISPLAY_ID"`，会话会关闭应用和窗口管理器子进程。自建 Xvfb 停止应用和 Xvfb。复用会话只关闭本次启动的应用。
2. 保留最终图片和必要复现记录，删除临时操作脚本和中间图。
3. 交付图片路径、逐张验收结果和未验证部分。若受阻，给出失败位置和下一步诊断动作。
