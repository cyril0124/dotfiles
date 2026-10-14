#!/usr/bin/env python3
"""Open the tab-goto picker popup with content-based size (stdlib only)."""

from __future__ import annotations

import json
import os
import socket
import sys

from picker import _TAB_NUM_PREFIX, herdr_bin, herdr_json, load_tabs


def content_size(rows: list[dict[str, str]], cols: int, lines: int) -> tuple[int, int]:
    groups = len({row["workspace_id"] for row in rows})
    # 7 chrome rows, 2 outer border rows, and optional workspace spacing.
    wanted = len(rows) + groups + max(0, groups - 1) + 9
    height = min(max(wanted, 12), lines)
    max_line = max(
        (max(len(_TAB_NUM_PREFIX.sub("", row["tab"]) or row["tab"]), len(row["workspace"]))
         for row in rows),
        default=0,
    )
    # Indentation, gaps, current/last, status, and outer popup borders.
    width = min(max(max_line + 27, 68), cols * 92 // 100)
    return width, height


def popup_size(bin_path: str) -> tuple[int, int]:
    rows = load_tabs(bin_path)
    area = herdr_json(bin_path, "pane", "layout")["layout"]["area"]
    cols, lines = area["width"], area["height"]
    if type(cols) is not int or type(lines) is not int or cols <= 0 or lines <= 0:
        raise ValueError("pane layout must contain positive integer area dimensions")
    return content_size(rows, cols, lines)


def main() -> int:
    width, height = popup_size(herdr_bin())
    request = {
        "id": "local.tab-goto.open",
        "method": "plugin.pane.open",
        "params": {
            "plugin_id": "local.tab-goto",
            "entrypoint": "picker",
            "placement": "popup",
            "width": width,
            "height": height,
            "focus": True,
        },
    }
    with socket.socket(socket.AF_UNIX) as sock:
        sock.connect(os.environ["HERDR_SOCKET_PATH"])
        sock.sendall((json.dumps(request) + "\n").encode())
        with sock.makefile("r", encoding="utf-8") as stream:
            response = json.loads(stream.readline())
    if "error" in response:
        raise RuntimeError(f"plugin.pane.open: {response['error']}")
    if not isinstance(response.get("result"), dict):
        raise RuntimeError(f"plugin.pane.open: malformed response: {response}")
    print(json.dumps(response))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"failed to open tab picker: {exc}", file=sys.stderr)
        raise SystemExit(1)
