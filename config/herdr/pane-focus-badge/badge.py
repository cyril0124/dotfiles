#!/usr/bin/env python3

import fcntl
import hashlib
import json
import os
import subprocess
from pathlib import Path


MARKER = "🟢"


def marked_label(label: str | None) -> str:
    if not label:
        return MARKER
    if label.startswith("[") and label.endswith("]"):
        title = label[1:-1]
        return f"[{MARKER} {title}]" if title else f"[{MARKER}]"
    return f"{MARKER} {label}"


def sync_badge(binary: str, state_file: Path) -> None:
    snapshot = json.loads(
        subprocess.check_output([binary, "api", "snapshot"], timeout=5)
    )["result"]["snapshot"]
    panes = snapshot["panes"]
    focused_id = snapshot.get("focused_pane_id")
    focused = next((pane for pane in panes if pane["pane_id"] == focused_id), None)

    if state_file.exists():
        previous_badge = json.loads(state_file.read_text())
        previous_pane = next(
            (pane for pane in panes if pane["terminal_id"] == previous_badge["terminal_id"]),
            None,
        )
        if previous_pane is not None and previous_pane.get("label") == previous_badge["marked"]:
            original_label = previous_badge["label"]
            badge_is_current = (
                previous_pane is focused
                and not previous_pane.get("title")
                and previous_badge["marked"] == marked_label(original_label)
            )
            if badge_is_current:
                return
            subprocess.run(
                [binary, "pane", "rename", previous_pane["pane_id"], original_label or "--clear"],
                check=True,
                timeout=5,
            )
            previous_pane["label"] = original_label
        state_file.unlink()

    # Agent-reported titles take precedence over manual labels in Herdr.
    if focused is None or focused.get("title"):
        return
    label = focused.get("label")
    marked = marked_label(label)
    badge = {"terminal_id": focused["terminal_id"], "label": label, "marked": marked}
    pending = state_file.with_suffix(".tmp")
    pending.write_text(json.dumps(badge))
    pending.replace(state_file)
    subprocess.run([binary, "pane", "rename", focused_id, marked], check=True, timeout=5)


def main() -> None:
    state_dir = Path(os.environ["HERDR_PLUGIN_STATE_DIR"])
    socket_path = os.environ["HERDR_SOCKET_PATH"]
    session = hashlib.sha256(os.fsencode(socket_path)).hexdigest()
    state_file = state_dir / f"{session}.json"
    with state_file.with_suffix(".lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        sync_badge(os.environ["HERDR_BIN_PATH"], state_file)


if __name__ == "__main__":
    main()
