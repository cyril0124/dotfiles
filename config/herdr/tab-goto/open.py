#!/usr/bin/env python3
"""Open the tab-goto picker popup with content-based size (stdlib only)."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys


def herdr_bin() -> str:
    path = os.environ.get("HERDR_BIN_PATH") or ""
    if path and os.access(path, os.X_OK):
        return path
    from shutil import which

    found = which("herdr")
    if not found:
        print("herdr not found", file=sys.stderr)
        sys.exit(1)
    return found


def herdr_json(bin_path: str, *args: str) -> dict:
    raw = subprocess.check_output([bin_path, *args], stderr=subprocess.DEVNULL)
    payload = json.loads(raw)
    if not isinstance(payload, dict):
        return {}
    result = payload.get("result")
    return result if isinstance(result, dict) else payload


def popup_size(bin_path: str) -> tuple[int, int]:
    tabs: list = []
    try:
        tabs = herdr_json(bin_path, "tab", "list").get("tabs") or []
    except Exception:
        tabs = []
    if not isinstance(tabs, list):
        tabs = []

    workspaces: dict[str, str] = {}
    try:
        for ws in herdr_json(bin_path, "workspace", "list").get("workspaces") or []:
            if not isinstance(ws, dict):
                continue
            wid = ws.get("workspace_id")
            if isinstance(wid, str) and wid:
                label = ws.get("label")
                workspaces[wid] = label if isinstance(label, str) and label else wid
    except Exception:
        pass

    max_line = len("  tab  workspace  RUN ")
    for tab in tabs:
        if not isinstance(tab, dict):
            continue
        wid = tab.get("workspace_id") if isinstance(tab.get("workspace_id"), str) else "?"
        wlabel = workspaces.get(wid, wid)
        tlabel = (
            tab.get("label")
            if isinstance(tab.get("label"), str) and tab.get("label")
            else (tab.get("tab_id") or "")
        )
        status = tab.get("agent_status") if isinstance(tab.get("agent_status"), str) else ""
        # marker + tab + gaps + workspace + badge
        line_len = 2 + len(str(tlabel)) + 2 + len(wlabel) + 2 + max(4, len(status))
        max_line = max(max_line, line_len)

    term = shutil.get_terminal_size(fallback=(100, 30))
    n = max(1, len(tabs))
    # chrome ≈ help + seps + footer + border
    height = max(10, min(n + 6, max(10, int(term.lines * 0.85))))
    width = max(40, min(max_line + 8, max(40, int(term.columns * 0.92))))
    return width, height


def main() -> int:
    bin_path = herdr_bin()
    width, height = popup_size(bin_path)
    cmd = [
        bin_path,
        "plugin",
        "pane",
        "open",
        "--plugin",
        "local.tab-goto",
        "--entrypoint",
        "picker",
        "--placement",
        "popup",
        "--width",
        str(width),
        "--height",
        str(height),
        "--focus",
    ]
    os.execv(bin_path, cmd)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except subprocess.CalledProcessError as exc:
        print(f"failed: {exc}", file=sys.stderr)
        raise SystemExit(exc.returncode or 1)
