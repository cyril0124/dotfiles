---
name: xpra-web
description: Use when asked to open or view a GUI program on a remote, headless, or shared Linux host, in a browser or with an xpra client. Invoked directly as `xpra-web <ensure|run|list|close|close-all|stop>`.
disable-model-invocation: true
---

# Xpra Web

Serve X11 GUI programs from this machine over TCP so a browser or a local `xpra attach` can show them, and tell the user which port to open.

```
caller shell ──> xpra server (daemon, DISPLAY=:N, binds 0.0.0.0:PORT)
                   ├── child: xclock      one session, many programs
                   ├── child: myapp
                   ├── http://HOST:PORT/  html5 client for a browser
                   └── tcp://HOST:PORT    xpra attach / xpra info
```

## Invocation

This skill is invoked by name, so the user naming it with a subcommand is the
whole request. Read `xpra-web <subcommand> ...` (or `xpra-web.sh`, or the script
path) in any message as `bash scripts/xpra-web.sh <subcommand> ...`, with the
rest of their words passed through unchanged:

| The user writes | You run |
| --- | --- |
| `xpra-web` alone, or "open X in the browser on this host" | `ensure`, preceded by `run -- X` when a program is named |
| "add X to my session :10" | `run --display :10 -- X` |
| `xpra-web ls`, `xpra-web list` | `list` |
| `xpra-web close-all` | `close-all` |
| `xpra-web close xclock` | `close xclock` |
| `xpra-web stop :10` | `stop :10` |
| `xpra-web --help`, `xpra-web help` | `help`, then show what it printed |

Options travel unchanged: `xpra-web ensure --port 35971 --no-password` is
`ensure --port 35971 --no-password`. A named subcommand is the scope, not a
starting point: run exactly that one. Do not widen `close` into `close-all`, or
a subcommand into `stop`, on your own — only the user's own words justify a
broader scope. Ask one short question only when the user names no subcommand and
their request is one this table does not cover.

## Quick start

Run the script from this skill's directory (`<skill dir>/scripts/xpra-web.sh`):

```bash
bash scripts/xpra-web.sh ensure                # always a fresh session on a free port
bash scripts/xpra-web.sh ensure --port 35971   # that exact port, reusing a live session that already holds it
bash scripts/xpra-web.sh ensure --no-password  # no password on this session's TCP bind
bash scripts/xpra-web.sh run -- xclock         # launch xclock in a session of its own
bash scripts/xpra-web.sh run --display :10 -- myapp  # add a window to a session the user named
bash scripts/xpra-web.sh list                  # displays, ports, windows, programs, directories (`ls` also works)
bash scripts/xpra-web.sh close xclock          # close matching programs, port stays
bash scripts/xpra-web.sh close --all           # close every program, keep the session
bash scripts/xpra-web.sh close-all             # close every program everywhere, then stop every session
bash scripts/xpra-web.sh stop :10              # stop one session and its children
bash scripts/xpra-web.sh stop --all            # stop every live session (destructive)
```

Options: `--host HOST` (default `0.0.0.0`), `--port PORT` (default `0`, kernel picks), `--display :N`, `--password PW`, `--no-password`.

`ensure` and `run` both start a session on a free port; `run` therefore puts each program on its own port unless the request names an existing session (`--display :N` or `--port N`). [Reuse rules](#reuse-rules) gives the exact conditions and who may ask for reuse.

A new session takes about 3 seconds, a reused one about half a second. A host or port that cannot be bound is rejected in under a second, before `xpra start` runs, so a bad address never waits out a startup timeout.

`ensure` prints this block:

```
SESSION=created|reused
DISPLAY=:10
BIND=0.0.0.0:35971
PORT=35971
BROWSER=http://<host>:35971/
ATTACH=xpra attach --password-file=/run/user/<uid>/xpra-web-<user>/password tcp://<host>:35971
LOCAL=http://127.0.0.1:35971/
AUTH=file|none
PASSWORD=<value>            (only when this run created a password-protected session)
PASSWORD_FILE=<path>        (only when AUTH=file)
WEB=yes|no
```

`run` prints that same block on stderr and three keys on stdout:

```
DISPLAY=:10
CWD=/path/you/ran/from
APP_PID=12345
```

`list` prints one tab-separated line per session:

```
:10	tcp=0.0.0.0:35971	windows=xclock	programs=xclock(12345)	cwd=/path/to/project
```

`programs=` gives each child as `name(pid)`. `cwd=` is the working directory those
children actually run in, read from `/proc/<pid>/cwd` and deduplicated, so programs
started from one directory show one path; it is `none` when nothing runs or when
procfs hides the directory.

## Passwords

Two modes, both chosen when the session starts and neither changeable afterwards:

| Request | Listener | Effect |
| --- | --- | --- |
| default, or `--password PW` | `auth=file` | the password is required on every connection |
| `--no-password` | no `auth=` | the listener accepts anyone who can reach the port |

### Password mode (default)

The TCP bind authenticates against a password file at `${XDG_RUNTIME_DIR:-/tmp}/xpra-web-<user>/password`, mode 0600, holding the user name unless `--password` says otherwise. Report the password with the port: the browser client prompts for it before it connects.

```bash
bash scripts/xpra-web.sh ensure --password 'something-else'
```

Against a live session this rewrites the file, and xpra re-reads it on change, so the new password applies from the next connection without a restart. Editing the file has the same effect, and if the file is missing the next `ensure` writes it again with the default so a live session stays reachable.

### No password

```bash
bash scripts/xpra-web.sh ensure --host 127.0.0.1 --no-password
```

`--no-password` starts a session whose TCP bind carries no `auth=` option. The result block reports `AUTH=none` and omits `PASSWORD` and `PASSWORD_FILE`; the `ATTACH` line carries no `--password-file`, and no client is prompted.

Reachability is now the only protection, so pair it with `--host 127.0.0.1` unless the user asks for a wider bind, and say in your report that the port has no password. When the bind is not loopback the script prints that warning on stderr itself. `--no-password` never downgrades a live session: against a password-protected one it starts a second session instead.

## Closing things on request

Match the scope the user asked for. Closing one program is not a request to tear down the session.

| Request | Command | Effect |
| --- | --- | --- |
| "close that app" | `close myapp` | SIGTERM matching programs, session and port stay up |
| "close everything" | `close --all` | every program in that session dies, session and port stay up |
| program ignores SIGTERM | `close --all --force` | SIGKILL the survivors |
| "shut it down" | `stop :10` | session and children exit, port released |
| "shut all of them down" | `stop --all` | every live session exits |
| "close everything, everywhere" | `close-all` | every program in every session dies, then every session exits |

`close-all` accepts `--force` and nothing else, and prints `SESSIONS_STOPPED=<n>`. It spans sessions by design, so run it only for a request that names every session, and tell the user which sessions it stopped: it takes down the user's own work in parallel, not just sessions this skill created.

Sessions are shared by design, so one session can hold programs you did not start, including the user's own work started in parallel. Before closing anything:

1. Run `list` (`ls` works too) and read `programs=<name>(<pid>)` and `cwd=<dir>`.
2. Close by program name, not by session.
3. Use `close --all`, `stop --all`, `stop :N` or `close-all` only for the scope the user asked for.

`close` acts on one session: the one `--display` names, or the only live session. When several sessions are live and `--display` is missing, it refuses and lists them. `stop --all` and `close-all` are the only commands that span sessions. Both `close` and `stop` print the programs they are about to end before ending them, and `stop` never guesses: it needs `:N` or `--all`.

A killed GUI loses whatever was only in memory, so a broad close is destructive, not cleanup.

`close` matches a child by command-line substring, ignoring case, so `close myapp` also matches `myapp --config /path/to/file`. It reports `CLOSED=<n>` and `STILL_RUNNING=<pids>`, or `none` when nothing survived. No match is normal, not an error.

`close` only touches pids reported by this session's `xpra info`, so it stays inside the session; `pkill` and `killall` match by name across the host, reaching the xpra server, other users' processes and the agent's own command line.

When the user names something that is not running, say so and show `list`.

## Reporting the result

Give the user the port, the password when there is one, and both access paths:

- browser: `http://<host>:<PORT>/`, when `WEB=yes`; the client prompts for the password when `AUTH=file`, and connects straight in when `AUTH=none`
- xpra client: the printed `ATTACH` line, which already carries `--password-file` when there is one
- through SSH only: forward the port and use the `LOCAL` URL, `ssh -L <PORT>:127.0.0.1:<PORT> <host>`

With `AUTH=none`, state that the port is unprotected instead of naming a password.

When `WEB=no`, no browser client was served, which means the html5 web root is missing. Leave `--html` unset so the configured path applies: `--html=on` or `--html=auto` overrides it and the server logs `Error: cannot find the html web root`.

## When xpra is missing

The script exits 3 and points back here. Installing is a judgement call, not a scripted step.

Ask the user first. Then choose the method that fits the machine: which package managers exist, which OS it is, whether the package exists there at all. Show the command you intend to run and get agreement before running it. Prefer an install the user can undo and that does not need root. Once `xpra --version` works, re-run the original command.

If the user declines, or the machine cannot install it, say so and stop. Running the GUI on a machine with a display, or SSH with X11 forwarding, are the alternatives.

xpra alone covers the TCP path (`ATTACH`). The browser path also needs the html5 web root on disk, pointed at by `html = <dir>` in `~/.config/xpra/xpra.conf`. Without it the script still works and reports `WEB=no`.

## Reuse rules

- The default is a fresh session on a free port. A live session is joined only when the request names it: `--display :N` pointing at that live session, or `--port N` naming the port that session already holds. Plain `ensure`, plain `run` and `run --port 0` always create a session.
- A named session is joined only when it matches on all axes: listener host equals `--host` exactly, listener port equals `--port` when a non-zero port was asked for, and the session's auth mode equals the requested one (`file` by default, `none` with `--no-password`). Host, port and auth are all fixed at startup, so any mismatch fails or starts a new session rather than ignoring the request.
- Reuse is the user's call, not a convenience: pass `--display :N` or `--port N` only when the user asked to add a window to an existing session, never to save a port on your own.
- What it left alone is reported on stderr, for example `2 live session(s) left alone: default is a fresh session; pass --port N or --display :N to reuse one` for a plain request, or `3 live session(s) do not match host=0.0.0.0, port=35971, auth=file; starting a new one` when the named `--port` is held by a session that differs on host or auth. A named `--display` never gets this treatment: a mismatch there fails outright, as the next bullet says.
- A new session takes the first free display in `:10` to `:99`, skipping displays xpra knows and existing `/tmp/.X11-unix/X<n>` sockets.
- `--display :N` naming a live session that does not match fails with the live listener printed, and says to stop it or drop `--port` / `--no-password`. A live session is never restarted or reinterpreted behind the user's back.
- `--port N` fails before `xpra start` when N is held by some other process, and is reused when N belongs to a matching live session. `--port 0` means the kernel picks, and then any port is acceptable.
- A repeated `--port N` or `--display :N` request returns the same session and port, for `ensure` and `run` alike.
- A second session is the default outcome, not a symptom: a new program gets a session of its own unless the request names an existing one to join.

## Background execution

The server daemonizes itself (`--daemon=yes`) and returns in about 3 seconds, so nothing here needs a background shell. Do not run `xpra start` in a way that blocks for the session's lifetime.

`run` sends one control command to the running server and returns at once. The program becomes a child of the xpra server, so it outlives the agent shell and lives in the session `run` chose.

When the agent has a process tool, use it for a command that has to stay in the foreground and be supervised, for example `process start name=myapp command='DISPLAY=:10 myapp'`, or an `xpra start --daemon=no` server.

## Working directory and environment

`run` starts the program in the directory it was called from. GUI tools write next to where they run, so logs, session files and screenshots land in the user's working directory instead of the directory the session was created from. The command prints `CWD=<dir>`, and `list` reports the running children's directories in its `cwd=` column.

xpra has no per-command working directory: it runs every child in the server's own directory. The bundled `scripts/xpra-run-in.sh` changes to the requested directory and `exec`s the program, so the pid xpra tracks belongs to the program itself and `close <name>` still finds it.

Arguments survive intact, including spaces, quotes and empty strings:

```bash
cd /path/to/project && bash scripts/xpra-web.sh run -- myapp "file with spaces.fsdb" --tag "a'b"
```

Environment variables come from the xpra server, not from the calling shell, so pass what the program needs:

```bash
bash scripts/xpra-web.sh run -- env LD_LIBRARY_PATH=/opt/tool/lib myapp --config /path/to/config
```

An old session keeps its old environment. Restart it (`stop :N`, then `ensure`) when the whole session needs a fresh one.

## Verifying a session

```bash
bash scripts/xpra-web.sh list
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:$PORT/   # 200 means the browser client is served
xpra info $DISPLAY | grep network.sockets.tcp.listeners           # the real bind address and port
```

A client maps windows, so `xpra screenshot` stays empty until something attaches.

## Troubleshooting

Read [`references/troubleshooting.md`](references/troubleshooting.md) when a command exits non-zero or a session misbehaves: it maps each symptom to its cause and the action to take, and names the session log.

## Security

With `auth=file`, the TCP bind requires the password in `PASSWORD_FILE`, and xpra verifies it by challenge-response, so the password does not travel in clear. `--no-password` removes that check entirely: the listener accepts any client that can reach the port, which is why that mode belongs on `127.0.0.1` (see [No password](#no-password)). The stream itself is unencrypted and anyone on the network can try passwords against a password-protected port: keep it on a trusted network, or publish it through an SSH tunnel. `--host 127.0.0.1` keeps it local either way.

## Cleanup

`stop :N` ends the session and its children. Plain `ensure` and `run` never join a running session, so sessions pile up on their own ports until `stop :N` or `stop --all` ends them; naming `--port N` or `--display :N` is what finds one again.
