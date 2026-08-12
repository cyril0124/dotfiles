#!/usr/bin/env python3
"""Polished close-pane confirm for a small herdr popup (stdlib curses)."""

from __future__ import annotations

import curses
import json
import locale
import os
import subprocess
import sys


def herdr_bin() -> str:
    path = os.environ.get("HERDR_BIN_PATH") or ""
    if path and os.access(path, os.X_OK):
        return path
    from shutil import which

    found = which("herdr")
    if not found:
        raise RuntimeError("herdr not found")
    return found


def focused_pane_id(bin_path: str) -> str | None:
    env_id = os.environ.get("HERDR_ACTIVE_PANE_ID") or ""
    if env_id:
        return env_id
    try:
        raw = subprocess.check_output(
            [bin_path, "pane", "layout"], stderr=subprocess.DEVNULL
        )
        payload = json.loads(raw)
        result = payload.get("result") or payload
        layout = result.get("layout") or {}
        pid = layout.get("focused_pane_id")
        return pid if isinstance(pid, str) and pid else None
    except Exception:
        return None


def short_id(pane_id: str) -> str:
    return pane_id.rsplit(":", 1)[-1] if ":" in pane_id else pane_id


def put(stdscr: curses.window, y: int, x: int, text: str, attr: int = 0) -> None:
    try:
        h, w = stdscr.getmaxyx()
        if y < 0 or y >= h or x >= w:
            return
        stdscr.addstr(y, max(0, x), text[: max(0, w - max(0, x) - 1)], attr)
    except curses.error:
        pass


def center_x(width: int, text: str) -> int:
    return max(0, (width - len(text)) // 2)


def dialog(stdscr: curses.window, title: str, subtitle: str) -> bool:
    """Return True if user confirms close."""
    curses.curs_set(0)
    # Request mouse; works when the herdr popup forwards events to the pane.
    try:
        curses.mousemask(curses.ALL_MOUSE_EVENTS | curses.REPORT_MOUSE_POSITION)
        curses.mouseinterval(0)
    except curses.error:
        pass

    if curses.has_colors():
        curses.start_color()
        curses.use_default_colors()
        curses.init_pair(1, curses.COLOR_WHITE, -1)  # normal
        curses.init_pair(2, curses.COLOR_CYAN, -1)  # pane id
        curses.init_pair(3, curses.COLOR_BLACK, curses.COLOR_RED)  # yes button
        curses.init_pair(4, curses.COLOR_BLACK, curses.COLOR_WHITE)  # no button

    # Default focus No — accidental enter won't kill the pane.
    choice = 1  # 0 yes, 1 no

    while True:
        stdscr.erase()
        h, w = stdscr.getmaxyx()
        # Reserve last row for hints; center the rest above it.
        body_h = max(1, h - 1)
        # title, blank, id, blank, buttons  → 5 rows
        block = 5
        y0 = max(0, (body_h - block) // 2)

        put(stdscr, y0, center_x(w, title), title, curses.A_BOLD)
        put(
            stdscr,
            y0 + 2,
            center_x(w, subtitle),
            subtitle,
            curses.color_pair(2) | curses.A_BOLD if curses.has_colors() else curses.A_BOLD,
        )

        yes = "  Yes  "
        no = "  No  "
        gap = 3
        total = len(yes) + gap + len(no)
        x0 = center_x(w, " " * total)
        btn_y = y0 + 4
        yes_x0, yes_x1 = x0, x0 + len(yes)
        no_x0, no_x1 = x0 + len(yes) + gap, x0 + len(yes) + gap + len(no)

        yes_attr = (
            (curses.color_pair(3) | curses.A_BOLD)
            if choice == 0 and curses.has_colors()
            else (curses.A_REVERSE | curses.A_BOLD if choice == 0 else curses.A_DIM)
        )
        no_attr = (
            (curses.color_pair(4) | curses.A_BOLD)
            if choice == 1 and curses.has_colors()
            else (curses.A_REVERSE | curses.A_BOLD if choice == 1 else curses.A_DIM)
        )
        put(stdscr, btn_y, yes_x0, yes, yes_attr)
        put(stdscr, btn_y, no_x0, no, no_attr)

        # Always pin hints to the bottom row of the popup.
        hint = "y/n  ·  click  ·  enter"
        put(stdscr, h - 1, center_x(w, hint), hint, curses.A_DIM)

        stdscr.refresh()
        ch = stdscr.getch()
        if ch in (ord("y"), ord("Y")):
            return True
        if ch in (ord("n"), ord("N"), 27):  # esc
            return False
        if ch in (curses.KEY_LEFT, ord("h")):
            choice = 0
        elif ch in (curses.KEY_RIGHT, ord("l")):
            choice = 1
        elif ch in (ord("\t"),):
            choice = 1 - choice
        elif ch in (10, 13, curses.KEY_ENTER):
            return choice == 0
        elif ch in (ord("q"),):
            return False
        elif ch == curses.KEY_MOUSE:
            try:
                _id, mx, my, _z, bstate = curses.getmouse()
            except curses.error:
                continue
            # Accept press or click on either button.
            clicked = bstate & (
                getattr(curses, "BUTTON1_CLICKED", 0)
                | getattr(curses, "BUTTON1_PRESSED", 0)
                | getattr(curses, "BUTTON1_RELEASED", 0)
            )
            if not clicked and bstate == 0:
                # Some terminals only report coordinates with a generic event.
                clicked = True
            if not clicked:
                continue
            if my == btn_y and yes_x0 <= mx < yes_x1:
                return True
            if my == btn_y and no_x0 <= mx < no_x1:
                return False


def main() -> int:
    try:
        locale.setlocale(locale.LC_ALL, "")
    except locale.Error:
        pass

    try:
        bin_path = herdr_bin()
    except RuntimeError as exc:
        print(exc)
        return 1

    pane_id = focused_pane_id(bin_path)
    if not pane_id:
        def _empty(stdscr: curses.window) -> None:
            curses.curs_set(0)
            stdscr.erase()
            put(stdscr, 1, 1, "No focused pane", curses.A_BOLD)
            put(stdscr, 3, 1, "press any key", curses.A_DIM)
            stdscr.refresh()
            stdscr.getch()

        if sys.stdin.isatty():
            curses.wrapper(_empty)
        return 1

    label = short_id(pane_id)
    confirmed = curses.wrapper(lambda s: dialog(s, "Close this pane?", label))
    if not confirmed:
        return 0

    proc = subprocess.run(
        [bin_path, "pane", "close", pane_id],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
    )
    if proc.returncode != 0:
        err = (proc.stderr or "").strip() or "failed"

        def _err(stdscr: curses.window) -> None:
            curses.curs_set(0)
            stdscr.erase()
            put(stdscr, 1, 1, "Could not close", curses.A_BOLD)
            put(stdscr, 3, 1, err[: max(1, stdscr.getmaxyx()[1] - 2)], curses.A_DIM)
            put(stdscr, 5, 1, "press any key", curses.A_DIM)
            stdscr.refresh()
            stdscr.getch()

        if sys.stdin.isatty():
            curses.wrapper(_err)
        return proc.returncode
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
