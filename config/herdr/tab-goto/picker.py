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
# badge text is fixed width 7 for column alignment
STATUS_META: dict[str, tuple[str, int, int]] = {
    "working": ("working", 10, 20),
    "idle": ("idle   ", 11, 21),
    "done": ("done   ", 12, 22),
    "blocked": ("blocked", 13, 23),
    "unknown": ("?      ", 14, 24),
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
                "workspace_id": wid,
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
    return text[: width - 1] + "."


def _status_badge(status: str) -> str:
    key = (status or "").strip().lower()
    if key in STATUS_META:
        return STATUS_META[key][0]
    raw = (status or "?")[:7]
    return raw.ljust(7)


def _tree_tab_width(rows: list[dict[str, str]], inner: int) -> tuple[int, int]:
    """Return (tab_name_width, status_width) for tree leaves.

    Layout: pad(1)+branch(3)+cur(2)+name+gap(2)+status(7) ≈ 15 fixed.
    """
    w_st = 7
    w_tab = max(12, inner - 15)
    return w_tab, w_st


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
    # tree chrome (branches / fold icons) — always quieter than labels
    curses.init_pair(5, curses.COLOR_WHITE, -1)
    curses.init_pair(6, curses.COLOR_BLACK, curses.COLOR_CYAN)  # tree on selected row


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


def _filtered_tab_indices(rows: list[dict[str, str]], filter_on: bool) -> list[int]:
    if not filter_on:
        return list(range(len(rows)))
    return [i for i, row in enumerate(rows) if _is_interesting_status(row.get("status", ""))]


def _workspace_order(rows: list[dict[str, str]], tab_indices: list[int]) -> list[str]:
    order: list[str] = []
    seen: set[str] = set()
    for i in tab_indices:
        wid = rows[i].get("workspace_id") or "?"
        if wid not in seen:
            seen.add(wid)
            order.append(wid)
    return order


def _build_entries(
    rows: list[dict[str, str]],
    tab_indices: list[int],
    current_wid: str,
    expanded: set[str],
) -> list[dict[str, Any]]:
    """Tree entries: workspace node, then tab children when expanded."""
    by_ws: dict[str, list[int]] = {}
    labels: dict[str, str] = {}
    for i in tab_indices:
        wid = rows[i].get("workspace_id") or "?"
        by_ws.setdefault(wid, []).append(i)
        labels[wid] = rows[i].get("workspace") or wid

    entries: list[dict[str, Any]] = []
    for wid in _workspace_order(rows, tab_indices):
        indices = by_ws.get(wid) or []
        if not indices:
            continue
        is_current = wid == current_wid
        # Expanded set is authoritative (current ws starts expanded in pick_index).
        is_open = wid in expanded
        entries.append(
            {
                "kind": "ws",
                "workspace_id": wid,
                "workspace": labels.get(wid, wid),
                "count": len(indices),
                "expanded": is_open,
                "is_current_ws": is_current,
            }
        )
        if is_open:
            for n, i in enumerate(indices):
                entries.append(
                    {
                        "kind": "tab",
                        "idx": i,
                        "workspace_id": wid,
                        "is_last": n == len(indices) - 1,
                    }
                )
    return entries


def pick_index(rows: list[dict[str, str]], start: int) -> int | None:
    def _ui(stdscr: curses.window) -> int | None:
        curses.curs_set(0)
        _init_colors()
        try:
            curses.mousemask(curses.ALL_MOUSE_EVENTS | curses.REPORT_MOUSE_POSITION)
            curses.mouseinterval(0)
        except curses.error:
            pass

        # Unicode tree (width-1 box marks). Locale is set in main().
        branch, branch_last = "├─ ", "└─ "
        open_icon, shut_icon = "▾ ", "▸ "
        cur_mark = "●"
        sep_char = "─"

        filter_on = False
        start_idx = max(0, min(start, len(rows) - 1))
        current_wid = rows[start_idx].get("workspace_id") or "?"
        # Default: expand every workspace; h/l still folds any node.
        expanded = {
            (r.get("workspace_id") or "?")
            for r in rows
        }
        cursor = 0  # index into entries

        def rebuild() -> list[dict[str, Any]]:
            nonlocal cursor
            tabs = _filtered_tab_indices(rows, filter_on)
            entries = _build_entries(rows, tabs, current_wid, expanded)
            if not entries:
                cursor = 0
                return entries
            cursor = max(0, min(cursor, len(entries) - 1))
            return entries

        def snap_to_ws(wid: str) -> None:
            nonlocal cursor
            entries2 = _build_entries(
                rows,
                _filtered_tab_indices(rows, filter_on),
                current_wid,
                expanded,
            )
            for i, e in enumerate(entries2):
                if e.get("kind") == "ws" and e.get("workspace_id") == wid:
                    cursor = i
                    return
            cursor = max(0, min(cursor, max(0, len(entries2) - 1)))

        # Place cursor on starting tab after first build.
        entries = rebuild()
        for i, ent in enumerate(entries):
            if ent.get("kind") == "tab" and ent.get("idx") == start_idx:
                cursor = i
                break

        while True:
            entries = rebuild()
            stdscr.erase()
            height, width = stdscr.getmaxyx()
            if height < 4 or width < 16:
                _put(stdscr, 0, 0, "window too small", curses.A_BOLD)
                stdscr.refresh()
                ch = stdscr.getch()
                if ch in (27, ord("q")):
                    return None
                continue

            inner = max(0, width - 1)
            help_l = "j/k · click · h/l fold · enter · f · esc"
            _put(stdscr, 0, 1, _fit(help_l, max(0, inner - 1)), curses.A_DIM)
            if filter_on:
                flag = "FILTER"
                _put(stdscr, 0, max(0, inner - len(flag) - 1), flag, curses.A_BOLD)

            w_tab, w_st = _tree_tab_width(rows, inner)
            sep = " " + (sep_char * max(0, inner - 2))
            _put(stdscr, 1, 0, _fit(sep, inner), curses.A_DIM)

            list_top = 2
            footer_row = height - 1
            sep_bottom = height - 2
            view_h = max(1, sep_bottom - list_top)

            if not entries:
                _put(stdscr, list_top, 1, _fit("no matches — press f", max(0, inner - 1)), curses.A_DIM)
            else:
                top = 0
                if cursor >= top + view_h:
                    top = cursor - view_h + 1
                if cursor < top:
                    top = cursor

                for row_i in range(view_h):
                    e_i = top + row_i
                    if e_i >= len(entries):
                        break
                    ent = entries[e_i]
                    selected = e_i == cursor
                    y = list_top + row_i

                    if selected:
                        base = (
                            curses.color_pair(1) | curses.A_BOLD
                            if curses.has_colors()
                            else curses.A_REVERSE | curses.A_BOLD
                        )
                        # Branches/icons stay dimmer than the label even when selected.
                        tree = (
                            curses.color_pair(6) | curses.A_DIM
                            if curses.has_colors()
                            else curses.A_REVERSE | curses.A_DIM
                        )
                        _put(stdscr, y, 0, " " * inner, base)
                    else:
                        base = curses.A_BOLD
                        tree = (
                            curses.color_pair(5) | curses.A_DIM
                            if curses.has_colors()
                            else curses.A_DIM
                        )

                    if ent["kind"] == "ws":
                        icon = open_icon if ent["expanded"] else shut_icon
                        label = ent["workspace"]
                        if not ent["expanded"]:
                            label += f"  ({ent['count']})"
                        # Fold/tree icon dim; workspace name stronger.
                        _put(stdscr, y, 1, icon, tree)
                        _put(
                            stdscr,
                            y,
                            1 + len(icon),
                            _fit(label, max(0, inner - 1 - len(icon))),
                            base,
                        )
                        continue

                    item_i = int(ent["idx"])
                    row = rows[item_i]
                    is_current = row.get("focused") == "1"
                    twig = branch_last if ent.get("is_last") else branch
                    name = row["tab"]
                    badge = _status_badge(row["status"])
                    # cols: 1 branch(3) | 4 cur(2) | 6 name | gap | status
                    name_w = max(8, min(w_tab, inner - 6 - 2 - w_st))
                    badge_at = 6 + name_w + 2
                    _put(stdscr, y, 1, twig, tree)
                    cur_cell = f"{cur_mark} " if is_current else "  "
                    if is_current and curses.has_colors():
                        cur_attr = (
                            (curses.color_pair(1) | curses.A_BOLD)
                            if selected
                            else (curses.color_pair(3) | curses.A_BOLD)
                        )
                    elif is_current:
                        cur_attr = base
                    else:
                        cur_attr = tree
                    _put(stdscr, y, 4, cur_cell, cur_attr)
                    _put(stdscr, y, 6, _fit(name, name_w), base)
                    if badge_at < inner:
                        _put(
                            stdscr,
                            y,
                            badge_at,
                            _fit(badge, min(w_st, max(0, inner - badge_at))),
                            _status_pair(row["status"], selected),
                        )

            _put(stdscr, sep_bottom, 0, sep, curses.A_DIM)

            if entries:
                footer = f"{cursor + 1}/{len(entries)}"
                if filter_on:
                    footer += " filter"
                ent = entries[cursor]
                if ent["kind"] == "ws":
                    footer += " h fold" if ent["expanded"] else " l open"
            else:
                footer = "0/0"
            _put(stdscr, footer_row, 0, _fit(footer, inner), curses.A_DIM)

            stdscr.refresh()

            ch = stdscr.getch()
            if ch in (ord("j"), curses.KEY_DOWN):
                if entries:
                    cursor = (cursor + 1) % len(entries)
            elif ch in (ord("k"), curses.KEY_UP):
                if entries:
                    cursor = (cursor - 1) % len(entries)
            elif ch in (ord("l"), curses.KEY_RIGHT):
                if entries:
                    ent = entries[cursor]
                    wid = str(ent.get("workspace_id") or "")
                    if wid:
                        expanded.add(wid)
            elif ch in (ord("h"), curses.KEY_LEFT):
                if entries:
                    ent = entries[cursor]
                    wid = str(ent.get("workspace_id") or "")
                    if wid:
                        expanded.discard(wid)
                        snap_to_ws(wid)
            elif ch in (ord("f"), ord("F")):
                filter_on = not filter_on
            elif ch in (curses.KEY_ENTER, 10, 13):
                if not entries:
                    continue
                ent = entries[cursor]
                if ent["kind"] == "tab":
                    return int(ent["idx"])
                wid = str(ent.get("workspace_id") or "")
                if not wid:
                    continue
                if ent.get("expanded"):
                    expanded.discard(wid)
                else:
                    expanded.add(wid)
            elif ch == curses.KEY_MOUSE:
                try:
                    _id, mx, my, _z, bstate = curses.getmouse()
                except curses.error:
                    continue
                clicked = bstate & (
                    getattr(curses, "BUTTON1_CLICKED", 0)
                    | getattr(curses, "BUTTON1_PRESSED", 0)
                    | getattr(curses, "BUTTON1_RELEASED", 0)
                )
                if not clicked and bstate == 0:
                    clicked = True
                if not clicked or not entries:
                    continue
                # Map screen row → visible entry (same scroll math as draw).
                list_top = 2
                sep_bottom = height - 2
                view_h = max(1, sep_bottom - list_top)
                top = 0
                if cursor >= top + view_h:
                    top = cursor - view_h + 1
                if cursor < top:
                    top = cursor
                if my < list_top or my >= list_top + view_h:
                    continue
                e_i = top + (my - list_top)
                if e_i < 0 or e_i >= len(entries):
                    continue
                ent = entries[e_i]
                cursor = e_i
                if ent["kind"] == "tab":
                    return int(ent["idx"])
                wid = str(ent.get("workspace_id") or "")
                if not wid:
                    continue
                if ent.get("expanded"):
                    expanded.discard(wid)
                else:
                    expanded.add(wid)
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
