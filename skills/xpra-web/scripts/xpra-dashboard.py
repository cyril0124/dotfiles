"""Run one local Xpra window dashboard per user runtime directory."""

from concurrent.futures import ThreadPoolExecutor
from contextlib import contextmanager
import errno
import fcntl
from http.client import HTTPConnection, HTTPResponse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from functools import lru_cache
import json
import mimetypes
import os
from pathlib import Path
import re
import secrets
import shlex
import socket
import ssl
import stat
import subprocess
import sys
from threading import Lock, Thread
from time import monotonic, time
from urllib.parse import unquote, urlsplit

ASSETS = Path(__file__).with_name("dashboard")
SERVICE_VERSION = 8
UUID = re.compile(r"[a-fA-F0-9-]+")
DISPLAY = re.compile(r":[0-9]+")
WINDOW_PROPERTIES = re.compile(r"^windows\.(\d+)\.(title|pid|command|xid)=(.*)$", re.MULTILINE)
LISTENER = re.compile(r"^network\.sockets\.tcp\.listeners=.*?\('([^']*)', '?([0-9]+)'?\)", re.MULTILINE)
CLIENT_CONNECT = "          client.connect();"
CLIENT_ARGV = '"argv": [window.location.href]'


def runtime_dir():
    base = Path(os.environ.get("XDG_RUNTIME_DIR") or os.environ.get("TMPDIR") or "/tmp")
    directory = base / f"xpra-web-dashboard-{os.getuid()}"
    directory.mkdir(mode=0o700, exist_ok=True)
    metadata = directory.lstat()
    if metadata.st_uid != os.getuid() or not stat.S_ISDIR(metadata.st_mode) or metadata.st_mode & 0o077:
        raise RuntimeError(f"dashboard runtime directory must be private: {directory}")
    return directory


@contextmanager
def locked(directory):
    with (directory / "lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        yield


def read_json(path, default=None):
    try:
        return json.loads(path.read_text())
    except FileNotFoundError:
        return default


def write_json(path, value):
    pending = path.with_suffix(".new")
    pending.write_text(json.dumps(value))
    pending.replace(path)


def xpra(command, *args):
    return subprocess.check_output([command, *args], text=True, stderr=subprocess.DEVNULL,
                                   timeout=4, errors="replace")


def identity(command, display):
    return dict(line.split("=", 1) for line in xpra(command, "id", display).splitlines() if "=" in line)


def registered_session(record):
    command, display = record["command"], record["display"]
    if identity(command, display).get("uuid") != record["uuid"]:
        return None
    info = xpra(command, "info", display)
    listener = LISTENER.search(info)
    if not listener or listener[1] != record["host"] or int(listener[2]) != record["port"]:
        return None
    return info


def process_details(pid):
    if not pid.isascii() or not pid.isdecimal() or int(pid) <= 0:
        return None, None

    process = Path("/proc") / pid
    try:
        if process.stat().st_uid != os.getuid():
            return None, None
    except OSError:
        return None, None

    cwd = None
    command = None
    try:
        cwd = os.readlink(process / "cwd")
        raw_command = (process / "cmdline").read_bytes()
        if raw_command:
            argv = raw_command.removesuffix(b"\0").split(b"\0")
            command = shlex.join(os.fsdecode(arg) for arg in argv)
    except OSError:
        pass
    return cwd, command


def process_start(pid):
    try:
        return (Path("/proc") / str(pid) / "stat").read_text().rsplit(")", 1)[1].split()[19]
    except (OSError, IndexError):
        return None


@lru_cache(maxsize=1)
def boot_timestamp():
    for line in Path("/proc/stat").read_text().splitlines():
        if line.startswith("btime "):
            return int(line.split()[1])
    raise ValueError("missing boot time")


def process_started_at(pid):
    try:
        if (Path("/proc") / pid).stat().st_uid != os.getuid():
            return None
        ticks = process_start(pid)
        if ticks is not None:
            return boot_timestamp() + int(ticks) / os.sysconf("SC_CLK_TCK")
    except (OSError, ValueError):
        pass
    return None


def remember_launch(directory, session_file, pid, cwd, argv):
    _, key = Path(session_file).read_text().split()
    uuid = key.removeprefix("uuid=")
    if key == uuid or not UUID.fullmatch(uuid):
        raise ValueError("invalid launcher session identity")
    with locked(directory):
        path = directory / "launches.json"
        launches = read_json(path, {})
        launches.setdefault(uuid, {})[pid] = {"start": process_start(pid), "cwd": cwd, "argv": argv}
        write_json(path, launches)


def window_inventory(info):
    windows = {}
    for wid, key, value in WINDOW_PROPERTIES.findall(info):
        windows.setdefault(int(wid), {})[key] = value

    for wid, properties in windows.items():
        if "title" not in properties:
            continue
        pid = properties.get("pid", "")
        cwd, command = process_details(pid)
        yield {
            "id": wid,
            "pid": pid,
            "started_at": process_started_at(pid) if re.fullmatch(r"[1-9][0-9]*", pid) else None,
            "title": properties["title"],
            "cwd": cwd,
            "command": command or properties.get("command") or None,
        }


def inventory_entry(record):
    try:
        info = registered_session(record)
    except (OSError, subprocess.SubprocessError):
        return None
    if info is None:
        return None
    windows = list(window_inventory(info))
    return {"uuid": record["uuid"], "display": record["display"], "windows": windows}


def force_close_windows(record, target=None):
    command, display = record["command"], record["display"]
    info = registered_session(record)
    if info is None:
        return 0, 0

    properties = {(wid, key): value for wid, key, value in WINDOW_PROPERTIES.findall(info)}
    window_ids = sorted({wid for wid, key in properties if key == "title"}, key=int)
    if target is not None:
        window_ids = [wid for wid in window_ids if wid == target]
    authority = re.search(r"^env\.XAUTHORITY=(.+)$", info, re.MULTILINE)
    env = os.environ.copy()
    if authority:
        env["XAUTHORITY"] = authority[1]
    requested = failed = 0
    for wid in window_ids:
        xid = properties.get((wid, "xid"), "")
        if not re.fullmatch(r"0x[0-9a-fA-F]{1,8}", xid) or int(xid, 16) == 0:
            failed += 1
            continue
        try:
            if identity(command, display).get("uuid") != record["uuid"]:
                raise OSError("Xpra session changed")
            subprocess.run(["xkill", "-display", display, "-id", xid], env=env,
                           timeout=4, check=True, capture_output=True)
            requested += 1
        except (OSError, subprocess.SubprocessError):
            failed += 1
    return requested, failed


def import_launchers(directory, command, project, service):
    discovered = {}
    for state in sorted((Path(project) / ".xpra-web").glob("*/.session")):
        try:
            display, key = state.read_text().split()
            if not DISPLAY.fullmatch(display):
                continue
            identifiers = identity(command, display)
            expected = "uuid=" + identifiers.get("uuid", "")
            if key != expected and key != identifiers.get("session-name"):
                continue
            uuid = identifiers.get("uuid", "")
            if not UUID.fullmatch(uuid):
                continue
            info = xpra(command, "info", display)
            listener = LISTENER.search(info)
            if not listener:
                continue
            transport, cert = session_transport(info)
            discovered[uuid] = session_record(command, display, uuid, listener[1], int(listener[2]), transport, cert)
        except (OSError, ValueError, subprocess.SubprocessError):
            continue
    with locked(directory):
        if read_json(directory / "service.json") != service:
            return
        records = directory / "sessions.json"
        write_json(records, discovered | read_json(records, {}))


def session_transport(info):
    argv = next((line for line in info.splitlines() if line.startswith(("argv=", "server.argv="))), "")
    cert = re.search(r"['\"]--ssl-cert=([^'\"]+)['\"]", argv)
    if "--ssl-cert" in argv:
        return "wss", cert[1] if cert else ""
    return "ws", ""


def session_record(command, display, uuid, host, port, transport, cert):
    return dict(command=command, display=display, uuid=uuid, host=host, port=int(port),
                transport=transport, cert=cert)


def local_request(state, method, route):
    connection = HTTPConnection("127.0.0.1", state["port"], timeout=0.4)
    try:
        connection.request(method, f"/{state['control']}/{route}")
        response = connection.getresponse()
        return response.status == 204
    except OSError:
        return False
    finally:
        connection.close()


def dashboard_listener(ports):
    for port in ports:
        listener = socket.socket()
        try:
            listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            listener.bind(("127.0.0.1", int(port)))
            listener.listen()
            return listener
        except OSError as error:
            listener.close()
            if port == "0" or error.errno not in (errno.EADDRINUSE, errno.EACCES):
                raise
    raise RuntimeError("no Dashboard port is available")


def register(directory, record, project, session, ports):
    with locked(directory):
        records_path = directory / "sessions.json"
        records = read_json(records_path, {})
        if session == "reused":
            recorded = records.get(record["uuid"], {})
            record["cert"] = recorded.get("cert", "")
        records = {uuid: item for uuid, item in records.items() if item["display"] != record["display"]}
        records[record["uuid"]] = record
        write_json(records_path, records)
        state_path = directory / "service.json"
        state = read_json(state_path)
        running = state and local_request(state, "GET", "health")
        if running and state.get("version") != SERVICE_VERSION:
            if not local_request(state, "POST", "stop"):
                raise RuntimeError("could not replace the old Dashboard listener")
            if "token" not in state:
                ports = [str(state["port"]), *ports]
            running = False
        if not running:
            with dashboard_listener(ports) as listener:
                state = dict(port=listener.getsockname()[1], control=secrets.token_urlsafe(24),
                             version=SERVICE_VERSION)
                write_json(state_path, state)
                with (directory / "server.log").open("ab") as log:
                    subprocess.Popen([sys.executable, __file__, "serve", str(listener.fileno()),
                                      record["command"], project], stdin=subprocess.DEVNULL,
                                     stdout=log, stderr=log, pass_fds=(listener.fileno(),), start_new_session=True)
    print(f"DASHBOARD=http://127.0.0.1:{state['port']}")
    print(f"DASHBOARD_PORT={state['port']}")


def stop(directory):
    with locked(directory):
        state_path = directory / "service.json"
        state = read_json(state_path)
        if state:
            if not local_request(state, "POST", "stop") and local_request(state, "GET", "health"):
                raise RuntimeError("could not stop the dashboard")
            state_path.unlink()
        (directory / "sessions.json").unlink(missing_ok=True)
        (directory / "launches.json").unlink(missing_ok=True)


class Dashboard(ThreadingHTTPServer):
    def __init__(self, listener, directory, state):
        super().__init__(listener.getsockname(), DashboardHandler, bind_and_activate=False)
        self.socket.close()
        self.socket = listener
        self.server_address = listener.getsockname()
        self.directory = directory
        self.state = state
        self.html_root = None
        self.inventory_lock = Lock()
        self.inventory_time = float("-inf")
        self.windows = []
        self.closed_windows = {}
        self.stopping = False

    def records(self):
        return read_json(self.directory / "sessions.json", {})

    def inventory(self, *, refresh=False):
        with self.inventory_lock:
            if refresh or monotonic() - self.inventory_time > 1.5:
                with ThreadPoolExecutor(max_workers=6) as workers:
                    self.windows = [entry for entry in workers.map(inventory_entry, self.records().values()) if entry]
                self.inventory_time = monotonic()
            launches = read_json(self.directory / "launches.json", {})
            groups = {}
            for entry in self.windows:
                uuid = entry["uuid"]
                windows = []
                for window in entry["windows"]:
                    public = {key: value for key, value in window.items() if key != "pid"}
                    public["can_reopen"] = bool(self.launch_for(launches.get(uuid, {}), window["pid"]))
                    windows.append(public)
                groups[uuid] = {**entry, "windows": windows}
            for (uuid, _), (window, _) in self.closed_windows.items():
                if uuid in groups:
                    groups[uuid]["windows"].append(window)
            return [group for group in groups.values() if group["windows"]]

    @staticmethod
    def launch_for(launches, pid):
        # A window can belong to a descendant of the process started by Xpra.
        while re.fullmatch(r"[0-9]+", pid) and int(pid) > 1:
            recipe = launches.get(pid)
            if recipe and recipe["start"] and recipe["start"] == process_start(pid):
                return recipe
            try:
                stat_fields = (Path("/proc") / pid / "stat").read_text().rsplit(")", 1)[1].split()
                pid = stat_fields[1]
            except (OSError, IndexError):
                break
        return None

    def window_action(self, action, uuid, window_id):
        with self.inventory_lock:
            if self.stopping:
                raise ValueError("The Dashboard is stopping.")
            record = self.records().get(uuid)
            if not record or not (info := registered_session(record)):
                raise ValueError("The Xpra session is no longer available.")
            key = (uuid, window_id)
            saved = self.closed_windows.get(key)
            if saved:
                if action != "reopen":
                    raise ValueError("The window is already closed.")
                window, recipe = saved
            else:
                window = next((item for item in window_inventory(info) if str(item["id"]) == window_id), None)
                if not window:
                    raise ValueError("The window is no longer available.")
                launches = read_json(self.directory / "launches.json", {}).get(uuid, {})
                recipe = self.launch_for(launches, window.pop("pid"))
                if action == "reopen" and not recipe:
                    raise ValueError("The original launch command is unavailable.")
                closed, failed = force_close_windows(record, window_id)
                if not closed or failed:
                    raise ValueError("Could not close the window.")
                if recipe:
                    window.update(closed=True, can_reopen=True, closed_at=time())
                    self.closed_windows[key] = window, recipe
                self.inventory_time = float("-inf")
            if action == "reopen":
                self.relaunch(record, recipe)
                del self.closed_windows[key]

    def relaunch(self, record, recipe):
        command, display = record["command"], record["display"]
        if identity(command, display).get("uuid") != record["uuid"]:
            raise ValueError("The Xpra session is no longer available.")
        runner = str(Path(__file__).with_name("xpra-run-in.sh").resolve())
        result = subprocess.check_output(
            [command, "control", display, "start-child", "--", runner, recipe["cwd"], *recipe["argv"]],
            text=True, stderr=subprocess.STDOUT, timeout=4, errors="replace",
        )
        pid = re.search(r"\bpid=(\d+)", result)
        if not pid:
            raise ValueError("Xpra did not report a launched process.")
        with locked(self.directory):
            path = self.directory / "launches.json"
            launches = read_json(path, {})
            launches.setdefault(record["uuid"], {})[pid[1]] = {**recipe, "start": process_start(pid[1])}
            write_json(path, launches)
        self.inventory_time = float("-inf")

    def close_windows(self, *, stop_dashboard=False):
        with self.inventory_lock, ThreadPoolExecutor(max_workers=6) as workers:
            if self.stopping:
                raise ValueError("The Dashboard is stopping.")
            futures = {workers.submit(force_close_windows, record): record for record in self.records().values()}
            requested = failed = 0
            for future, record in futures.items():
                try:
                    session_requested, session_failed = future.result()
                    requested += session_requested
                    failed += session_failed
                except subprocess.CalledProcessError:
                    # Ignore a stale registration only when Xpra confirms the display is absent.
                    try:
                        listing = xpra(record["command"], "list")
                    except (OSError, subprocess.SubprocessError):
                        failed += 1
                    else:
                        display = re.escape(record["display"])
                        if re.search(rf"\bsession at {display}(?![0-9])", listing):
                            failed += 1
                except (OSError, subprocess.TimeoutExpired):
                    failed += 1
            self.inventory_time = float("-inf")
            self.stopping = stop_dashboard and failed == 0
            return {"requested": requested, "failed": failed}


class DashboardHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *_):
        # The local health and shutdown routes contain the control token.
        pass

    def setup(self):
        self.request.settimeout(10)
        super().setup()

    def send_content(self, status, content=b"", content_type="text/plain; charset=utf-8"):
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(content)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("X-Frame-Options", "DENY")
        self.send_header("Cross-Origin-Resource-Policy", "same-origin")
        self.end_headers()
        if content:
            try:
                self.wfile.write(content)
            except (BrokenPipeError, ConnectionResetError):
                self.close_connection = True

    def request_route(self):
        host = self.headers.get("Host", "")
        if host not in {f"127.0.0.1:{self.server.state['port']}", f"localhost:{self.server.state['port']}"}:
            return None
        if self.headers.get("Sec-Fetch-Site") in {"cross-site", "same-site"}:
            return None
        if self.headers.get("Origin", f"http://{host}") != f"http://{host}":
            return None
        return unquote(urlsplit(self.path).path).lstrip("/")

    def do_GET(self):
        route = self.request_route()
        if route == f"{self.server.state['control']}/health":
            self.send_content(204)
            return
        if route == "windows.json":
            if not self.owned_browser_connection():
                self.send_content(403)
                return
            refresh = urlsplit(self.path).query == "refresh=1"
            inventory = self.server.inventory(refresh=refresh)
            self.send_content(200, json.dumps(inventory).encode(), "application/json")
        elif route in ("", "dashboard.js"):
            self.send_asset(ASSETS / (route or "index.html"))
        elif route is not None and route.startswith("view/"):
            if not self.owned_browser_connection():
                self.send_content(403)
                return
            self.serve_view(route)
        else:
            self.send_content(404)

    def do_POST(self):
        route = self.request_route()
        action = re.fullmatch(r"window/(close|reopen)/([a-fA-F0-9-]+)/([0-9]{1,10})", route or "")
        if action:
            if not self.can_change_windows():
                self.send_content(403, b"Dashboard actions require a connection from the session owner.")
                return
            try:
                self.server.window_action(*action.groups())
            except ValueError as error:
                self.send_content(409, str(error).encode())
            except (OSError, subprocess.SubprocessError):
                self.send_content(502, b"Xpra could not complete the window action.")
            else:
                self.send_content(204)
            return
        if route in {"close-windows", "close-windows-and-stop"}:
            if not self.can_change_windows():
                self.send_content(403)
                return
            stop_dashboard = route == "close-windows-and-stop"
            try:
                result = self.server.close_windows(stop_dashboard=stop_dashboard)
            except ValueError as error:
                self.send_content(409, str(error).encode())
                return
            try:
                self.send_content(200, json.dumps(result).encode(), "application/json")
            finally:
                if stop_dashboard and not result["failed"]:
                    self.shutdown_dashboard()
            return
        if route != f"{self.server.state['control']}/stop":
            self.send_content(404)
            return
        self.send_content(204)
        self.shutdown_dashboard()

    def shutdown_dashboard(self):
        self.server.socket.close()
        Thread(target=self.server.shutdown, daemon=True).start()

    def can_change_windows(self):
        return self.headers.get("Origin") == f"http://{self.headers['Host']}" and self.owned_browser_connection()

    def owned_browser_connection(self):
        # A loopback listener is reachable by other users on the same host.
        host, port = self.client_address
        server_host, server_port = self.connection.getsockname()
        try:
            peers = subprocess.check_output(
                ["ss", "-Htnpe", "state", "established", "src", f"{host}:{port}",
                 "and", "dst", f"{server_host}:{server_port}"],
                text=True, timeout=2, stderr=subprocess.DEVNULL,
            )
        except (OSError, subprocess.SubprocessError):
            return False
        uid = re.search(r"\buid:(\d+)\b", peers)
        return bool(peers.strip()) and int(uid[1] if uid else 0) == os.getuid()

    def send_asset(self, path, transform=None):
        try:
            content = path.read_bytes()
            if transform:
                content = transform(content.decode()).encode()
        except (OSError, UnicodeError):
            self.send_content(404)
            return
        except ValueError as exc:
            self.send_content(503, str(exc).encode())
            return
        self.send_content(200, content, mimetypes.guess_type(path.name)[0] or "application/octet-stream")

    def serve_view(self, route):
        _, separator, viewer_path = route.partition("/")
        uuid, _, window_path = viewer_path.partition("/")
        window_id, _, asset = window_path.partition("/")
        record = self.server.records().get(uuid)
        if not separator or not record or not re.fullmatch(r"[0-9]{1,10}", window_id):
            self.send_content(404)
            return
        if asset == "socket":
            self.upgrade(record, window_id)
            return
        html_root = self.server.html_root
        if html_root is None:
            self.send_content(503, b"The Xpra HTML5 client is unavailable.")
            return
        path = (html_root / (asset or "index.html")).resolve()
        if not path.is_relative_to(html_root) or not path.is_file():
            self.send_content(404)
        elif path == html_root / "index.html":
            self.send_asset(path, lambda page: window_client(page, window_id))
        elif path == html_root / "js/Client.js":
            self.send_asset(path, checked_client)
        else:
            self.send_asset(path)

    def upgrade(self, record, window_id):
        if (self.headers.get("Upgrade", "").lower() != "websocket"
                or self.headers.get("Origin") != f"http://{self.headers['Host']}"):
            self.send_content(403)
            return
        key = self.headers.get("Sec-WebSocket-Key", "")
        if not re.fullmatch(r"[A-Za-z0-9+/]{22}==", key):
            self.send_content(400)
            return
        try:
            info = registered_session(record)
            window_exists = info and any(
                wid == window_id and key == "title" for wid, key, _ in WINDOW_PROPERTIES.findall(info)
            )
            if not window_exists:
                self.send_content(410, b"This Xpra window has closed.")
                return
            _, cert = session_transport(info)
            if cert and Path(cert).is_absolute():
                record = record | {"cert": cert}
            with upstream_socket(record) as upstream:
                self.relay(upstream, record, key)
        except (OSError, ValueError, subprocess.SubprocessError) as error:
            if not getattr(self, "upgraded", False):
                print(f"Xpra relay failed for {record['display']}: {error}", file=sys.stderr)
                self.send_content(502, b"Could not connect to the Xpra session.")

    def relay(self, upstream, record, key):
        address = f"{endpoint_host(record)}:{record['port']}"
        upstream.sendall((f"GET / HTTP/1.1\r\nHost: {address}\r\nOrigin: http://{address}\r\n"
                          "Connection: Upgrade\r\nUpgrade: websocket\r\nSec-WebSocket-Version: 13\r\n"
                          f"Sec-WebSocket-Key: {key}\r\nSec-WebSocket-Protocol: binary\r\n\r\n").encode())
        response = HTTPResponse(upstream)
        response.begin()
        if response.status != 101:
            self.send_content(502, b"Xpra declined the WebSocket connection.")
            return
        verify_upstream(record, upstream)
        self.close_connection = True
        self.upgraded = True
        self.send_response(101)
        for header in ("Upgrade", "Connection", "Sec-WebSocket-Accept", "Sec-WebSocket-Protocol"):
            if response.headers.get(header):
                self.send_header(header, response.headers[header])
        self.end_headers()
        self.connection.settimeout(None)
        upstream.settimeout(None)
        Thread(target=copy_stream, args=(self.rfile, upstream, self.connection), daemon=True).start()
        copy_stream(response.fp, self.connection, upstream)
        response.close()


def verify_upstream(record, upstream):
    expected = identity(record["command"], record["display"])
    pid = expected.get("pid", "")
    if expected.get("uuid") != record["uuid"] or not pid.isdecimal():
        raise OSError("Xpra session changed")
    local_port = upstream.getsockname()[1]
    peers = subprocess.check_output(
        ["ss", "-Htnpe", "state", "established", "sport", "=", f":{record['port']}",
         "and", "dport", "=", f":{local_port}"], text=True, timeout=2,
        stderr=subprocess.DEVNULL,
    )
    if re.search(rf"\bpid={pid},", peers):
        return
    # Hardened Xpra processes can hide their PID from ss. The kernel still
    # exposes the UID of the accepted socket in extended TCP diagnostics.
    if "pid=" not in peers and re.search(rf"\buid:{os.getuid()}\b", peers):
        return
    raise OSError(f"Xpra TCP peer could not be verified for server PID {pid}")


def endpoint_host(record):
    return "127.0.0.1" if record["host"] in ("0.0.0.0", "::", "*") else record["host"]


@contextmanager
def upstream_socket(record):
    host = endpoint_host(record)
    with socket.create_connection((host, record["port"]), timeout=4) as connection:
        if record["transport"] == "ws":
            yield connection
            return
        cert = record["cert"]
        if cert:
            # Authenticate the exact certificate supplied for this local Xpra process.
            pem = Path(cert).read_text().split("-----END CERTIFICATE-----", 1)[0]
            fingerprint = ssl.PEM_cert_to_DER_cert(pem[pem.index("-----BEGIN CERTIFICATE-----"):] + "-----END CERTIFICATE-----")
            context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
            context.check_hostname = False
            context.verify_mode = ssl.CERT_NONE
        else:
            context = ssl.create_default_context()
        with context.wrap_socket(connection, server_hostname=host) as tls:
            if cert and not secrets.compare_digest(tls.getpeercert(binary_form=True), fingerprint):
                raise ssl.SSLError("Xpra certificate changed")
            yield tls


def copy_stream(source, destination, other):
    try:
        while data := source.read1(65536):
            destination.sendall(data)
    except (OSError, ValueError):
        pass
    finally:
        for connection in (destination, other):
            try:
                connection.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass


def checked_client(script):
    if script.count(CLIENT_ARGV) != 1:
        raise ValueError("This Xpra HTML5 release has no compatible client script.")
    return script.replace(CLIENT_ARGV, '"argv": []')


def window_client(page, window_id):
    if page.count(CLIENT_CONNECT) != 1:
        raise ValueError("This Xpra HTML5 release has no compatible window entry point.")
    focus = ("          client.host = window.location.hostname;\n"
             "          client.port = window.location.port;\n"
             "          client.ssl = window.location.protocol === 'https:';\n"
             "          client.sharing = true;\n"
             "          client.path = window.location.pathname + 'socket';\n"
             "          client.remote_logging = false;\n"
             "          client.webtransport = false;\n"
             "          document.addEventListener('connection-established', () => {\n"
             f"            const win = client.id_to_window[{int(window_id)}];\n"
             "            if (win) {\n"
             "              client.set_focus(win);\n"
             "              document.title = win.title;\n"
             "            }\n"
             "          }, {once: true});\n")
    return page.replace(CLIENT_CONNECT, focus + CLIENT_CONNECT)


def initialize(server, command, project):
    try:
        config = xpra(command, "showconfig")
        html = re.search(r"^html +\(used\) += '([^']+)'", config, re.MULTILINE)
        if html:
            configured = Path(html[1])
            if configured.is_absolute():
                server.html_root = configured.resolve()
            elif html[1] == "auto":
                default_roots = (Path("/usr/share/xpra/www"), Path("/usr/local/share/xpra/www"))
                server.html_root = next((root.resolve() for root in default_roots if (root / "index.html").is_file()), None)
    except (OSError, subprocess.SubprocessError):
        pass
    import_launchers(server.directory, command, project, server.state)


def main():
    action, *args = sys.argv[1:]
    os.umask(0o077)
    directory = runtime_dir()
    if action == "register":
        command, display, uuid, host, port, transport, cert, project, session, *ports = args
        register(directory, session_record(command, display, uuid, host, port, transport, cert), project, session, ports)
    elif action == "remember":
        session_file, pid, cwd, *argv = args
        remember_launch(directory, session_file, pid, cwd, argv)
    elif action == "stop":
        stop(directory)
    elif action == "serve":
        fd, command, project = args
        state = read_json(directory / "service.json")
        listener = socket.socket(fileno=int(fd))
        with Dashboard(listener, directory, state) as server:
            Thread(target=initialize, args=(server, command, project), daemon=True).start()
            server.serve_forever(poll_interval=0.1)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, RuntimeError) as error:
        sys.exit(f"Xpra Dashboard: {error}")
