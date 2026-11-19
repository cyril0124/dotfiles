#!/usr/bin/env python3
"""Toggle half zoom on the calling pane (Herdr 0.9.5, Linux/macOS)."""

import fcntl
import hashlib
import json
import os
import socket
import sys
from pathlib import Path


def request(method, **params):
    with socket.socket(socket.AF_UNIX) as connection:
        connection.settimeout(5)
        connection.connect(os.environ["HERDR_SOCKET_PATH"])
        payload = {"id": "half-zoom", "method": method, "params": params}
        connection.sendall(json.dumps(payload).encode() + b"\n")
        with connection.makefile("rb") as reply:
            response = json.loads(reply.readline())
    if "error" in response:
        raise ValueError(response["error"]["message"])
    return response["result"]


def split(direction, ratio, first, second):
    return dict(
        type="split", direction=direction, ratio=ratio, first=first, second=second
    )


def topology(node):
    if node["type"] == "pane":
        return {"type": "pane", "pane_id": node["pane_id"]}
    return split(
        node["direction"],
        node["ratio"],
        topology(node["first"]),
        topology(node["second"]),
    )


def pane_ids(node):
    if node["type"] == "pane":
        yield node["pane_id"]
    else:
        yield from pane_ids(node["first"])
        yield from pane_ids(node["second"])


def replace_subtree(root, path, node):
    if not path:
        return node
    side, *remaining_path = path
    return root | {side: replace_subtree(root[side], remaining_path, node)}


def find_collapsible_split(node, selected, path=()):
    """Find a split between 2 panes and choose which pane to park."""
    first, second = node["first"], node["second"]
    for side, child in (("first", first), ("second", second)):
        if child["type"] == "split":
            return find_collapsible_split(child, selected, (*path, side))
    if second["pane_id"] == selected:
        return path, node, second, first
    return path, node, first, second


def plan_side_toggle(root, selected):
    enter_steps, restore_steps = [], []
    while root["type"] == "split":
        path, branch, anchor, parked = find_collapsible_split(root, selected)
        collapsed = replace_subtree(root, path, anchor)
        # Herdr inserts the returning pane as the second child of the split.
        inserted = replace_subtree(
            root, path, branch | {"first": anchor, "second": parked}
        )
        enter_steps.append(
            {"before": root, "after": collapsed, "park": parked["pane_id"]}
        )
        undo = [
            {
                "before": collapsed,
                "after": inserted,
                "insert": parked["pane_id"],
                "anchor": anchor["pane_id"],
                "direction": branch["direction"],
                "ratio": branch["ratio"],
            }
        ]
        if inserted != root:
            undo.append(
                {
                    "before": inserted,
                    "after": root,
                    "swap": [anchor["pane_id"], parked["pane_id"]],
                }
            )
        restore_steps = undo + restore_steps
        root = collapsed
    return enter_steps, restore_steps


def pane_info(pane_id):
    return request("pane.get", pane_id=pane_id)["pane"]


def move(pane_id, destination):
    result = request("pane.move", pane_id=pane_id, destination=destination)[
        "move_result"
    ]
    if not result["changed"]:
        raise ValueError(
            f"Cannot move {pane_id}: {result.get('reason', 'layout unchanged')}"
        )


def apply_step(tab, workspace, step, parking_anchor):
    if "park" in step:
        if parking_anchor is None:
            destination = {
                "type": "new_tab",
                "workspace_id": workspace,
                "label": "Half Zoom",
            }
        else:
            parking = pane_info(parking_anchor)
            if parking["tab_id"] == tab or parking["workspace_id"] != workspace:
                raise ValueError("Half Zoom parking tab changed")
            destination = {
                "type": "tab",
                "tab_id": parking["tab_id"],
                "target_pane_id": parking_anchor,
                "split": "down",
            }
        move(step["park"], destination)
    elif "insert" in step:
        move(
            step["insert"],
            {
                "type": "tab",
                "tab_id": tab,
                "target_pane_id": step["anchor"],
                "split": step["direction"],
                "ratio": step["ratio"],
            },
        )
    else:
        source, target = step["swap"]
        request("pane.swap", source_pane_id=source, target_pane_id=target)


def save(path, state):
    pending = path.with_suffix(".tmp")
    pending.write_text(json.dumps(state))
    pending.replace(path)


SIDES = ("first", "second")


def side_for(root, pane):
    for side in SIDES:
        if pane in pane_ids(root[side]):
            return side
    raise ValueError(f"Pane {pane} is no longer in this tab")


def load_state(path, root, selected):
    if not path.exists():
        return {"original_ratio": root["ratio"], "sides": {}}
    state = json.loads(path.read_text())
    if "sides" in state:
        return state

    # Older journals recorded whole-tab snapshots and ratio changes together.
    original = state["enter"][0]["before"]
    expanded = state.get("expanded_pane")
    if expanded is None:
        parked = next(iter(state["parked"]), None)
        if parked is not None:
            side = side_for(original, parked)
            final = state["enter"][-1]["after"]
            expanded = final[side]["pane_id"]
        else:
            expanded = selected
    side = side_for(original, expanded)
    phase = state["phase"]
    if phase != "active":
        completed = state[phase][: state["index"]]
        state["index"] = sum(
            "before" in step and step["before"][side] != step["after"][side]
            for step in completed
        )
    for direction in ("enter", "exit"):
        state[direction] = [
            step | {"before": step["before"][side], "after": step["after"][side]}
            for step in state[direction]
            if step["before"][side] != step["after"][side]
        ]
    state["expanded_pane"] = expanded
    return {"original_ratio": original["ratio"], "sides": {side: state}}


def run(tab, workspace, selected, state_path):
    def current_layout():
        layout = request("layout.export", tab_id=tab)["layout"]
        if layout["zoomed"]:
            raise ValueError("Exit fullscreen zoom before toggling Half Zoom")
        root = topology(layout["root"])
        if root["type"] != "split" or root["direction"] != "right":
            raise ValueError("Half Zoom requires a top-level left/right split")
        return layout, root

    layout, root = current_layout()
    side = side_for(root, selected)
    journal = load_state(state_path, root, selected)
    sides = journal["sides"]
    opposite = sides.get("second" if side == "first" else "first")
    if opposite is not None and opposite["phase"] != "active":
        raise ValueError("Finish toggling Half Zoom on the other side first")
    original_ratio = journal["original_ratio"]
    if root["ratio"] not in (0.5, original_ratio):
        raise ValueError(
            f"Tab split ratio changed outside Half Zoom. Saved layout: {state_path}"
        )

    state = sides.get(side)
    if state is None:
        enter_steps, restore_steps = plan_side_toggle(root[side], selected)
        parked = [step["park"] for step in enter_steps]
        state = dict(
            enter=enter_steps,
            exit=restore_steps,
            phase="enter",
            index=0,
            expanded_pane=selected,
            parked={pane_id: pane_info(pane_id)["terminal_id"] for pane_id in parked},
        )
        sides[side] = state
    else:
        for pane_id, terminal_id in state["parked"].items():
            pane = pane_info(pane_id)
            if pane["workspace_id"] != workspace or pane["terminal_id"] != terminal_id:
                raise ValueError(f"Parked pane {pane_id} changed")
        if state["phase"] == "active":
            state.update(phase="exit", index=0, return_focus=layout["focused_pane_id"])
    save(state_path, journal)

    phase = state["phase"]
    for index in range(state["index"], len(state[phase])):
        step = state[phase][index]
        _, root = current_layout()
        if root[side] == step["before"]:
            parking_anchor = None
            if "park" in step:
                visible = set(pane_ids(root))
                parking_anchor = next(
                    (
                        pane
                        for entry in sides.values()
                        for pane in entry["parked"]
                        if pane not in visible
                    ),
                    None,
                )
            apply_step(tab, workspace, step, parking_anchor)
            _, root = current_layout()
        if root[side] != step["after"]:
            raise ValueError(
                f"Side layout changed outside Half Zoom. Saved layout: {state_path}"
            )
        state["index"] = index + 1
        save(state_path, journal)

    _, root = current_layout()
    ratio = 0.5 if phase == "enter" or opposite is not None else original_ratio
    if root["ratio"] != ratio:
        request("layout.set_split_ratio", tab_id=tab, path=[], ratio=ratio)

    expanded_pane = state["expanded_pane"]
    if phase == "enter":
        request(
            "pane.report_metadata",
            pane_id=expanded_pane,
            source="half-zoom",
            title="HALF ZOOM",
        )
        state["phase"] = "active"
    else:
        if any("swap" in step for step in state["exit"]):
            request("pane.focus", pane_id=state["return_focus"])
        request(
            "pane.report_metadata",
            pane_id=expanded_pane,
            source="half-zoom",
            clear_title=True,
        )
        del sides[side]
    if sides:
        save(state_path, journal)
    else:
        state_path.unlink()


def state_path(tab_id):
    socket_path = Path(os.environ["HERDR_SOCKET_PATH"]).resolve()
    session = hashlib.sha256(os.fsencode(socket_path)).hexdigest()[:16]
    return (
        Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state")
        / "herdr/half-zoom"
        / session
        / f"{tab_id}.json"
    )


def main():
    os.umask(0o077)
    selected = os.environ.get("HERDR_ACTIVE_PANE_ID") or os.environ.get("HERDR_PANE_ID")
    if not selected or not os.environ.get("HERDR_SOCKET_PATH"):
        raise ValueError("Run this command inside Herdr")
    pane = pane_info(selected)
    tab = pane["tab_id"]
    path = state_path(tab)
    path.parent.mkdir(parents=True, exist_ok=True)
    with (path.parent / "lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        run(tab, pane["workspace_id"], selected, path)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError) as error:
        print(f"Half Zoom: {error}", file=sys.stderr)
        sys.exit(1)
