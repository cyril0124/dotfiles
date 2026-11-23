#!/usr/bin/env python3
import argparse
import fcntl
import getpass
from hashlib import sha256
import json
import os
from pathlib import Path
import pwd
import re
import select
import shlex
import shutil
import signal
import socket
import subprocess
import sys
import time
from urllib.parse import urlencode
from urllib.request import ProxyHandler, build_opener

HOST = socket.gethostname()
BOOT_ID = Path("/proc/sys/kernel/random/boot_id")
LISTENING = re.compile(r"HTTP server listening on http://127\.0\.0\.1:(\d+)/?")
HTTP = build_opener(ProxyHandler({}))
START_TIMEOUT = 20
STOP_TIMEOUT = 10
SESSION_ERRORS = (AttributeError, OSError, RuntimeError, ValueError, KeyError)
SLUG = re.compile(r"[a-zA-Z0-9][a-zA-Z0-9._-]*")
# Slugs avoid these names because every launcher directory holds files with them.
RESERVED_NAMES = {"open.sh", "status.sh", "close.sh", "config.yaml", "server.log", "user-data"}


def write_private(path, text):
    temporary = path.with_suffix(".tmp")
    temporary.write_text(text, encoding="utf-8")
    temporary.replace(path)


def create_launchers(directory):
    marker = directory / ".managed"
    if not marker.is_file():
        if any(path.name != ".lock" for path in directory.iterdir()):
            raise RuntimeError(f"launcher directory already exists: {directory}")
        marker.touch()

    script = shlex.quote(str(Path(__file__).resolve()))
    for action in ("open", "status", "close"):
        launcher = directory / f"{action}.sh"
        if launcher.exists() and os.access(launcher, os.X_OK):
            continue
        write_private(
            launcher,
            '#!/usr/bin/env bash\n'
            'set -euo pipefail\n'
            'launcher=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)\n'
            'project=$(cd -- "$launcher/../.." && pwd -P)\n'
            f'exec python3 {script} {action} "$project" "$@" --slug "${{launcher##*/}}"\n',
        )
        launcher.chmod(0o700)
    ignore = directory / ".gitignore"
    if not ignore.exists():
        write_private(ignore, "*\n")


def password_config(password: str) -> str:
    return f"auth: password\npassword: {json.dumps(password, ensure_ascii=False)}\ncert: false\n"


def process_start_time(pid: int) -> str:
    stat = Path(f"/proc/{pid}/stat").read_text()
    # The command name may contain spaces. Fields after it start at field 3.
    fields_after_command = stat.rsplit(")", 1)[1].split()
    return fields_after_command[22 - 3]


def session_handle(state, expected_processes=None):
    if not state.exists():
        return None
    record = json.loads(state.read_text())
    pid, recorded_start_time = record["pid"], record["start"]
    if expected_processes is not None and (pid, recorded_start_time) not in expected_processes:
        return None
    if record["host"] != HOST:
        raise RuntimeError(f"session was opened on {record['host']}; run the command there")
    if record["boot"] != BOOT_ID.read_text().strip():
        state.unlink()
        return None

    handle = None
    try:
        handle = os.pidfd_open(pid)
        if process_start_time(pid) == recorded_start_time and not exited(handle, 0):
            return handle
    except (FileNotFoundError, ProcessLookupError):
        pass
    except BaseException:
        if handle is not None:
            os.close(handle)
        raise
    if handle is not None:
        os.close(handle)
    state.unlink()
    return None


def exited(handle, seconds):
    poll = select.poll()
    poll.register(handle, select.POLLIN)
    return bool(poll.poll(int(seconds * 1000)))


def stop(handle):
    try:
        signal.pidfd_send_signal(handle, signal.SIGTERM)
    except ProcessLookupError:
        return
    if not exited(handle, STOP_TIMEOUT):
        raise RuntimeError(f"code-server did not exit within {STOP_TIMEOUT} seconds")


def stop_forced(handle):
    """Stop a session, escalating to SIGKILL when it ignores SIGTERM."""
    try:
        stop(handle)
    except RuntimeError:
        signal.pidfd_send_signal(handle, signal.SIGKILL)
        if not exited(handle, STOP_TIMEOUT):
            raise RuntimeError(f"code-server survived SIGKILL for {STOP_TIMEOUT} seconds")


def start(project, directory, state, port):
    binary = shutil.which("code-server")
    if binary is None:
        raise RuntimeError("code-server was not found on PATH")

    if not hasattr(os, "pidfd_open") or not hasattr(signal, "pidfd_send_signal"):
        raise RuntimeError("Python must support Linux PID file descriptors")
    os.close(os.pidfd_open(os.getpid()))

    environment = os.environ.copy()
    for key in ("PORT", "PASSWORD", "HASHED_PASSWORD", "VSCODE_IPC_HOOK_CLI", "CODE_SERVER_COOKIE_SUFFIX"):
        environment.pop(key, None)
    # Cookies are scoped by host and path, so ports cannot isolate sessions.
    cookie_suffix = sha256(os.fsencode(directory)).hexdigest()
    args = [
        binary,
        "--config", str(directory / "config.yaml"),
        "--bind-addr", f"127.0.0.1:{port}",
        "--user-data-dir", str(directory / "user-data"),
        "--cookie-suffix", cookie_suffix,
        "--disable-telemetry",
        "--disable-update-check",
        str(project),
    ]
    with (directory / "server.log").open("wb") as log:
        child = subprocess.Popen(
            args, cwd=project, env=environment, start_new_session=True,
            stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT,
        )
    handle = os.pidfd_open(child.pid)
    try:
        record = {
            "host": HOST,
            "boot": BOOT_ID.read_text().strip(),
            "pid": child.pid,
            "start": process_start_time(child.pid),
        }
        write_private(state, json.dumps(record) + "\n")
    except BaseException:
        try:
            stop(handle)
        finally:
            os.close(handle)
        raise
    return handle


def ready_port(handle, log, seconds):
    deadline = time.monotonic() + seconds
    while True:
        if exited(handle, 0):
            raise RuntimeError(f"code-server exited; see {log}")
        match = LISTENING.search(log.read_text(errors="replace"))
        if match:
            port = int(match[1])
            try:
                with HTTP.open(f"http://127.0.0.1:{port}/healthz", timeout=1) as response:
                    if response.status == 200 and not exited(handle, 0):
                        return port
            except OSError:
                pass
        if time.monotonic() >= deadline:
            raise RuntimeError(f"code-server health check failed; see {log}")
        time.sleep(0.1)


def print_running(project, directory, port):
    query = urlencode({"folder": str(project)})
    tunnel = shlex.join([
        "ssh", "-N", "-L", f"127.0.0.1:{port}:127.0.0.1:{port}", f"{getpass.getuser()}@{HOST}",
    ])
    print("STATUS=running")
    print(f"PORT={port}")
    print(f"BROWSER=http://127.0.0.1:{port}/?{query}")
    print(f"SSH={tunnel}")
    print(f"PASSWORD_FILE={directory / 'config.yaml'}")
    print(f"LAUNCHER_DIR={directory}")


def port_is_free(port):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
        probe.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            probe.bind(("127.0.0.1", port))
        except OSError:
            return False
        return True


def blocking_listeners(port):
    """This user's PIDs that block a loopback bind on port; error when another user holds it."""
    if port_is_free(port):
        return []
    lsof = shutil.which("lsof")
    if lsof is None:
        raise RuntimeError("releasing an occupied port requires lsof")
    result = subprocess.run(
        [lsof, "-w", "-nP", "-a", "-u", str(os.getuid()), "-iTCP:" + str(port), "-sTCP:LISTEN", "-Fpn"],
        capture_output=True, text=True,
    )
    # lsof exits 1 when it matches no file.
    if result.returncode not in (0, 1):
        raise RuntimeError(f"cannot identify listeners on port {port}: {result.stderr.strip()}")

    # Only loopback and wildcard listeners can block this IPv4 loopback bind.
    blocking_addresses = {f"*:{port}", f"0.0.0.0:{port}", f"127.0.0.1:{port}"}
    pids = set()
    pid = None
    for line in result.stdout.splitlines():
        if line.startswith("p"):
            pid = int(line[1:])
        elif line.startswith("n") and pid is not None and line[1:] in blocking_addresses:
            pids.add(pid)

    if not pids:
        raise RuntimeError(f"port {port} is held by a listener this user does not own; --force cannot release it")
    return sorted(pids)


def release_port(port):
    pids = blocking_listeners(port)
    if not pids:
        return
    for pid in pids:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    deadline = time.monotonic() + STOP_TIMEOUT
    while not port_is_free(port):
        if time.monotonic() >= deadline:
            raise RuntimeError(f"port {port} is still busy after SIGKILL to {pids}")
        time.sleep(0.1)


def manage(action, project, directory, requested_port, expected_processes, password, force=False):
    if action == "open":
        create_launchers(directory)
    elif not (directory / ".managed").is_file():
        raise RuntimeError(f"launcher directory is not managed by this skill: {directory}")

    state = directory / ".session.json"
    log = directory / "server.log"
    if force and requested_port:
        # Fail before stopping a session that could not be restarted on that port.
        blocking_listeners(requested_port)
    handle = session_handle(state, expected_processes)
    if handle is not None and force:
        try:
            stop_forced(handle)
            state.unlink(missing_ok=True)
        finally:
            os.close(handle)
        handle = None
    if handle is None and action != "open":
        print("STATUS=stopped")
        return

    started = handle is None
    config = directory / "config.yaml"
    if started:
        if force and requested_port:
            release_port(requested_port)
        session_password = password if password is not None else pwd.getpwuid(os.getuid()).pw_name
        write_private(config, password_config(session_password))
        handle = start(project, directory, state, requested_port)
    try:
        if password is not None and not started:
            configured_password = config.read_text(encoding="utf-8")
            if configured_password != password_config(password):
                raise RuntimeError(
                    "project is already running with a different password; run close.sh before reopening"
                )
        if action == "close":
            stop(handle)
            state.unlink()
            print("STATUS=stopped")
            return True
        try:
            port = ready_port(handle, log, START_TIMEOUT if started else 0)
        except (RuntimeError, OSError, KeyboardInterrupt):
            if started:
                stop(handle)
                state.unlink()
            raise
        if requested_port and port != requested_port:
            raise RuntimeError(f"project is already running on port {port}")
        print_running(project, directory, port)
    finally:
        os.close(handle)


def require_private_directory(directory: Path) -> None:
    info = directory.lstat()
    if directory.is_symlink() or not directory.is_dir() or info.st_uid != os.getuid() or info.st_mode & 0o077:
        raise RuntimeError(f"launcher directory must be private and owned by the current user: {directory}")


def manage_project(action, project, port=0, expected_processes=None, *, password=None, slug=None, force=False):
    project = project.resolve(strict=True)
    if not project.is_dir():
        raise RuntimeError(f"project is not a directory: {project}")
    default_slug = re.sub(r"[^a-zA-Z0-9._-]+", "-", project.name).lstrip("._-")[:80] or "project"
    if default_slug in RESERVED_NAMES:
        default_slug = f"project-{default_slug}"
    slug = slug if slug is not None else default_slug
    root = project / ".code-server"
    if action == "open":
        root.mkdir(exist_ok=True, mode=0o700)
    elif not root.exists():
        print("STATUS=stopped")
        return

    require_private_directory(root)
    lock = os.open(root / ".lock", os.O_CREAT | os.O_WRONLY | os.O_NOFOLLOW, 0o600)
    try:
        fcntl.flock(lock, fcntl.LOCK_EX)
        directory = root / slug
        if action == "open":
            directory.mkdir(exist_ok=True, mode=0o700)
        elif not directory.exists():
            print("STATUS=stopped")
            return
        require_private_directory(directory)
        return manage(action, project, directory, port, expected_processes, password, force)
    finally:
        os.close(lock)


def discover_sessions() -> dict[Path, set[tuple[int, str]]]:
    processes_by_launcher = {}
    uid = os.getuid()
    for process in Path("/proc").iterdir():
        if not process.name.isdecimal():
            continue
        try:
            if process.stat().st_uid != uid:
                continue
            args = (process / "cmdline").read_bytes().split(b"\0")
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            continue

        # Both the code-server wrapper and its child can carry the same config path.
        for option, value in zip(args, args[1:]):
            if option != b"--config":
                continue
            config = Path(os.fsdecode(value))
            launcher_directory = config.parent
            if (
                not config.is_absolute()
                or config.name != "config.yaml"
                or launcher_directory.parent.name != ".code-server"
                or not SLUG.fullmatch(launcher_directory.name)
            ):
                continue
            if not (launcher_directory / ".session.json").is_file():
                continue

            pid = int(process.name)
            try:
                start_time = process_start_time(pid)
            except (FileNotFoundError, ProcessLookupError, PermissionError):
                break
            processes_by_launcher.setdefault(launcher_directory, set()).add((pid, start_time))
            break
    return processes_by_launcher


def close_all() -> int:
    stopped = 0
    failed = 0
    for directory, processes in sorted(discover_sessions().items()):
        project, slug = directory.parent.parent, directory.name
        print(f"PROJECT={project}\nLAUNCHER_DIR={directory}", flush=True)
        try:
            if manage_project("close", project, expected_processes=processes, slug=slug):
                stopped += 1
        except SESSION_ERRORS as error:
            print(f"ERROR: {directory}: {error}", file=sys.stderr)
            failed += 1
    print(f"SESSIONS_STOPPED={stopped}")
    print(f"SESSIONS_FAILED={failed}")
    return int(failed > 0)


def main():
    parser = argparse.ArgumentParser(description="Manage code-server project sessions.")
    commands = parser.add_subparsers(dest="action", required=True)
    for action in ("open", "status", "close"):
        command = commands.add_parser(action)
        command.add_argument("project", type=Path)
        command.add_argument("--slug", help="launcher name (default: derived from the project directory name)")
        if action == "open":
            command.add_argument("--port", type=int, default=0, help="0 lets the kernel choose a port")
            command.add_argument("--password", help="override the account name as the password for a new session")
            command.add_argument(
                "--force", action="store_true",
                help="restart the session and clear an owned listener blocking --port",
            )
    commands.add_parser("close-all", help="stop all managed sessions on this host")
    args = parser.parse_args()
    port = getattr(args, "port", 0)
    if not 0 <= port <= 65535:
        parser.error("--port must be between 0 and 65535")

    password = getattr(args, "password", None)
    if password is not None:
        if not password or password != password.strip() or "\n" in password or "\r" in password:
            parser.error("--password requires a nonempty single line without leading or trailing whitespace")

    os.umask(0o077)
    if args.action == "close-all":
        return close_all()
    if args.slug is not None:
        if not SLUG.fullmatch(args.slug):
            parser.error("--slug must start with a letter or digit and contain only letters, digits, dots, underscores or hyphens")
        if args.slug in RESERVED_NAMES:
            parser.error(f"--slug {args.slug!r} is reserved for launcher file names")
    force = getattr(args, "force", False)
    manage_project(args.action, args.project, port, password=password, slug=args.slug, force=force)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except SESSION_ERRORS as error:
        sys.exit(f"ERROR: {error}")
