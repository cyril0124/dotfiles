---
name: xpra-web
description: Use when asked to open or view a GUI program on a remote, headless, or shared Linux host, in a browser or with an xpra client.
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

## Quick start

Run the script from this skill's directory (`<skill dir>/scripts/xpra-web.sh`):

```bash
bash scripts/xpra-web.sh ensure                # reuse a live session, or start one
bash scripts/xpra-web.sh run -- xclock         # launch a program inside that session
bash scripts/xpra-web.sh list                  # displays, ports, windows, program pids
bash scripts/xpra-web.sh close xclock          # close matching programs, port stays
bash scripts/xpra-web.sh close --all           # close every program, keep the session
bash scripts/xpra-web.sh stop :10              # stop one session and its children
bash scripts/xpra-web.sh stop --all            # stop every live session (destructive)
```

Options: `--host HOST` (default `0.0.0.0`), `--port PORT` (default `0`, kernel picks), `--display :N`, `--password PW`.

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
PASSWORD=<value>            (only when this run created the session)
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
:10	tcp=0.0.0.0:35971	windows=xclock	programs=xclock(12345)
```

## Passwords

The TCP bind always authenticates. A new session gets a password file at
`${XDG_RUNTIME_DIR:-/tmp}/xpra-web-<user>/password`, mode 0600, holding the user name unless `--password` says otherwise. Report the password with the port: the browser client prompts for it before it connects.

```bash
bash scripts/xpra-web.sh ensure --password 'something-else'
```

Against a live session this rewrites the file, and xpra re-reads it on change, so the new password applies from the next connection without a restart. Editing the file has the same effect, and if the file is missing the next `ensure` writes it again with the default so a live session stays reachable.

A live session whose TCP listener has no `auth=` option has no password. `ensure` reuses it and reports `AUTH=none` with a warning on stderr. Tell the user the port is unprotected and offer to restart the session (`stop :N`, then `ensure`).

## Closing things on request

Match the scope the user asked for. Closing one program is not a request to tear down the session.

| Request | Command | Effect |
| --- | --- | --- |
| "close that app" | `close myapp` | SIGTERM matching programs, session and port stay up |
| "close everything" | `close --all` | every program in that session dies, session and port stay up |
| program ignores SIGTERM | `close --all --force` | SIGKILL the survivors |
| "shut it down" | `stop :10` | session and children exit, port released |
| "shut all of them down" | `stop --all` | every live session exits |

Sessions are shared by design, so one session can hold programs you did not start, including the user's own work started in parallel. Before closing anything:

1. Run `list` and read `programs=<name>(<pid>)`.
2. Close by program name, not by session.
3. Use `close --all`, `stop --all` or `stop :N` only for the scope the user asked for.

`close` acts on one session: the one `--display` names, or the only live session. When several sessions are live and `--display` is missing, it refuses and lists them. `stop --all` is the only command that spans sessions. Both `close` and `stop` print the programs they are about to end before ending them, and `stop` never guesses: it needs `:N` or `--all`.

A killed GUI loses whatever was only in memory, so a broad close is destructive, not cleanup.

`close` matches a child by command-line substring, ignoring case, so `close myapp` also matches `myapp --config /path/to/file`. It reports `CLOSED=<n>` and `STILL_RUNNING=<pids>`. No match is normal, not an error.

Avoid `pkill` and `killall` by program name. On a shared host they reach the xpra server, other users' processes and the agent's own command line. `close` only touches pids reported by this session's `xpra info`.

When the user names something that is not running, say so and show `list`.

## Reporting the result

Give the user the port, the password, and both access paths:

- browser: `http://<host>:<PORT>/`, when `WEB=yes`; the client prompts for the password
- xpra client: the printed `ATTACH` line, which already carries `--password-file`
- through SSH only: forward the port and use the `LOCAL` URL, `ssh -L <PORT>:127.0.0.1:<PORT> <host>`

When `WEB=no`, no browser client was served, which means the html5 web root is missing. Do not pass `--html=on` or `--html=auto` on the command line: that overrides the configured path and the server logs `Error: cannot find the html web root`. Leave `--html` alone and the config applies.

## When xpra is missing

The script exits 3 and points back here. Installing is a judgement call, not a scripted step.

Ask the user first. Then choose the method that fits the machine: which package managers exist, which OS it is, whether the package exists there at all. Show the command you intend to run and get agreement before running it. Prefer an install the user can undo and that does not need root. Once `xpra --version` works, re-run the original command.

If the user declines, or the machine cannot install it, say so and stop. Running the GUI on a machine with a display, or SSH with X11 forwarding, are the alternatives.

xpra alone covers the TCP path (`ATTACH`). The browser path also needs the html5 web root on disk, pointed at by `html = <dir>` in `~/.config/xpra/xpra.conf`. Without it the script still works and reports `WEB=no`.

## Reuse rules

- `ensure` reuses the first live session whose listener host equals `--host` exactly, which defaults to `0.0.0.0`. A session bound to a different host is never reused, because a listener cannot be changed after startup.
- It creates a session only when no live session has a usable TCP listener, on the first free display in `:10` to `:99`, skipping displays xpra knows and existing `/tmp/.X11-unix/X<n>` sockets.
- A different program is not a reason for a second session. Many GUIs share one session and one port.
- `ensure` is idempotent and reports the existing port.

## Background execution

The server daemonizes itself (`--daemon=yes`) and returns in about 3 seconds, so nothing here needs a background shell. Do not run `xpra start` in a way that blocks for the session's lifetime.

`run` sends one control command to the running server and returns at once. The program becomes a child of the xpra server, so it outlives the agent shell and joins the shared session.

When the agent has a process tool, use it for a command that has to stay in the foreground and be supervised, for example `process start name=myapp command='DISPLAY=:10 myapp'`, or an `xpra start --daemon=no` server.

## Working directory and environment

`run` starts the program in the directory it was called from. GUI tools write next to where they run, so logs, session files and screenshots land in the user's working directory instead of the directory the session was created from. The command prints `CWD=<dir>`.

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

| Symptom | Cause | Action |
| --- | --- | --- |
| exit code 3, `xpra is not installed` | the dependency is absent | ask the user, then install (see [When xpra is missing](#when-xpra-is-missing)) |
| `Error: cannot find the html web root` in `server.log` | `--html=on` or `auto` overrode the config path | drop `--html`, restart the session |
| no listener within 10s | Xvfb or xpra startup failed after the bind check passed | the script prints the `server.log` tail; read it |
| `WEB=no` but the session is live | html root missing on this machine | use the xpra client path, or set `html = <dir>` in `~/.config/xpra/xpra.conf` |
| the user does not know the password | the default is the user name, stored in `PASSWORD_FILE` | read the file, or rewrite it with `ensure --password PW` |
| `AUTH=none` on a live session | it was started without `auth=` | restart it (`stop :N`, then `ensure`) to require the password |
| window never appears in the browser | nothing attached yet, or the child exited | `list`, then check the child with `ps` |
| browser shows a proxy `403 Forbidden` page | the viewer's HTTP proxy intercepts the port URL | add the host to `no_proxy`, or use the `LOCAL` URL through `ssh -L` |
| program dies immediately | missing env, license or display library | relaunch with `run -- env ...` and check the child's output |
| `run` says `xpra refused to launch` | xpra's reason is in the message; a reused session may have been started without new commands enabled | start a fresh session on a free display, or stop that session and re-run `ensure` |

Session log: `/run/user/$(id -u)/xpra/<N>/server.log`.

## Security

The TCP bind requires the password in `PASSWORD_FILE`, and xpra verifies it by challenge-response, so the password does not travel in clear. The stream itself is unencrypted and anyone on the network can try passwords against the port: keep it on a trusted network, or publish it through an SSH tunnel. `--host 127.0.0.1` keeps it local. A reused session reporting `AUTH=none` has no password at all until it is restarted.

## Cleanup

`stop :N` ends the session and its children. Leaving a session running is the point of reuse: the next `ensure` finds it again instead of opening another port.
