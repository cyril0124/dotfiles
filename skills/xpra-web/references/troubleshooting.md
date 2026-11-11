# Troubleshooting

Read this when a `xpra-web.sh` command exits non-zero, or when the symptom in the first column matches.

| Symptom | Cause | Action |
| --- | --- | --- |
| exit code 3, `xpra is not installed` | the dependency is absent | ask the user, then install (see [When xpra is missing](../SKILL.md#when-xpra-is-missing)) |
| `Error: cannot find the html web root` in `server.log` | `--html=on` or `auto` overrode the config path | drop `--html`, restart the session |
| no listener within 10s | Xvfb or xpra startup failed after the bind check passed | the script prints the `server.log` tail; read it |
| `FileNotFoundError: '/usr/bin/Xvfb'` in `server.log` | the `xvfb` line in `~/.config/xpra/xpra.conf` names a binary that is not on this machine | point `xvfb` at a real Xvfb; `ensure` refuses this configuration before starting |
| `Fatal server error: could not open default font 'fixed'` | that `xvfb` command has no font path | add `-fp /usr/share/fonts/X11/misc` to the `xvfb` line |
| browser sits at `Sending handshake` | the session answers TCP but never the protocol, most often because the server is spinning on an Xvfb it cannot drive | `doctor` marks it `status=bad` or `status=unresponsive`, and the session log records `connection timed out`. Point `xvfb` at an Xvfb that offers `+extension GLX +extension Composite +extension RANDR +extension RENDER`, then start a fresh session |
| `status=unresponsive`, and `list`/`stop` never return | a spinning server never reads its control channel | kill the pid from `SESSION ... server=<pid>`; `xpra stop :N` waits on that same channel, so it will hang too |
| `WEB=no` but the session is live | the html5 root is missing on this machine | use the xpra client path, or set `html = <dir>` in `~/.config/xpra/xpra.conf` |
| the user does not know the password | the default is the user name, stored in `PASSWORD_FILE` | read the file, or rewrite it with `ensure --password PW` |
| `AUTH=none` and that was not requested | the session was started with `--no-password`, or by another tool without `auth=` | report the port as unprotected; `stop :N` then a plain `ensure` gives a password-protected session |
| a second session appeared while a session was live | `ensure` and `run` both start a fresh session by default; only a named `--display`/`--port` joins one | expected; `list` shows both, `stop :N` ends the one you no longer need, `--display :N` targets the one you keep |
| `cannot bind <host>:<port>` | the port is held by a process that is not a matching live session | drop `--port` to let the kernel pick one, or choose another port |
| window never appears in the browser | nothing attached yet, or the child exited | `list`, then check the child with `ps` |
| browser shows a proxy `403 Forbidden` page | the viewer's HTTP proxy intercepts the port URL | add the host to `no_proxy`, or use the `LOCAL` URL through `ssh -L` |
| program dies immediately | missing env, license or display library | relaunch with `run -- env ...` and check the child's output |
| `run` says `xpra refused to launch` | xpra's reason is in the message; a reused session may have been started without new commands enabled | start a fresh session on a free display, or stop that session and re-run `ensure` |

Session log: `/run/user/$(id -u)/xpra/<N>/server.log`, or `~/.xpra/<N>/server.log` when that one is absent. The script prints the tail itself when startup fails.

## Xvfb

xpra runs whatever `xvfb` in `~/.config/xpra/xpra.conf` names. The usual default, `/usr/bin/Xvfb`, exists only where the Xvfb package is installed, so on many machines that line has to name a binary from elsewhere. xpra drives an Xvfb that offers `GLX`, `Composite`, `RANDR` and `RENDER`; an older one still displays windows but leaves the server spinning near a full core, which blocks every handshake while the GUI itself looks fine.

`pgrep -a Xvfb` shows the binary each live session runs, including xpra's own `Xvfb-for-Xpra-<display>` copies; a session that serves windows is a proven source for a working path.
