#!/usr/bin/env python3
"""Action local.action-palette.open: open the palette popup pane.

Runs on the herdr server (no TTY). Talks to the socket API directly.
Forwards the origin pane's cwd so context-aware actions invoked from the
popup resolve the right repo.
"""

from __future__ import annotations

import json
import os
import shutil
import sys

from herdr_api import call


def popup_size() -> tuple[int, int]:
    """Content-based size: widest action line + count, bounded by terminal."""
    try:
        actions = call("plugin.action.list").get("actions") or []
    except Exception:
        actions = []

    max_line = len("▸ █  enter run · esc close")
    for act in actions:
        if not isinstance(act, dict):
            continue
        qid = f"{act.get('plugin_id', '')}.{act.get('action_id', '')}"
        # marker(3) + title + gap(2) + id + margin
        max_line = max(max_line, 3 + len(act.get("title") or "") + 2 + len(qid) + 2)

    term = shutil.get_terminal_size(fallback=(100, 30))
    n = max(1, len(actions))
    # chrome: prompt + 2 separators + footer + border
    height = max(9, min(n + 5, max(9, int(term.lines * 0.85))))
    width = max(52, min(max_line + 2, max(52, int(term.columns * 0.92))))
    return width, height


def origin_cwd() -> str:
    raw = os.environ.get("HERDR_PLUGIN_CONTEXT_JSON") or ""
    try:
        ctx = json.loads(raw)
    except (json.JSONDecodeError, ValueError):
        ctx = {}
    if not isinstance(ctx, dict):
        ctx = {}
    for key in ("focused_pane_cwd", "workspace_cwd"):
        value = ctx.get(key)
        if isinstance(value, str) and os.path.isdir(value):
            return value
    return ""


def main() -> int:
    width, height = popup_size()
    params = {
        "plugin_id": "local.action-palette",
        "entrypoint": "palette",
        "placement": "popup",
        "width": width,
        "height": height,
        "focus": True,
    }
    cwd = origin_cwd()
    if cwd:
        params["cwd"] = cwd
    try:
        call("plugin.pane.open", params)
    except RuntimeError as exc:
        print(exc, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
