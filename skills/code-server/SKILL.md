---
name: code-server
description: Use when asked to open a project directory in browser-based VS Code with code-server, check a session, or close one or all managed sessions.
---

# Code Server

## Commands

Resolve `scripts/code-server.py` relative to this skill and invoke it by absolute path on the Linux host that contains the project. Use the requested project directory for project commands, or the current directory if the user says to open the current project. Ask for a path if the project cannot be identified.

| Request | Command |
| --- | --- |
| Open or reopen a project | `python3 /absolute/path/to/scripts/code-server.py open PROJECT [--slug SLUG] [--port PORT] [--password PASSWORD] [--force]` |
| Check the session | `python3 /absolute/path/to/scripts/code-server.py status PROJECT [--slug SLUG]` |
| Close the session | `python3 /absolute/path/to/scripts/code-server.py close PROJECT [--slug SLUG]` |
| Close all managed sessions on this host | `python3 /absolute/path/to/scripts/code-server.py close-all` |

Run `close-all` only on an explicit bulk-close request. It stops this launcher's sessions for the current user on the current host. Ask the user to save open edits before a single or bulk close. Report `SESSIONS_STOPPED` and `SESSIONS_FAILED` for a bulk close. A failed stop makes the command exit nonzero.

Quote paths containing spaces. Pass `--port PORT` when requested. The default lets the kernel choose a port. Opening a running project reuses its session. If the requested port is occupied, report the startup error. Check status on the host where the session was opened.

Use `--force` only when the user asks to restart or terminate the current session. It stops the recorded session, escalates to SIGKILL when the stop times out, then starts a fresh session. A fresh session rewrites the config file, so a custom password reverts to the account name unless `--password` is passed. With `--port PORT` it also SIGKILLs this user's listeners that still block the port after the stop. A port held by another user's listener, or a missing `lsof`, fails before the session is stopped.

## Project launchers

Opening a project creates `PROJECT/.code-server/<slug>/` with executable `open.sh`, `status.sh` and `close.sh`. The default slug is derived from the project folder name. Use `--slug SLUG` to give the launcher a different name. Each slug has its own session, editor state, password, and startup log. Its local Git ignore file excludes these files from normal staging.

The scripts work from any working directory and require the skill to remain at its generated path. `open.sh [--port PORT] [--password PASSWORD] [--force]` reopens the same launcher. `close.sh` stops its server and releases the port. For a project with launchers directly under `.code-server/`, close the old session first. The next default open moves its editor data into the default slug directory.

## Connect and verify

1. Run the requested command. An open succeeds after the loopback HTTP health check passes. Report the exact `LAUNCHER_DIR` and `BROWSER` from stdout. For a remote host also report the printed `SSH` tunnel command. Tell the user to open `BROWSER` on their client after starting the tunnel.
2. Sign in with the `password` entry in the printed `PASSWORD_FILE`. Each new session defaults to the Linux account name. `--password PASSWORD` overrides that default for the new session. To change the password of a running session, close it before reopening. The server listens on `127.0.0.1` and stores the password in a mode-0600 config file. Report the file path and keep the password out of chat and URLs.
3. For status or close, report the returned `STATUS=running` or `STATUS=stopped`. On failure, use the error and startup log to diagnose the requested session. The launcher requires code-server on `PATH` and Python 3.9 or newer on Linux with PID file descriptor support.
