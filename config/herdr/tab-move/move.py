import json
import os
import socket
import sys


def call(method, **params):
    request = {"id": "local.tab-move", "method": method, "params": params}
    with socket.socket(socket.AF_UNIX) as sock:
        sock.settimeout(5)
        sock.connect(os.environ["HERDR_SOCKET_PATH"])
        sock.sendall((json.dumps(request) + "\n").encode())
        with sock.makefile("rb") as reader:
            response = json.loads(reader.readline())
    if error := response.get("error"):
        raise RuntimeError(f"{method}: {error['message']}")
    return response["result"]


def move(direction):
    workspace_id = os.environ["HERDR_WORKSPACE_ID"]
    tab_id = os.environ["HERDR_TAB_ID"]
    tabs = call("tab.list", workspace_id=workspace_id)["tabs"]
    current = [tab["tab_id"] for tab in tabs].index(tab_id)
    last = len(tabs) - 1
    destinations = {
        "left": max(0, current - 1),
        "right": min(last, current + 1),
        "head": 0,
        "tail": last,
    }
    destination = destinations[direction]
    if destination != current:
        # Herdr interprets the insertion index before removing the tab.
        insert_index = destination + int(destination > current)
        call("tab.move", tab_id=tab_id, insert_index=insert_index)


if __name__ == "__main__":
    try:
        move(sys.argv[1])
    except (KeyError, OSError, ValueError, RuntimeError) as error:
        sys.exit(f"Move tab failed: {error}")
