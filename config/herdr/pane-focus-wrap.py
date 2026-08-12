#!/usr/bin/env python3
"""Focus neighboring pane with spatial wrap (stdlib only).

Usage: pane-focus-wrap.py left|right|up|down

1. Unzoom
2. If neighbor exists in direction → focus that way
3. Else wrap to the far pane on the opposite edge (same row/col overlap)
"""

from __future__ import annotations

import json
import os
import socket
import subprocess
import sys
from typing import Any


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


def herdr_json(bin_path: str, *args: str) -> dict[str, Any]:
    raw = subprocess.check_output([bin_path, *args], stderr=subprocess.DEVNULL)
    payload = json.loads(raw)
    if not isinstance(payload, dict):
        return {}
    result = payload.get("result")
    return result if isinstance(result, dict) else payload


def api_request(method: str, params: dict[str, Any]) -> dict[str, Any]:
    sock_path = os.environ.get("HERDR_SOCKET_PATH") or os.path.expanduser(
        "~/.config/herdr/herdr.sock"
    )
    req = json.dumps({"id": "pane-focus-wrap", "method": method, "params": params}) + "\n"
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
        sock.connect(sock_path)
        sock.sendall(req.encode())
        chunks: list[bytes] = []
        while True:
            data = sock.recv(65536)
            if not data:
                break
            chunks.append(data)
            if b"\n" in data:
                break
    text = b"".join(chunks).decode()
    line = text.splitlines()[0] if text else "{}"
    return json.loads(line)


def ranges_overlap(a0: int, a1: int, b0: int, b1: int) -> bool:
    return a0 < b1 and a1 > b0


def wrap_target(layout: dict[str, Any], focused_id: str, direction: str) -> str | None:
    panes = layout.get("panes") or []
    focused = next((p for p in panes if p.get("pane_id") == focused_id), None)
    if not focused:
        return None
    fr = focused.get("rect") or {}
    fx, fy = int(fr.get("x", 0)), int(fr.get("y", 0))
    fw, fh = int(fr.get("width", 0)), int(fr.get("height", 0))

    candidates: list[tuple[int, str]] = []
    for p in panes:
        pid = p.get("pane_id")
        if not isinstance(pid, str) or pid == focused_id:
            continue
        r = p.get("rect") or {}
        x, y = int(r.get("x", 0)), int(r.get("y", 0))
        w, h = int(r.get("width", 0)), int(r.get("height", 0))
        if direction in ("left", "right"):
            if not ranges_overlap(y, y + h, fy, fy + fh):
                continue
            # wrap left → rightmost; wrap right → leftmost
            key = x if direction == "right" else -(x + w)
            candidates.append((key, pid))
        else:
            if not ranges_overlap(x, x + w, fx, fx + fw):
                continue
            # wrap up → bottommost; wrap down → topmost
            key = y if direction == "down" else -(y + h)
            candidates.append((key, pid))

    if not candidates:
        # fall back: any pane extreme on that axis
        for p in panes:
            pid = p.get("pane_id")
            if not isinstance(pid, str) or pid == focused_id:
                continue
            r = p.get("rect") or {}
            x, y = int(r.get("x", 0)), int(r.get("y", 0))
            w, h = int(r.get("width", 0)), int(r.get("height", 0))
            if direction == "left":
                candidates.append((-(x + w), pid))
            elif direction == "right":
                candidates.append((x, pid))
            elif direction == "up":
                candidates.append((-(y + h), pid))
            else:
                candidates.append((y, pid))

    if not candidates:
        return None
    candidates.sort(key=lambda t: t[0])
    return candidates[0][1]


def main() -> int:
    if len(sys.argv) != 2 or sys.argv[1] not in ("left", "right", "up", "down"):
        print("usage: pane-focus-wrap.py left|right|up|down", file=sys.stderr)
        return 2

    direction = sys.argv[1]
    bin_path = herdr_bin()

    # Unzoom first so spatial neighbors are visible.
    subprocess.run(
        [bin_path, "pane", "zoom", "--off"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )

    try:
        neighbor = herdr_json(bin_path, "pane", "neighbor", "--current", "--direction", direction)
    except Exception as exc:
        print(f"neighbor failed: {exc}", file=sys.stderr)
        return 1

    # CLI nests under result.neighbor or returns neighbor fields at top of result.
    node = neighbor.get("neighbor") if isinstance(neighbor.get("neighbor"), dict) else neighbor
    nid = node.get("neighbor_pane_id")
    if isinstance(nid, str) and nid:
        subprocess.run(
            [bin_path, "pane", "focus", "--direction", direction],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
        return 0

    layout = node.get("layout")
    if not isinstance(layout, dict):
        try:
            layout = herdr_json(bin_path, "pane", "layout").get("layout") or {}
        except Exception:
            layout = {}

    focused_id = (
        node.get("pane_id")
        or layout.get("focused_pane_id")
        or ""
    )
    if not isinstance(focused_id, str) or not focused_id:
        return 0

    target = wrap_target(layout, focused_id, direction)
    if not target or target == focused_id:
        return 0

    resp = api_request("pane.focus", {"pane_id": target})
    if resp.get("error"):
        print(resp["error"], file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
