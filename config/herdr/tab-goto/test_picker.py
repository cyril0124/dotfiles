"""Exercise picker keyboard input through a real pseudo-terminal.

Set TAB_GOTO_RS_BIN to also test a compiled Rust picker.
"""

import fcntl
import json
import os
from pathlib import Path
import pty
import select
import struct
import subprocess
import sys
import tempfile
import termios
import time
import unittest


class PickerKeysTests(unittest.TestCase):
    def check_keys(self, keys, expected_tab):
        picker_dir = Path(__file__).resolve().parent
        commands = [[sys.executable, "-S", "-m", "picker"]]
        if binary := os.environ.get("TAB_GOTO_RS_BIN"):
            commands.append([str(Path(binary).resolve()), "picker"])

        for command in commands:
            with self.subTest(command=command), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                tabs = [
                    {"tab_id": f"t{i}", "workspace_id": f"w{i // 2}",
                     "label": f"gG tab {i}", "agent_status": "working",
                     "focused": i == 1}
                    for i in range(4)
                ]
                fixture = root / "tabs.json"
                fixture.write_text(json.dumps({"tabs": tabs}))
                stub = root / "herdr"
                stub.write_text(
                    f"#!{sys.executable}\n"
                    "import pathlib, sys\n"
                    f"fixture = pathlib.Path({str(fixture)!r})\n"
                    "if sys.argv[1:3] == ['tab', 'list']:\n"
                    "    print(fixture.read_text())\n"
                    "elif sys.argv[1:3] == ['tab', 'focus']:\n"
                    "    fixture.with_name('focused').write_text(sys.argv[3])\n"
                    "else:\n"
                    "    print('{}')\n"
                )
                stub.chmod(0o700)
                master, slave = pty.openpty()
                fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 8, 100, 0, 0))
                env = dict(os.environ, TERM="xterm-256color", ESCDELAY="25", HERDR_BIN_PATH=str(stub),
                           HERDR_PLUGIN_STATE_DIR=directory)
                process = subprocess.Popen(
                    command, cwd=picker_dir, stdin=slave, stdout=slave, stderr=slave, env=env,
                )
                os.close(slave)
                try:
                    self.wait_for(master, b"3/6")
                    # Separate Escape from the next key so it is not decoded as Alt.
                    # Drain incremental curses output instead of assuming full redraws.
                    for key in keys:
                        os.write(master, bytes([key]))
                        deadline = time.monotonic() + 3
                        while select.select([master], [], [], 0.1)[0]:
                            os.read(master, 65536)
                            if time.monotonic() >= deadline:
                                self.fail("Picker did not finish drawing")
                    os.write(master, b"\r")
                    self.assertEqual(process.wait(timeout=3), 0)
                    self.assertEqual((root / "focused").read_text(), expected_tab)
                finally:
                    if process.poll() is None:
                        process.kill()
                        process.wait(timeout=3)
                    os.close(master)

    def wait_for(self, master, expected):
        output = b""
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            ready, _, _ = select.select([master], [], [], max(0, deadline - time.monotonic()))
            if not ready:
                break
            try:
                output += os.read(master, 65536)
            except OSError:
                break
            if expected in output:
                return
        self.fail(f"Missing {expected!r} in terminal output: {output!r}")

    def test_last_and_scrolling(self):
        self.check_keys(b"G", "t3")

    def test_first(self):
        self.check_keys(b"Gggj", "t0")

    def test_single_g_does_not_move(self):
        self.check_keys(b"g", "t1")

    def test_interrupted_prefix(self):
        self.check_keys(b"gkg", "t0")

    def test_search_treats_g_as_text_and_resets_prefix(self):
        self.check_keys(b"g/gG\x1bg", "t1")

    def test_filtered_tree(self):
        self.check_keys(b"/tab 2\x1bggG", "t2")

    def test_folded_tree(self):
        self.check_keys(b"hGgghjj", "t2")

    def test_no_matches(self):
        self.check_keys(b"/zzz\x1bggG\x1bG", "t3")


if __name__ == "__main__":
    unittest.main()
