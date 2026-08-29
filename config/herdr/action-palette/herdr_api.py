"""Minimal herdr socket API client: newline-delimited JSON over unix socket."""

from __future__ import annotations

import json
import os
import socket
from typing import Any


def _socket_path() -> str:
    path = os.environ.get("HERDR_SOCKET_PATH") or ""
    if path:
        return path
    return os.path.expanduser("~/.config/herdr/herdr.sock")


def call(method: str, params: dict[str, Any] | None = None) -> dict[str, Any]:
    """Send one request, return `result`; raise RuntimeError on API error."""
    request = {"id": "local.action-palette", "method": method, "params": params or {}}
    with socket.socket(socket.AF_UNIX) as sock:
        sock.settimeout(10)
        sock.connect(_socket_path())
        sock.sendall((json.dumps(request) + "\n").encode())
        buf = b""
        while b"\n" not in buf:
            chunk = sock.recv(65536)
            if not chunk:
                raise RuntimeError(f"{method}: connection closed before response")
            buf += chunk
    response = json.loads(buf.split(b"\n", 1)[0])
    error = response.get("error")
    if error:
        raise RuntimeError(f"{method}: {error.get('code')}: {error.get('message')}")
    result = response.get("result")
    if not isinstance(result, dict):
        raise RuntimeError(f"{method}: malformed response: {response!r}")
    return result
