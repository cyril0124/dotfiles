#!/usr/bin/env python3
"""Open the close-confirm popup (titled)."""

from __future__ import annotations

import os
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


def main() -> int:
    bin_path = herdr_bin()
    os.execv(
        bin_path,
        [
            bin_path,
            "plugin",
            "pane",
            "open",
            "--plugin",
            "local.pane-close",
            "--entrypoint",
            "confirm",
            "--placement",
            "popup",
            "--width",
            "34",
            "--height",
            "9",
            "--focus",
        ],
    )


if __name__ == "__main__":
    raise SystemExit(main())
