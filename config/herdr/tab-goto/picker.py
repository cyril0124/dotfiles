#!/usr/bin/env python3
"""Tab-only herdr goto: stdlib curses list (j/k), no third-party deps."""

from __future__ import annotations

import curses
import json
import locale
import os
import subprocess
import sys
from typing import Any


# Display badge + color pair id (base / selected-on-highlight)
STATUS_META: dict[str, tuple[str, int, int]] = {
    "working": ("RUN ", 10, 20),
    "idle": ("IDLE", 11, 21),
    "done": ("DONE", 12, 22),
    "blocked": ("ASK ", 13, 23),
    "unknown": ("  ? ", 14, 24),
}


def herdr_bin() -> str:
    path = os.environ.get("HERDR_BIN_PATH") or ""
    if path and os.access(path, os.X_OK):
        return path
    from shutil import which

    found = which("herdr")
    if not found:
        raise RuntimeError("herdr not found (set HERDR_BIN_PATH or PATH)")
    return found


def herdr_json(bin_path: str, *args: str) -> dict[str, Any]:
    raw = subprocess.check_output([bin_path, *args], stderr=subprocess.DEVNULL)
    payload = json.loads(raw)
    if not isinstance(payload, dict):
        raise RuntimeError(f"unexpected herdr output for: herdr {' '.join(args)}")
    result = payload.get("result")
    return result if isinstance(result, dict) else payload


def load_tabs(bin_path: str) -> list[dict[str, str]]:
    tab_result = herdr_json(bin_path, "tab", "list")
    tabs = tab_result.get("tabs") or []
    if not isinstance(tabs, list) or not tabs:
        return []

    workspaces: dict[str, str] = {}
    try:
        ws_result = herdr_json(bin_path, "workspace", "list")
        for ws in ws_result.get("workspaces") or []:
            if not isinstance(ws, dict):
                continue
            wid = ws.get("workspace_id")
            if isinstance(wid, str) and wid:
                label = ws.get("label")
                workspaces[wid] = label if isinstance(label, str) and label else wid
    except Exception:
        pass

    rows: list[dict[str, str]] = []
    for tab in tabs:
        if not isinstance(tab, dict):
            continue
        tid = tab.get("tab_id")
        if not isinstance(tid, str) or not tid:
            continue
        wid = tab.get("workspace_id") if isinstance(tab.get("workspace_id"), str) else "?"
        wlabel = workspaces.get(wid, wid)
        tlabel = tab.get("label") if isinstance(tab.get("label"), str) and tab.get("label") else tid
        status = tab.get("agent_status") if isinstance(tab.get("agent_status"), str) else ""
        focused = bool(tab.get("focused"))
        rows.append(
            {
                "tab_id": tid,
                "workspace": wlabel,
                "tab": tlabel,
                "status": status,
                "focused": "1" if focused else "0",
            }
        )
    return rows


def initial_index(rows: list[dict[str, str]]) -> int:
    for i, row in enumerate(rows):
        if row.get("focused") == "1":
            return i
    return 0


def pause(msg: str) -> None:
    sys.stdout.write(f"{msg}\nPress enter to close.\n")
    sys.stdout.flush()
    try:
        sys.stdin.readline()
    except Exception:
        pass


def _fit(text: str, width: int) -> str:
    if width <= 0:
        return ""
    if len(text) <= width:
        return text.ljust(width)
    if width <= 1:
        return text[:width]
    return text[: width - 1] + "…"


def _status_badge(status: str) -> str:
    key = (status or "").strip().lower()
    if key in STATUS_META:
        return STATUS_META[key][0]
    raw = (status or "?")[:4].upper()
    return raw.ljust(4)


def _col_widths(rows: list[dict[str, str]], inner: int) -> tuple[int, int, int]:
    """tab, workspace, status widths. Layout: mark(2)+pad + tab + gap + ws + gap + st."""
    # fixed: "▸ " (2) + "  " + "  " = 6, status badge 4
    budget = max(12, inner - 6)
    w_st = 4
    rest = max(8, budget - w_st)
    w_tab = max((len(r["tab"]) for r in rows), default=3)
    w_ws = max((len(r["workspace"]) for r in rows), default=4)
    w_tab = max(w_tab, 3)
    w_ws = max(w_ws, 4)
    # Prefer tab name; give workspace remaining
    if w_tab + w_ws > rest:
        w_tab = min(w_tab, max(8, int(rest * 0.55)))
        w_ws = max(4, rest - w_tab)
    while w_tab + w_ws + w_st > budget and w_ws > 4:
        w_ws -= 1
    while w_tab + w_ws + w_st > budget and w_tab > 6:
        w_tab -= 1
    return w_tab, w_ws, w_st


def _put(stdscr: curses.window, y: int, x: int, text: str, attr: int = 0) -> int:
    if y < 0 or x < 0:
        return x
    try:
        height, width = stdscr.getmaxyx()
        if y >= height or x >= width:
            return x
        chunk = text[: max(0, width - x - 1)]
        if not chunk:
            return x
        stdscr.addstr(y, x, chunk, attr)
        return x + len(chunk)
    except curses.error:
        return x


def _init_colors() -> None:
    if not curses.has_colors():
        return
    curses.start_color()
    curses.use_default_colors()
    # 1 selected row soft highlight (content on cyan)
    curses.init_pair(1, curses.COLOR_BLACK, curses.COLOR_CYAN)
    # 2 dim text
    curses.init_pair(2, curses.COLOR_WHITE, -1)
    # status on default bg
    curses.init_pair(10, curses.COLOR_YELLOW, -1)   # working
    curses.init_pair(11, curses.COLOR_GREEN, -1)    # idle
    curses.init_pair(12, curses.COLOR_CYAN, -1)     # done
    curses.init_pair(13, curses.COLOR_RED, -1)      # blocked
    curses.init_pair(14, curses.COLOR_MAGENTA, -1)  # unknown
    curses.init_pair(15, curses.COLOR_WHITE, -1)    # other
    # status on selected cyan bg
    curses.init_pair(20, curses.COLOR_YELLOW, curses.COLOR_CYAN)
    curses.init_pair(21, curses.COLOR_GREEN, curses.COLOR_CYAN)
    curses.init_pair(22, curses.COLOR_BLUE, curses.COLOR_CYAN)
    curses.init_pair(23, curses.COLOR_RED, curses.COLOR_CYAN)
    curses.init_pair(24, curses.COLOR_MAGENTA, curses.COLOR_CYAN)
    curses.init_pair(25, curses.COLOR_BLACK, curses.COLOR_CYAN)
    # current marker
    curses.init_pair(3, curses.COLOR_CYAN, -1)


def _status_pair(status: str, selected: bool) -> int:
    key = (status or "").strip().lower()
    meta = STATUS_META.get(key)
    if not curses.has_colors():
        return curses.A_BOLD if selected else curses.A_NORMAL
    if meta:
        pair = meta[2] if selected else meta[1]
    else:
        pair = 25 if selected else 15
    return curses.color_pair(pair) | curses.A_BOLD


def _is_interesting_status(status: str) -> bool:
    key = (status or "").strip().lower()
    return key not in ("idle", "unknown")


def _visible_indices(rows: list[dict[str, str]], filter_on: bool) -> list[int]:
    if not filter_on:
        return list(range(len(rows)))
    return [i for i, row in enumerate(rows) if _is_interesting_status(row.get("status", ""))]


def pick_index(rows: list[dict[str, str]], start: int) -> int | None:
    def _ui(stdscr: curses.window) -> int | None:
        curses.curs_set(0)
        _init_colors()

        try:
            "▸".encode(sys.stdout.encoding or "utf-8")
            sel_mark, idle_mark, cur_mark = "▸", " ", "●"
            sep_char = "─"
        except Exception:
            sel_mark, idle_mark, cur_mark = ">", " ", "*"
            sep_char = "-"

        filter_on = False
        global_idx = max(0, min(start, len(rows) - 1))

        def ensure_selection() -> list[int]:
            nonlocal global_idx
            vis = _visible_indices(rows, filter_on)
            if not vis:
                return vis
            if global_idx not in vis:
                following = [i for i in vis if i >= global_idx]
                global_idx = following[0] if following else vis[-1]
            return vis

        while True:
            vis = ensure_selection()
            stdscr.erase()
            height, width = stdscr.getmaxyx()
            inner = max(0, width - 1)

            # Compact help — left; filter flag — right
            help_l = "j/k  enter  f  esc"
            _put(stdscr, 0, 1, help_l, curses.A_DIM)
            if filter_on:
                flag = "FILTER"
                _put(stdscr, 0, max(1, inner - len(flag) - 1), flag, curses.A_BOLD)

            w_tab, w_ws, w_st = _col_widths(rows, inner - 2)
            # row width estimate for separator
            row_w = 2 + 1 + 1 + w_tab + 2 + w_ws + 2 + w_st
            sep = sep_char * min(inner, max(row_w + 2, 24))
            _put(stdscr, 1, 0, sep, curses.A_DIM)

            list_top = 2
            footer_row = height - 1
            sep_bottom = height - 2
            view_h = max(1, sep_bottom - list_top)

            if not vis:
                _put(
                    stdscr,
                    list_top,
                    1,
                    "no matches  ·  press f to clear filter",
                    curses.A_DIM,
                )
            else:
                vpos = vis.index(global_idx)
                top = 0
                if vpos >= top + view_h:
                    top = vpos - view_h + 1
                if vpos < top:
                    top = vpos

                for row_i in range(view_h):
                    v_i = top + row_i
                    if v_i >= len(vis):
                        break
                    item_i = vis[v_i]
                    row = rows[item_i]
                    selected = item_i == global_idx
                    is_current = row.get("focused") == "1"
                    y = list_top + row_i

                    if selected and curses.has_colors():
                        base = curses.color_pair(1) | curses.A_BOLD
                        dim = curses.color_pair(1)
                    elif selected:
                        base = curses.A_REVERSE | curses.A_BOLD
                        dim = curses.A_REVERSE
                    else:
                        base = curses.A_BOLD
                        dim = curses.A_DIM

                    # Fill selected row background across usable width
                    if selected:
                        try:
                            stdscr.move(y, 0)
                            stdscr.clrtoeol()
                            pad = " " * min(inner, max(row_w + 2, 8))
                            _put(stdscr, y, 0, pad[:inner], base)
                        except curses.error:
                            pass

                    mark = sel_mark if selected else (cur_mark if is_current else idle_mark)
                    mark_attr = base
                    if is_current and not selected and curses.has_colors():
                        mark_attr = curses.color_pair(3) | curses.A_BOLD

                    x = 1
                    x = _put(stdscr, y, x, f"{mark} ", mark_attr)
                    # tab name primary
                    x = _put(stdscr, y, x, _fit(row["tab"], w_tab), base)
                    x = _put(stdscr, y, x, "  ", dim)
                    # workspace secondary
                    x = _put(stdscr, y, x, _fit(row["workspace"], w_ws), dim)
                    x = _put(stdscr, y, x, "  ", dim)
                    # status badge
                    badge = _status_badge(row["status"])
                    _put(stdscr, y, x, _fit(badge, w_st), _status_pair(row["status"], selected))

            _put(stdscr, sep_bottom, 0, sep, curses.A_DIM)

            if vis:
                vpos = vis.index(global_idx)
                footer = f" {vpos + 1}/{len(vis)}"
                if filter_on:
                    footer += f"  ·  {len(vis)}/{len(rows)}"
                if rows[global_idx].get("focused") == "1":
                    footer += "  ·  here"
            else:
                footer = f" 0/0  ·  {len(rows)} total"
            _put(stdscr, footer_row, 0, footer, curses.A_DIM)

            stdscr.refresh()

            ch = stdscr.getch()
            if ch in (ord("j"), curses.KEY_DOWN):
                if vis:
                    vpos = vis.index(global_idx)
                    global_idx = vis[(vpos + 1) % len(vis)]
            elif ch in (ord("k"), curses.KEY_UP):
                if vis:
                    vpos = vis.index(global_idx)
                    global_idx = vis[(vpos - 1) % len(vis)]
            elif ch in (ord("f"), ord("F")):
                filter_on = not filter_on
            elif ch in (curses.KEY_ENTER, 10, 13):
                if vis:
                    return global_idx
            elif ch in (27, ord("q")):
                return None

    return curses.wrapper(_ui)


def focus_tab(bin_path: str, tab_id: str) -> None:
    subprocess.check_call(
        [bin_path, "tab", "focus", tab_id],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def main() -> int:
    try:
        locale.setlocale(locale.LC_ALL, "")
    except locale.Error:
        pass

    if not sys.stdin.isatty() or not sys.stdout.isatty():
        pause("tab-goto needs a TTY (run from herdr popup).")
        return 1

    try:
        bin_path = herdr_bin()
    except RuntimeError as exc:
        pause(str(exc))
        return 1

    try:
        rows = load_tabs(bin_path)
    except Exception as exc:
        pause(f"Failed to list tabs: {exc}")
        return 1

    if not rows:
        pause("No tabs in this session.")
        return 0

    start = initial_index(rows)
    try:
        chosen = pick_index(rows, start)
    except curses.error as exc:
        pause(f"curses UI failed: {exc}")
        return 1

    if chosen is None:
        return 0

    tab_id = rows[chosen]["tab_id"]
    try:
        focus_tab(bin_path, tab_id)
    except Exception as exc:
        pause(f"herdr tab focus failed for {tab_id}: {exc}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
