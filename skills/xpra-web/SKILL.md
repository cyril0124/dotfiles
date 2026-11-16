---
name: xpra-web
description: Use when asked to open or view a GUI program on a remote, headless, or shared Linux host, in a browser or with an xpra client. Invoked directly as `xpra-web <ensure|run|list|doctor|close|close-all|stop>`.
disable-model-invocation: true
---

# Xpra Web

Serve X11 GUI programs from this machine so a browser or `xpra attach` can show them.

```
caller shell ──> xpra server (daemon, DISPLAY=:N, binds 127.0.0.1:PORT)
                   ├── children: xclock, myapp     one session, many programs
                   ├── http://127.0.0.1:PORT/     HTML5 locally or through SSH
                   ├── https://HOST:PORT/         HTML5 with WSS
                   └── tcp/wss://HOST:PORT        xpra attach / info
```

## Invocation

Run `bash scripts/xpra-web.sh <subcommand> ...` from this skill's directory. The user's subcommand and options pass through unchanged.

| User request | Command |
| --- | --- |
| `xpra-web`, or open a program in a browser | `ensure`, or `run -- X` when naming a program |
| add X to session :10 | `run --display :10 -- X` |
| `ls`, `list` | `list` |
| `doctor` | `doctor` |
| `close xclock` | `close xclock` |
| `close-all` | `close-all` |
| `stop :10` | `stop :10` |
| `help`, `--help` | `help`, then show the output |

Run exactly the requested scope. Do not widen `close` into `close-all`, or another command into `stop`. Ask only when a request without a subcommand is not covered above.

## Start and reuse

```bash
bash scripts/xpra-web.sh ensure
bash scripts/xpra-web.sh ensure --host 0.0.0.0 --ssl-cert /path/cert.pem --ssl-key /path/key.pem
bash scripts/xpra-web.sh run -- xclock
bash scripts/xpra-web.sh run --display :10 -- myapp
bash scripts/xpra-web.sh list
bash scripts/xpra-web.sh doctor
```

Options: `--host HOST` (default `127.0.0.1`), `--port PORT` (default `0`, kernel picks), `--display :N`, `--password PW`, `--password-file FILE`, `--no-password`, `--ssl-cert FILE`, `--ssl-key FILE`, `--allow-insecure`. The 3 password modes are mutually exclusive.

- `ensure` and `run` create a fresh session by default, taking a free display from `:10` to `:99` and a free port. Plain `run --port 0` also creates one.
- Join a session only when the user names it with `--display :N` or `--port N`. Reuse must match host, requested non-zero port, auth mode and WS/WSS transport. A display mismatch fails; a port mismatch may create a session only when that port is available.
- A non-zero port held by another process fails before startup. An existing session is never restarted or reinterpreted.
- New sessions daemonize in about 3 seconds. A bad host or occupied port is rejected before `xpra start` when possible.

`ensure` reports:

```
SESSION=created|reused
DISPLAY=:10
BIND=127.0.0.1:35971
PORT=35971
TRANSPORT=ws|wss
BROWSER=http://127.0.0.1:35971/
ATTACH=xpra attach --password-file=/run/user/<uid>/xpra-web-<user>/10/password tcp://<host>:35971
LOCAL=http://127.0.0.1:35971/
SSH=ssh -L 35971:127.0.0.1:35971 <user>@<host>
AUTH=file|none
PASSWORD=<value>            (AUTH=file, on a session this run created)
PASSWORD_FILE=<path>        (AUTH=file only)
WEB=yes|no|unknown
```

`run` prints this block on stderr, and `DISPLAY`, `CWD` and `APP_PID` on stdout. WSS sessions use `https` for browser URLs and `wss` for `ATTACH`.

## Access and passwords

- Each new display gets the user name as its password in `${XDG_RUNTIME_DIR:-/tmp}/xpra-web-<user>/<N>/password`, mode 0600 inside mode 0700 directories. Permission or write failures abort startup. A user name is guessable, so it stops a stray connection, not a deliberate one.
- Prefer `--password-file FILE`; it copies the secret exactly and does not print it. `--password PW` remains available, but command arguments can leak through history and process listings. A new password on a live session rewrites only that session's file atomically. A missing file is regenerated with the user name. Older sessions can keep their original shared file.
- `--no-password` selects `AUTH=none` and omits password fields. Keep it on loopback. It never downgrades an existing password-protected session.
- The default listener is loopback; use the printed `SSH` command and `LOCAL` URL remotely. Direct non-loopback access requires `--ssl-cert` and `--ssl-key` for HTTPS/WSS. Plain WS/TCP, or no authentication on a non-loopback listener, requires explicit `--allow-insecure`; report that exposure.
- `auth=file` uses challenge-response and does not encrypt the stream. The HTML5 client may refuse remote plaintext passwords. Never put passwords or AES keys in URLs.
- For a self-signed development certificate, `doctor` accepts `XPRA_WEB_SSL_SERVER_VERIFY_MODE=none` and `XPRA_WEB_SSL_CHECK_HOSTNAME=no`. Defaults are `required` and `yes`; production clients should trust the certificate instead.

`WEB=no` means no HTTP 200 was obtained; `WEB=unknown` means the probe could not run, for example without `curl`. Neither proves the HTML5 root is missing. Leave `--html` unset so the configured path applies.

## Run and inspect

`run` uses `xpra control start-child` and returns immediately. `scripts/xpra-run-in.sh` preserves the caller's working directory and execs the program, keeping its PID visible to `close`.

- Arguments, including spaces, quotes and empty strings, survive unchanged.
- Environment comes from the xpra server, not the calling shell. Use `run -- env LD_LIBRARY_PATH=/opt/tool/lib myapp` when needed. Restart a session to replace its environment.
- A new program gets its own session unless the user explicitly names an existing one. The server daemon and its children outlive the caller shell.

`list` shows display, TCP listener, windows, `name(pid)` children and their actual working directories from procfs. Probes are capped at `XPRA_WEB_PROBE_SECONDS` (default 5s); an unresponsive session reports `tcp=unresponsive` instead of hanging.

## Close and stop

| Request | Command | Effect |
| --- | --- | --- |
| close a program | `close myapp` | SIGTERM matching children; session stays |
| close all programs in one session | `close --all` | session and port stay |
| force stubborn programs | `close --all --force` | SIGKILL survivors |
| stop one session | `stop :N` | stop the server and its children |
| stop every session | `stop --all` | destructive, all live sessions |
| close everything everywhere | `close-all [--force]` | close all children, then stop all sessions |

Before closing, run `list` and identify the requested programs by name and working directory. `close` is case-insensitive substring matching against children of one session only; with multiple sessions it requires `--display`. `stop` requires `:N` or `--all` and prints the affected inventory first. A broad close destroys unsaved GUI state.

Stop operations use `XPRA_WEB_STOP_SECONDS` (default 10s), verify that each display disappears, and remove its per-display password file. Global operations print actual `SESSIONS_STOPPED` and `SESSIONS_FAILED`; any failure returns non-zero. An inventory query failure reports `programs=unknown`.

## Verify and report

Report `BROWSER`, `ATTACH`, `SSH`, `LOCAL`, the port, and a printed password when present. Report a session as usable only after `doctor` returns `DOCTOR=ok`.

`doctor` checks Xvfb, the HTML5 root, Xpra and HTML5 versions, the declared minimum protocol, HTTP(S), and an authenticated `xpra id` handshake over WS/WSS. It fails when:

- Xvfb or the HTML5 root is missing, or the client requires a newer protocol
- no sessions exist, the session list fails, or a control channel stays silent
- the active handshake fails
- HTTP(S) fails or cannot be probed

CPU and historical `connection timed out` entries are informational only. The doctor checks server-side readiness without launching a browser. A client must attach before `xpra screenshot` can capture windows.

## Missing dependencies and troubleshooting

If `xpra` is missing, the script exits 3. Ask before installing, show the command and get agreement before running it. Choose a method appropriate for the host and prefer a reversible rootless install. After `xpra --version` works, re-run the original command. Without Xpra or permission to install it, stop and report the limitation.

The browser also needs an HTML5 web root, normally configured as `html = <dir>` in `~/.config/xpra/xpra.conf`. The native `ATTACH` path works without it.

Read [`references/troubleshooting.md`](references/troubleshooting.md) for startup, handshake, authentication, timeout and window failures.
