---
name: code-server
description: Use when asked to open a project directory in browser-based VS Code with code-server, check a session, or close one or all managed sessions.
---

# Code Server

Run `scripts/code-server.py` (path relative to this skill) by absolute path on the Linux host that holds the project. Use the requested project directory, or the current directory for "open the current project". Ask for a path when the project cannot be identified.

| Request | Command |
| --- | --- |
| Open or reopen a project | `python3 /abs/path/scripts/code-server.py open PROJECT [--slug SLUG] [--port PORT] [--password PASSWORD] [--force]` |
| Check the session | `python3 /abs/path/scripts/code-server.py status PROJECT [--slug SLUG]` |
| Close the session | `python3 /abs/path/scripts/code-server.py close PROJECT [--slug SLUG]` |
| Close all managed sessions on this host | `python3 /abs/path/scripts/code-server.py close-all` |

- Reopening a running project reuses its session. `--port` defaults to a kernel-chosen port; report a port-in-use startup error instead of retrying. Quote paths containing spaces. Check status on the host where the session was opened.
- `--force` only on an explicit restart request: stop the recorded session, SIGKILL it after the stop timeout, then start fresh. A fresh session rewrites the config, so a custom password reverts to the account name unless `--password` is passed. With `--port` it also SIGKILLs this user's listeners that still block the port; a listener owned by another user or a missing `lsof` fails before the session is stopped.
- `close-all` only on an explicit bulk-close request: it stops this launcher's sessions for the current user on the current host. Ask the user to save open edits before any close. Report `SESSIONS_STOPPED` and `SESSIONS_FAILED`; a failed stop exits nonzero.

## Project launchers

`open` creates `PROJECT/.code-server/<slug>/` with executable `open.sh`, `status.sh` and `close.sh`. The slug defaults to the project folder name; `--slug SLUG` renames the launcher. Each slug keeps its own session, editor state, password and `server.log`, and its local `.gitignore` keeps those files out of staging. The scripts work from any directory but need the skill at its generated path. `open.sh [--port PORT] [--password PASSWORD] [--force]` reopens the same launcher; `close.sh` stops it and releases the port.

## Connect and verify

1. Run the command. An open succeeds after the loopback health check passes. Report the exact `LAUNCHER_DIR` and `BROWSER`; on a remote host also report the printed `SSH` tunnel command and tell the user to open `BROWSER` after starting the tunnel.
2. Sign in with `password` from the printed `PASSWORD_FILE`: the account name by default, or `--password PASSWORD` for a new session. Changing a running session's password needs a close and reopen. The server binds `127.0.0.1` and keeps the password in a mode-0600 config file; report that path and keep the password out of chat and URLs.
3. Report `STATUS=running` or `STATUS=stopped`. On failure, diagnose from the error and `server.log`. Requires `code-server` on `PATH` and Python 3.9+ on Linux with PID file descriptor support.
