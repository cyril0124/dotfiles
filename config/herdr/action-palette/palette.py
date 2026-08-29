#!/usr/bin/env python3
"""Pane local.action-palette.palette: interactive action picker.

Stdlib curses over the herdr socket API, type-to-filter, enter invokes.
After dispatch, polls the plugin log so a failed action surfaces its
stderr instead of vanishing.
"""

from __future__ import annotations

import curses
import locale
import os
import sys
import time

from herdr_api import call

SELF_PLUGIN = os.environ.get("HERDR_PLUGIN_ID") or "local.action-palette"


def load_actions() -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    for act in call("plugin.action.list").get("actions") or []:
        if not isinstance(act, dict):
            continue
        pid = act.get("plugin_id")
        aid = act.get("action_id")
        if not isinstance(pid, str) or not isinstance(aid, str):
            continue
        if pid == SELF_PLUGIN:
            continue
        title = act.get("title") if isinstance(act.get("title"), str) else ""
        desc = act.get("description") if isinstance(act.get("description"), str) else ""
        rows.append({"plugin_id": pid, "action_id": aid, "title": title, "desc": desc})
    rows.sort(key=lambda r: (r["plugin_id"], r["action_id"]))
    return rows


def pause(msg: str) -> None:
    sys.stdout.write(f"{msg}\nPress enter to close.\n")
    sys.stdout.flush()
    try:
        sys.stdin.readline()
    except Exception:
        pass


def _matches(row: dict[str, str], query: str) -> bool:
    q = query.strip().lower()
    if not q:
        return True
    hay = f"{row['plugin_id']}.{row['action_id']} {row['title']}".lower()
    return all(word in hay for word in q.split())


def _fit(text: str, width: int) -> str:
    if width <= 0:
        return ""
    if len(text) <= width:
        return text.ljust(width)
    if width <= 1:
        return text[:width]
    return text[: width - 1] + "."


def _put(stdscr: curses.window, y: int, x: int, text: str, attr: int = 0) -> None:
    height, width = stdscr.getmaxyx()
    if y < 0 or y >= height or x < 0 or x >= width:
        return
    try:
        stdscr.addstr(y, x, text[: width - x - 1], attr)
    except curses.error:
        pass


def pick(rows: list[dict[str, str]]) -> dict[str, str] | None:
    def _ui(stdscr: curses.window) -> dict[str, str] | None:
        curses.curs_set(0)
        has_color = curses.has_colors()
        if has_color:
            curses.start_color()
            curses.use_default_colors()
            curses.init_pair(1, curses.COLOR_BLACK, curses.COLOR_CYAN)   # selected row
            curses.init_pair(2, curses.COLOR_CYAN, -1)                   # prompt / accents
            curses.init_pair(3, curses.COLOR_WHITE, -1)                  # dim ids
            curses.init_pair(4, curses.COLOR_BLACK, curses.COLOR_CYAN)   # id on selected

        query = ""
        cursor = 0

        while True:
            visible = [r for r in rows if _matches(r, query)]
            cursor = max(0, min(cursor, len(visible) - 1))

            stdscr.erase()
            height, width = stdscr.getmaxyx()
            inner = max(0, width - 1)

            # prompt
            prompt = "▸ "
            prompt_attr = curses.color_pair(2) | curses.A_BOLD if has_color else curses.A_BOLD
            _put(stdscr, 0, 1, prompt, prompt_attr)
            _put(stdscr, 0, 1 + len(prompt), query, curses.A_BOLD)
            _put(stdscr, 0, 1 + len(prompt) + len(query), "█", curses.A_DIM)
            hint = "enter run · esc close"
            if inner - len(hint) - 2 > len(prompt) + len(query) + 4:
                _put(stdscr, 0, inner - len(hint) - 1, hint, curses.A_DIM)

            sep = " " + "─" * max(0, inner - 2)
            _put(stdscr, 1, 0, sep, curses.A_DIM)

            list_top = 2
            footer_row = height - 1
            sep_bottom = height - 2
            view_h = max(1, sep_bottom - list_top)
            top = max(0, cursor - view_h + 1)

            id_w = max((len(f"{r['plugin_id']}.{r['action_id']}") for r in visible), default=0)
            title_w = max(12, inner - id_w - 6)

            for i in range(view_h):
                idx = top + i
                if idx >= len(visible):
                    break
                row = visible[idx]
                qid = f"{row['plugin_id']}.{row['action_id']}"
                y = list_top + i
                selected = idx == cursor

                if selected:
                    base = curses.color_pair(1) | curses.A_BOLD if has_color else curses.A_REVERSE | curses.A_BOLD
                    id_attr = curses.color_pair(4) if has_color else curses.A_REVERSE
                    _put(stdscr, y, 0, " " * inner, base)
                    _put(stdscr, y, 1, "▸ ", base)
                else:
                    base = curses.A_NORMAL
                    id_attr = (curses.color_pair(3) | curses.A_DIM) if has_color else curses.A_DIM

                _put(stdscr, y, 3, _fit(row["title"] or row["action_id"], title_w), base)
                id_at = 3 + title_w + 2
                if id_at < inner:
                    _put(stdscr, y, id_at, _fit(qid, max(0, inner - id_at)), id_attr)

            if not visible:
                _put(stdscr, list_top, 1, "no matches — edit filter or esc", curses.A_DIM)

            _put(stdscr, sep_bottom, 0, sep, curses.A_DIM)

            # footer: count + selected action's description
            if visible:
                footer = f"{cursor + 1}/{len(visible)}"
                desc = visible[cursor].get("desc") or ""
                if desc:
                    footer += f"  {desc}"
            else:
                footer = "0/0"
            _put(stdscr, footer_row, 1, _fit(footer, max(0, inner - 1)), curses.A_DIM)

            stdscr.refresh()
            ch = stdscr.getch()

            if ch in (27,):  # esc: clear query first, then quit
                if query:
                    query = ""
                else:
                    return None
            elif ch in (curses.KEY_ENTER, 10, 13):
                if visible:
                    return visible[cursor]
            elif ch in (curses.KEY_DOWN, 14):  # down / ctrl-n
                if visible:
                    cursor = (cursor + 1) % len(visible)
            elif ch in (curses.KEY_UP, 16):  # up / ctrl-p
                if visible:
                    cursor = (cursor - 1) % len(visible)
            elif ch == 21:  # ctrl-u
                query = ""
            elif ch in (curses.KEY_BACKSPACE, 127, 8):
                query = query[:-1]
            elif 32 <= ch <= 126:
                query += chr(ch)
                cursor = 0

    return curses.wrapper(_ui)


def notify(title: str, body: str) -> None:
    try:
        call("notification.show", {"title": title, "body": body[:500]})
    except Exception:
        pass


def invoke_detached(plugin_id: str, action_id: str) -> None:
    """Invoke AFTER this popup closes, from a detached child.

    Invoking while the palette popup is still open breaks any action that
    opens its own popup (herdr: "popup already open"), so the parent exits
    first and the orphaned child does the invoke. No TTY there, so failures
    are surfaced via notification.show instead of pause().
    """
    if os.fork() > 0:
        return  # parent: exit main(), popup closes

    # child: orphaned, own session, silent stdio
    os.setsid()
    devnull = os.open(os.devnull, os.O_RDWR)
    for fd in (0, 1, 2):
        os.dup2(devnull, fd)

    qid = f"{plugin_id}.{action_id}"
    time.sleep(0.2)  # let the popup actually close server-side
    try:
        result = call("plugin.action.invoke", {"plugin_id": plugin_id, "action_id": action_id})
    except Exception as exc:
        notify(f"invoke {qid} failed", str(exc))
        os._exit(1)

    log = result.get("log") or {}
    log_id = log.get("log_id") if isinstance(log, dict) else ""
    if not log_id:
        os._exit(0)

    # ~5s deadline; a run still going is assumed to be a healthy long action.
    for _ in range(25):
        time.sleep(0.2)
        try:
            logs = call("plugin.log.list", {"plugin_id": plugin_id, "limit": 20}).get("logs") or []
        except RuntimeError:
            os._exit(0)
        entry = next(
            (e for e in logs if isinstance(e, dict) and e.get("log_id") == log_id),
            None,
        )
        if not entry:
            continue
        status = entry.get("status")
        if status == "succeeded":
            os._exit(0)
        if status == "failed":
            notify(
                f"{qid} failed (exit {entry.get('exit_code', '?')})",
                entry.get("stderr") or "",
            )
            os._exit(1)
    os._exit(0)


def main() -> int:
    try:
        locale.setlocale(locale.LC_ALL, "")
    except locale.Error:
        pass

    if not sys.stdin.isatty() or not sys.stdout.isatty():
        pause("action-palette needs a TTY (run from herdr popup).")
        return 1

    try:
        rows = load_actions()
    except Exception as exc:
        pause(f"Failed to list plugin actions: {exc}")
        return 1

    if not rows:
        pause("No plugin actions available.")
        return 0

    try:
        chosen = pick(rows)
    except curses.error as exc:
        pause(f"curses UI failed: {exc}")
        return 1

    if chosen is None:
        return 0
    invoke_detached(chosen["plugin_id"], chosen["action_id"])
    return 0


if __name__ == "__main__":
    sys.exit(main())
