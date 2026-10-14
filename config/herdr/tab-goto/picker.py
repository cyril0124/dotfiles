#!/usr/bin/env python3
"""Tab-only herdr goto: stdlib curses list (j/k), no third-party deps."""

from __future__ import annotations

import curses
import json
import locale
import os
import re
import subprocess
import sys
import time
from typing import Any

_TAB_NUM_PREFIX = re.compile(r"^\d+\s+")
SPINNER_FRAMES = "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
SPINNER_INTERVAL_MS = 120
TAB_SHORTCUTS = "1234567890abcde"


# Display badge + color pair id (base / selected-on-highlight)
# badge text is fixed width 7 for column alignment
STATUS_META: dict[str, tuple[str, int, int]] = {
    "working": ("WORKING", 10, 20),
    "idle": ("IDLE   ", 11, 21),
    "done": ("DONE   ", 12, 22),
    "blocked": ("BLOCKED", 13, 23),
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


def _state_dir() -> str:
    env = os.environ.get("HERDR_PLUGIN_STATE_DIR") or ""
    if env:
        return env
    return os.path.join(os.path.dirname(os.path.abspath(__file__)), ".state")


def _last_tab_path() -> str:
    return os.path.join(_state_dir(), "last-tab")


def read_last_tab() -> str | None:
    path = _last_tab_path()
    try:
        text = open(path, encoding="utf-8").read().strip()
    except OSError:
        return None
    return text or None


def write_last_tab(tab_id: str) -> None:
    path = _last_tab_path()
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        fh.write(tab_id + "\n")
    os.replace(tmp, path)


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
    raw = (status or "--")[:7]
    return raw.ljust(7)


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
    """Initialize Nord colors, falling back to indexed or basic terminal colors."""
    if not curses.has_colors():
        return
    curses.start_color()
    curses.use_default_colors()
    # RGB, nearest xterm-256 color, and basic terminal fallback.
    palette = {
        "text": (0xD8DEE9, 253, curses.COLOR_WHITE),
        "bright": (0xECEFF4, 255, curses.COLOR_WHITE),
        "muted": (0x7B88A1, 103, curses.COLOR_WHITE),
        "divider": (0x4C566A, 240, curses.COLOR_WHITE),
        "red": (0xBF616A, 131, curses.COLOR_RED),
        "green": (0xA3BE8C, 150, curses.COLOR_GREEN),
        "yellow": (0xEBCB8B, 222, curses.COLOR_YELLOW),
        "magenta": (0xB48EAD, 139, curses.COLOR_MAGENTA),
        "cyan": (0x88C0D0, 109, curses.COLOR_CYAN),
    }
    colors: dict[str, int] = {}
    for slot, (name, (rgb, indexed, basic)) in enumerate(palette.items(), start=240):
        color = indexed if curses.COLORS >= 256 else basic
        if curses.COLORS >= 256 and curses.can_change_color():
            try:
                channels = [round(((rgb >> shift) & 255) * 1000 / 255) for shift in (16, 8, 0)]
                curses.init_color(slot, *channels)
                color = slot
            except curses.error:
                pass
        colors[name] = color

    # Keep the original ANSI selection and current/last marker colors.
    colors["selection"] = curses.COLOR_CYAN
    colors["black"] = curses.COLOR_BLACK
    colors["marker_current"] = curses.COLOR_CYAN
    colors["marker_last"] = curses.COLOR_YELLOW
    pairs = {
        1: ("black", "selection"), 2: ("muted", None),
        3: ("cyan", None), 4: ("text", None), 5: ("divider", None),
        6: ("black", "selection"), 7: ("marker_last", None),
        8: ("bright", None), 9: ("black", "selection"),
        16: ("marker_current", None),
    }
    for offset, name in enumerate(("yellow", "green", "cyan", "red", "magenta", "muted")):
        pairs[10 + offset] = (name, None)
    for pair, (foreground, background) in pairs.items():
        curses.init_pair(pair, colors[foreground], colors[background] if background else -1)
    for offset, color in enumerate((curses.COLOR_YELLOW, curses.COLOR_GREEN, curses.COLOR_BLUE,
                                    curses.COLOR_RED, curses.COLOR_MAGENTA, curses.COLOR_BLACK)):
        curses.init_pair(20 + offset, color, curses.COLOR_CYAN)


def _color_attr(pair: int, selected: bool = False, bold: bool = False) -> int:
    """Return a color attribute, keeping selection visible on monochrome terminals."""
    if curses.has_colors():
        attr = curses.color_pair(pair)
    else:
        attr = curses.A_REVERSE if selected else curses.A_NORMAL
    return attr | curses.A_BOLD if bold else attr


def _status_pair(status: str, selected: bool) -> int:
    key = (status or "").strip().lower()
    meta = STATUS_META.get(key)
    if meta:
        pair = meta[2] if selected else meta[1]
    else:
        pair = 25 if selected else 15
    return _color_attr(pair, selected, bold=selected)


def _is_interesting_status(status: str) -> bool:
    key = (status or "").strip().lower()
    return key not in ("idle", "unknown")


def _filtered_tab_indices(
    rows: list[dict[str, str]],
    filter_on: bool,
    query: str = "",
) -> list[int]:
    indices = list(range(len(rows)))
    if filter_on:
        indices = [i for i in indices if _is_interesting_status(rows[i].get("status", ""))]
    q = (query or "").strip().lower()
    if not q:
        return indices
    out: list[int] = []
    for i in indices:
        row = rows[i]
        hay = f"{row.get('tab', '')} {row.get('workspace', '')} {row.get('status', '')}".lower()
        if q in hay:
            out.append(i)
    return out


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
        # The expanded set preserves folding while filters change.
        is_open = wid in expanded
        entries.append(
            {
                "kind": "ws",
                "workspace_id": wid,
                "workspace": labels.get(wid, wid),
                "count": len(indices),
                "expanded": is_open,
            }
        )
        if is_open:
            for i in indices:
                entries.append(
                    {
                        "kind": "tab",
                        "idx": i,
                        "workspace_id": wid,
                    }
                )
    return entries


def _visible_entries(entries: list[dict[str, Any]], cursor: int, view_h: int) -> list[int | None]:
    """Map screen rows to entries, spacing workspaces only when the whole list fits."""
    groups = sum(entry["kind"] == "ws" for entry in entries)
    spaced = len(entries) + max(0, groups - 1) <= view_h
    top = 0 if spaced else max(0, cursor - view_h + 1)
    visible: list[int | None] = []
    for index in range(top, len(entries)):
        if len(visible) >= view_h:
            break
        if spaced and index > 0 and entries[index]["kind"] == "ws":
            visible.append(None)
        visible.append(index)
    return visible


def pick_index(
    rows: list[dict[str, str]],
    start: int,
    last_id: str | None = None,
) -> int | None:
    def _ui(stdscr: curses.window) -> int | None:
        try:
            curses.curs_set(0)
        except curses.error:
            pass  # Some monochrome terminals cannot change cursor visibility.
        _init_colors()
        try:
            curses.mousemask(curses.ALL_MOUSE_EVENTS | curses.REPORT_MOUSE_POSITION)
            curses.mouseinterval(0)
        except curses.error:
            pass

        filter_on = False
        query = ""
        query_mode = False
        pending_g = False
        start_idx = max(0, min(start, len(rows) - 1))
        # Default: expand every workspace; h/l (or arrows in / mode) still folds.
        expanded = {
            (r.get("workspace_id") or "?")
            for r in rows
        }
        cursor = 0  # index into entries

        def rebuild() -> list[dict[str, Any]]:
            nonlocal cursor
            tabs = _filtered_tab_indices(rows, filter_on, query)
            entries = _build_entries(rows, tabs, expanded)
            if not entries:
                cursor = 0
                return entries
            cursor = max(0, min(cursor, len(entries) - 1))
            return entries

        def snap_to_ws(wid: str) -> None:
            nonlocal cursor
            entries2 = _build_entries(
                rows,
                _filtered_tab_indices(rows, filter_on, query),
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
            if height < 6 or width < 24:
                _put(stdscr, 0, 0, "window too small", curses.A_BOLD)
                stdscr.refresh()
                pending_g = False
                stdscr.timeout(-1)
                ch = stdscr.getch()
                if ch in (27, ord("q")):
                    return None
                continue

            inner = width - 1
            right = inner - 1
            search_row = 2 if height >= 12 else 1
            list_top = search_row + 2
            footer_rows = 2 if width >= 60 and height >= 10 else 1
            sep_bottom = height - footer_rows - 1
            view_h = max(1, sep_bottom - list_top)
            visible = _visible_entries(entries, cursor, view_h)
            animating = any(
                entry["kind"] == "tab" and rows[int(entry["idx"])]["status"].strip().lower() == "working"
                for entry in entries
            )
            stdscr.timeout(SPINNER_INTERVAL_MS if animating else -1)
            spinner = SPINNER_FRAMES[
                (time.monotonic_ns() // (SPINNER_INTERVAL_MS * 1_000_000)) % len(SPINNER_FRAMES)
            ]

            matching_tabs = _filtered_tab_indices(rows, filter_on, query)
            workspaces = {row["workspace_id"] for row in rows}
            if filter_on or query:
                summary = f"{len(matching_tabs)} / {len(rows)} matches"
            else:
                summary = f"{len(rows)} tabs / {len(workspaces)} spaces"
            if inner < 42:
                summary = f"{len(matching_tabs)}/{len(rows)}"
            _put(stdscr, 0, 1, "TAB GOTO", _color_attr(8, bold=True))
            _put(stdscr, 0, right - len(summary), summary, _color_attr(2))

            filter_label = "[status]" if filter_on else ""
            search_width = right - 3 - len(filter_label) - (2 if filter_on else 0)
            search = query
            if query_mode:
                search += "█"
            elif not search:
                search = "Search tabs..."
            _put(stdscr, search_row, 1, "/", _color_attr(3))
            _put(stdscr, search_row, 3, _fit(search, search_width),
                 _color_attr(3 if query_mode else 2))
            if filter_on:
                _put(stdscr, search_row, right - len(filter_label), filter_label, _color_attr(3))
            separator = "─" * max(0, inner - 2)
            _put(stdscr, search_row + 1, 1, separator, _color_attr(5))

            # Numbers follow expanded tabs, including entries outside the viewport.
            tab_ord: dict[int, str] = {}
            ordinal = 0
            for entry_index, ent in enumerate(entries):
                if ent["kind"] == "tab":
                    ordinal += 1
                    if ordinal <= len(TAB_SHORTCUTS):
                        tab_ord[entry_index] = TAB_SHORTCUTS[ordinal - 1]

            if not entries:
                message = "No matches. /: edit search" if query else "No matches. f: reset status"
                _put(stdscr, list_top, 2, _fit(message, inner - 3), _color_attr(2))

            for row_index, entry_index in enumerate(visible):
                if entry_index is None:
                    continue
                ent = entries[entry_index]
                selected = entry_index == cursor
                y = list_top + row_index
                base = _color_attr(1 if selected else 4, selected, bold=selected)
                muted = _color_attr(6 if selected else 2, selected)
                accent = _color_attr(9 if selected else 3, selected, bold=True)
                bright = _color_attr(1 if selected else 8, selected, bold=True)
                if selected:
                    _put(stdscr, y, 0, " " * inner, base)

                if ent["kind"] == "ws":
                    count = f"{ent['count']} tab" + ("" if ent["count"] == 1 else "s")
                    count_at = right - len(count)
                    _put(stdscr, y, 1, "▾" if ent["expanded"] else "▸", accent)
                    _put(stdscr, y, 3, _fit(ent["workspace"], count_at - 5), bright)
                    _put(stdscr, y, count_at, count, muted)
                    continue

                row = rows[int(ent["idx"])]
                name_at = 10
                status_at = right - 7
                name_width = status_at - name_at - 4
                if selected:
                    _put(stdscr, y, 1, ">", accent)
                number = tab_ord.get(entry_index)
                if number is not None:
                    _put(stdscr, y, 3, str(number), accent if selected else muted)
                name = _TAB_NUM_PREFIX.sub("", row["tab"]) or row["tab"]
                _put(stdscr, y, name_at, _fit(name, name_width), bright if selected else base)
                if row.get("focused") == "1":
                    _put(stdscr, y, 6, "●", _color_attr(1 if selected else 16, selected, bold=True))
                elif last_id and row["tab_id"] == last_id:
                    _put(stdscr, y, 8, "○", _color_attr(1 if selected else 7, selected, bold=True))
                status_attr = _status_pair(row["status"], selected)
                if row["status"].strip().lower() == "working":
                    _put(stdscr, y, status_at - 2, spinner, status_attr)
                _put(stdscr, y, status_at, _status_badge(row["status"]), status_attr)

            _put(stdscr, sep_bottom, 1, separator, _color_attr(5))
            footer_row = sep_bottom + 1
            workspace_selected = bool(entries) and entries[cursor]["kind"] == "ws"
            enter_hint = "Enter fold" if workspace_selected else "Enter switch"
            if query_mode:
                escape_hint = "Esc done"
                help_text = f"Up/Down move   {enter_hint}"
                extra = "Ctrl-U clear   Esc leave input"
            else:
                escape_hint = "Esc clear" if query else "Esc close"
                help_text = f"j/k move   {enter_hint}   / search   f status"
                extra = f"1-9,0,a-e jump   n last   h/l fold   {escape_hint}"
            if footer_rows == 2:
                _put(stdscr, footer_row, 1, _fit(help_text, inner - 2), _color_attr(2))
                _put(stdscr, footer_row + 1, 1, _fit(extra, inner - 2), _color_attr(2))
            else:
                middle = "  " if query_mode else "  / search  "
                help_text = enter_hint + middle + escape_hint
                if inner < 34:
                    help_text = "Enter fold" if workspace_selected else "Enter pick"
                    help_text += "  Esc done" if query_mode else "  / search"
                _put(stdscr, footer_row, 1, _fit(help_text, inner - 2), _color_attr(2))

            stdscr.refresh()

            ch = stdscr.getch()
            if ch == -1:
                continue  # Animation ticks must preserve pending keyboard prefixes.

            def move_down() -> None:
                nonlocal cursor
                if entries:
                    cursor = (cursor + 1) % len(entries)

            def move_up() -> None:
                nonlocal cursor
                if entries:
                    cursor = (cursor - 1) % len(entries)

            def fold_right() -> None:
                if not entries:
                    return
                ent = entries[cursor]
                wid = str(ent.get("workspace_id") or "")
                if wid:
                    expanded.add(wid)

            def fold_left() -> None:
                if not entries:
                    return
                ent = entries[cursor]
                wid = str(ent.get("workspace_id") or "")
                if wid:
                    expanded.discard(wid)
                    snap_to_ws(wid)

            def activate() -> int | None:
                if not entries:
                    return None
                ent = entries[cursor]
                if ent["kind"] == "tab":
                    return int(ent["idx"])
                wid = str(ent.get("workspace_id") or "")
                if not wid:
                    return None
                if ent.get("expanded"):
                    expanded.discard(wid)
                else:
                    expanded.add(wid)
                return None

            def handle_mouse() -> int | None:
                nonlocal cursor
                try:
                    _id, mx, my, _z, bstate = curses.getmouse()
                except curses.error:
                    return None
                clicked = bstate & (
                    getattr(curses, "BUTTON1_CLICKED", 0)
                    | getattr(curses, "BUTTON1_PRESSED", 0)
                    | getattr(curses, "BUTTON1_RELEASED", 0)
                )
                moved = bstate & getattr(curses, "REPORT_MOUSE_POSITION", 0)
                if not clicked and bstate == 0:
                    clicked = True
                if not clicked and not moved:
                    return None
                if not entries:
                    return None
                if my < list_top or my >= list_top + len(visible):
                    return None
                e_i = visible[my - list_top]
                if e_i is None:
                    return None
                ent = entries[e_i]
                cursor = e_i
                if not clicked:
                    return None
                if ent["kind"] == "tab":
                    return int(ent["idx"])
                wid = str(ent.get("workspace_id") or "")
                if not wid:
                    return None
                if ent.get("expanded"):
                    expanded.discard(wid)
                else:
                    expanded.add(wid)
                return None

            if query_mode:
                if ch == 27:  # esc → leave input mode (keep query)
                    query_mode = False
                elif ch == 21:  # ctrl-u clear query
                    query = ""
                elif ch in (curses.KEY_BACKSPACE, 127, 8):
                    query = query[:-1]
                elif ch == curses.KEY_UP:
                    move_up()
                elif ch == curses.KEY_DOWN:
                    move_down()
                elif ch == curses.KEY_LEFT:
                    fold_left()
                elif ch == curses.KEY_RIGHT:
                    fold_right()
                elif ch in (curses.KEY_ENTER, 10, 13):
                    picked = activate()
                    if picked is not None:
                        return picked
                elif ch == curses.KEY_MOUSE:
                    picked = handle_mouse()
                    if picked is not None:
                        return picked
                elif 32 <= ch <= 126:
                    query += chr(ch)
                # ignore other keys in query mode (including q/f as letters only if printable)
                continue

            # A second consecutive g jumps to the first visible tree entry.
            if ch == ord("g"):
                if pending_g:
                    cursor = 0
                pending_g = not pending_g
                continue
            if ch != curses.KEY_RESIZE:
                pending_g = False

            # normal mode
            if ch == ord("G"):
                cursor = max(0, len(entries) - 1)
            elif ch in (ord("j"), curses.KEY_DOWN):
                move_down()
            elif ch in (ord("k"), curses.KEY_UP):
                move_up()
            elif ch in (ord("l"), curses.KEY_RIGHT):
                fold_right()
            elif ch in (ord("h"), curses.KEY_LEFT):
                fold_left()
            elif ch in (ord("f"), ord("F")):
                filter_on = not filter_on
            elif ch in (ord("/"),):
                query_mode = True
            elif ch in (ord("n"),):
                if last_id:
                    for i, row in enumerate(rows):
                        if row.get("tab_id") == last_id:
                            return i
            elif 0 <= ch < 128 and chr(ch) in TAB_SHORTCUTS:
                # Shortcuts count expanded tabs; ignore keys beyond the list.
                want = TAB_SHORTCUTS.index(chr(ch)) + 1
                seen = 0
                for ent in entries:
                    if ent.get("kind") != "tab":
                        continue
                    seen += 1
                    if seen == want:
                        return int(ent["idx"])
            elif ch in (curses.KEY_ENTER, 10, 13):
                picked = activate()
                if picked is not None:
                    return picked
            elif ch == ord(" "):
                # Space activates like enter; the filter query types it instead
                # (see the 32..126 branch above).
                picked = activate()
                if picked is not None:
                    return picked
            elif ch == curses.KEY_MOUSE:
                picked = handle_mouse()
                if picked is not None:
                    return picked
            elif ch == 27:  # esc: clear query if any, else quit
                if query:
                    query = ""
                else:
                    return None
            elif ch in (ord("q"),):
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
    here_id = rows[start]["tab_id"]
    last_id = read_last_tab()
    try:
        chosen = pick_index(rows, start, last_id=last_id)
    except curses.error as exc:
        pause(f"curses UI failed: {exc}")
        return 1

    if chosen is None:
        return 0

    tab_id = rows[chosen]["tab_id"]
    if tab_id != here_id:
        write_last_tab(here_id)
    try:
        focus_tab(bin_path, tab_id)
    except Exception as exc:
        pause(f"herdr tab focus failed for {tab_id}: {exc}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
