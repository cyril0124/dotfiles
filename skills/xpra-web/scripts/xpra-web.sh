#!/usr/bin/env bash
set -euo pipefail

# Serve Linux X11 GUI programs from this machine over TCP, so they can be viewed
# in a browser (xpra html5 client) or with a local `xpra attach`.
#
# One session holds many GUI programs: `ensure` starts a fresh session on a fresh
# port by default, and reuses a live session only when `--display`/`--port` names
# one. `run` reuses a matching session so several programs share one port.

HOST="0.0.0.0"
PORT="0"
DISPLAY_ARG=""
PASSWORD=""
AUTH_MODE="file"
WAIT_SECONDS="${XPRA_WEB_WAIT_SECONDS:-10}"

# "explicit": a fresh session unless --display or --port names a live one.
# "always": reuse any live session matching host and auth.
REUSE_POLICY="explicit"

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
RUN_IN="$SCRIPT_DIR/xpra-run-in.sh"

# The TCP bind authenticates against this file. XDG_RUNTIME_DIR is per-boot and
# private to the user, which is the right lifetime for a session password.
PASSWORD_DIR="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/xpra-web-$USER"
PASSWORD_FILE="$PASSWORD_DIR/password"

usage() {
  cat <<'USAGE'
Usage:
  xpra-web.sh ensure [options]          Start a network-visible xpra session
  xpra-web.sh run [options] -- CMD ...  Ensure a session, then launch CMD inside it
  xpra-web.sh list | ls                 Show live sessions, ports, windows and programs
  xpra-web.sh close PATTERN | --all     Close matching programs, keep the session alive
  xpra-web.sh close-all [--force]       Close every program everywhere, then stop every session
  xpra-web.sh stop :N | --all           Stop one named session, or every session
  xpra-web.sh help                      Show this message

  --all                 With stop: stop every live session. With close: every program
  --force               With close/close-all: SIGKILL programs that ignore SIGTERM

Options:
  --host HOST      Bind address (default: 0.0.0.0)
  --port PORT      Bind port; 0 lets the kernel pick one (default: 0)
  --display :N     Use display :N instead of the first free one
  --password PW    Password for the TCP bind (default: the user name)
  --no-password    Bind with no password at all (auth=none)

--password and --no-password are mutually exclusive.

ensure starts a new session on a free port every time. It reuses a live session
only when --display names that live session, or when --port N is given and a
session holding N also matches --host and the auth mode. run reuses a live
session matching --host and the auth mode (and --port when set), so several
programs share one port.

Output: KEY=value lines (SESSION, DISPLAY, BIND, PORT, BROWSER, ATTACH, AUTH,
PASSWORD, PASSWORD_FILE, WEB, ...).
USAGE
}

info() { printf '==> %s\n' "$1" >&2; }
fail() { printf 'ERROR: %s\n' "$1" >&2; exit 1; }

xpra_bin() {  if command -v xpra >/dev/null 2>&1; then
    command -v xpra
  elif [ -x "$HOME/.local/bin/xpra" ]; then
    printf '%s\n' "$HOME/.local/bin/xpra"
  else
    return 1
  fi
}

# Exit 3 means the dependency is missing: that is a question for the user, not
# something to work around here.
missing_xpra() {
  printf '%s\n' "ERROR: xpra is not installed (checked PATH and $HOME/.local/bin/xpra)." >&2
  printf '%s\n' "See 'When xpra is missing' in SKILL.md: ask the user, then install it." >&2
  exit 3
}

XPRA=""

# Live displays known to xpra, as ":N" lines.
live_displays() {
  "$XPRA" list 2>/dev/null | sed -n 's/.*LIVE session at \(:[0-9][0-9]*\).*/\1/p' | sort -u || true
}

# Print "<host> <port>" for the first TCP listener of a display, or fail.
tcp_listener() {
  local display=$1 line parsed
  line=$("$XPRA" info "$display" 2>/dev/null | grep -m1 '^network.sockets.tcp.listeners=' || true)
  [ -n "$line" ] || return 1
  parsed=$(printf '%s\n' "$line" | sed -n "s/.*(('\([^']*\)', '\([0-9][0-9]*\)').*/\1 \2/p")
  [ -n "$parsed" ] || return 1
  printf '%s\n' "$parsed"
}

# First display number that is free for both xpra and the X socket directory.
pick_display() {
  local used n
  used=$(
    {
      live_displays
      "$XPRA" displays 2>/dev/null | sed -n 's/.*\(:[0-9][0-9]*\).*/\1/p'
    } | sort -u
  )
  for n in $(seq 10 99); do
    printf '%s\n' "$used" | grep -qx ":$n" && continue
    [ -e "/tmp/.X11-unix/X$n" ] && continue
    printf ':%s\n' "$n"
    return 0
  done
  return 1
}

server_log() {
  local display=${1#:} path
  for path in "/run/user/$(id -u)/xpra/$display/server.log" "$HOME/.xpra/$display/server.log"; do
    if [ -f "$path" ]; then
      printf '%s\n' "$path"
      return 0
    fi
  done
  return 1
}

report_server_log() {
  local log
  if log=$(server_log "$1"); then
    printf '%s\n' "--- tail of $log ---" >&2
    tail -n 15 "$log" >&2
  fi
}

# A port that is already taken makes `xpra start` spin for about 20s before giving
# up, so reject it up front instead of waiting that out.
port_is_free() {
  local host=$1 port=$2
  command -v python3 >/dev/null 2>&1 || return 0
  python3 - "$host" "$port" <<'PY'
import socket
import sys
sock = socket.socket()
try:
    sock.bind((sys.argv[1], int(sys.argv[2])))
except OSError:
    sys.exit(1)
finally:
    sock.close()
PY
}

# PID of the daemonized server, used to stop waiting the moment it dies.
server_pid() {
  local display=${1#:} path pid
  for path in "/run/user/$(id -u)/xpra/$display/server.pid" "$HOME/.xpra/$display/server.pid"; do
    [ -f "$path" ] || continue
    pid=$(cat "$path" 2>/dev/null || true)
    [ -n "$pid" ] || continue
    printf '%s\n' "$pid"
    return 0
  done
  return 1
}

# Poll for the listener: return the moment it appears, and give up early when the
# server process has already died instead of sitting out the whole timeout.
wait_for_listener() {
  local display=$1 deadline=$((SECONDS + WAIT_SECONDS)) started=$SECONDS out pid
  while [ "$SECONDS" -lt "$deadline" ]; do
    if out=$(tcp_listener "$display"); then
      printf '%s\n' "$out"
      return 0
    fi
    pid=$(server_pid "$display" || true)
    if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
      info "xpra server $display exited before listening"
      return 1
    fi
    # A server that died without leaving a pid file never shows up in `xpra list`.
    if [ $((SECONDS - started)) -ge 5 ] && ! live_displays | grep -qx "$display"; then
      info "xpra session $display is not registered; startup failed"
      return 1
    fi
    sleep 0.2
  done
  return 1
}

# 200 on "/" means the html5 web root was found and a browser client is served.
# A window bound to one address is not reachable on loopback, so probe both.
web_available() {
  local bind_host=$1 port=$2 probe code
  command -v curl >/dev/null 2>&1 || return 1
  for probe in "$bind_host" 127.0.0.1; do
    [ "$probe" = "0.0.0.0" ] && probe=127.0.0.1
    code=$(curl -s -o /dev/null -m 5 -w '%{http_code}' "http://$probe:$port/" || true)
    [ "$code" = "200" ] && return 0
  done
  return 1
}

print_result() {
  local session=$1 display=$2 bind_host=$3 port=$4 auth=$5 password=$6 password_file=$7 host
  host=$(hostname -f 2>/dev/null || hostname)
  printf 'SESSION=%s\n' "$session"
  printf 'DISPLAY=%s\n' "$display"
  printf 'BIND=%s:%s\n' "$bind_host" "$port"
  printf 'PORT=%s\n' "$port"
  printf 'BROWSER=http://%s:%s/\n' "$host" "$port"
  if [ "$auth" = "none" ]; then
    printf 'ATTACH=xpra attach tcp://%s:%s\n' "$host" "$port"
  else
    printf 'ATTACH=xpra attach --password-file=%s tcp://%s:%s\n' "$password_file" "$host" "$port"
  fi
  printf 'LOCAL=http://127.0.0.1:%s/\n' "$port"
  printf 'AUTH=%s\n' "$auth"
  if [ -n "$password" ]; then
    printf 'PASSWORD=%s\n' "$password"
  fi
  if [ "$auth" != "none" ]; then
    printf 'PASSWORD_FILE=%s\n' "$password_file"
  fi
  printf 'WEB=%s\n' "$(web_available "$bind_host" "$port" && echo yes || echo no)"
}

# Password file for the TCP bind: written before the server starts, readable only
# by this user, and re-read by xpra whenever its mtime changes.
prepare_password() {
  mkdir -p -- "$PASSWORD_DIR" || fail "cannot create $PASSWORD_DIR"
  chmod 700 -- "$PASSWORD_DIR" 2>/dev/null || true
  if [ -n "$PASSWORD" ]; then
    printf '%s' "$PASSWORD" > "$PASSWORD_FILE"
  elif [ ! -f "$PASSWORD_FILE" ]; then
    printf '%s' "$(id -un)" > "$PASSWORD_FILE"
  fi
  chmod 600 -- "$PASSWORD_FILE" 2>/dev/null || true
}

# "file" when the session's TCP bind carries a per-socket auth option, else "none".
session_auth() {
  local argv
  argv=$("$XPRA" info "$1" 2>/dev/null | grep -m1 '^server.argv=' || true)
  case "$argv" in
    *",auth="*) printf 'file\n' ;;
    *) printf 'none\n' ;;
  esac
}

# A live session is reusable only when its listener matches the request on every
# axis. Host, port and auth mode are all fixed at startup, so a mismatch means a
# new session, never a silently different one.
listener_matches() {
  local display=$1 listener=$2
  [ "${listener%% *}" = "$HOST" ] || return 1
  if [ "$PORT" != "0" ] && [ "${listener##* }" != "$PORT" ]; then
    return 1
  fi
  [ "$(session_auth "$display")" = "$AUTH_MODE" ] || return 1
  return 0
}

# An unauthenticated listener on a routable address is open to everyone who can
# reach it, which the caller has to say out loud when reporting the port.
warn_if_unauthenticated() {
  local bind_host=$1 port=$2
  case "$bind_host" in
    127.0.0.1|::1|localhost) return 0 ;;
  esac
  printf '%s\n' "WARNING: $bind_host:$port has no password, so anyone who can reach it has full access." >&2
  printf '%s\n' "Use --host 127.0.0.1 to keep it local, or keep the port on a trusted network." >&2
}

# The password file a running session authenticates against, when it is visible.
session_password_file() {
  local argv
  argv=$("$XPRA" info "$1" 2>/dev/null | grep -m1 '^server.argv=' || true)
  printf '%s\n' "$argv" | sed -n "s/.*,auth=[^,]*,filename=\([^,']*\).*/\1/p" | head -1
}

# Find a reusable session, or start one. Prints the result block.
ensure_session() {
  local display="$DISPLAY_ARG" session="reused" listener="" bind_host="" port=""
  local requested_live=0 skipped=0 bind_opt="" may_reuse=1 reason=""

  # A fresh session is the default: only a named display or port reuses one.
  if [ "$REUSE_POLICY" = "explicit" ] && [ "$PORT" = "0" ] && [ -z "$DISPLAY_ARG" ]; then
    may_reuse=0
    reason="default is a fresh session; pass --port N or --display :N to reuse one"
  fi

  if [ -n "$display" ]; then
    if "$XPRA" info "$display" >/dev/null 2>&1; then
      requested_live=1
      listener=$(tcp_listener "$display" || true)
      if [ -n "$listener" ] && ! listener_matches "$display" "$listener"; then
        fail "session $display listens on ${listener%% *}:${listener##* } (auth=$(session_auth "$display")); that does not match host=$HOST, port=$PORT, auth=$AUTH_MODE. Stop $display first, or drop --port / --no-password."
      fi
    fi
  elif [ "$may_reuse" = 1 ]; then
    while IFS= read -r candidate; do
      listener=$(tcp_listener "$candidate" || true)
      [ -n "$listener" ] || continue
      if ! listener_matches "$candidate" "$listener"; then
        skipped=$((skipped + 1))
        continue
      fi
      display=$candidate
      break
    done < <(live_displays)
  else
    skipped=$(live_displays | grep -c . || true)
  fi

  if [ -n "$display" ] && [ -n "$listener" ]; then
    bind_host=${listener%% *}
    port=${listener##* }
    local auth pw_file
    auth=$(session_auth "$display")
    pw_file=$(session_password_file "$display")
    [ -n "$pw_file" ] || pw_file="$PASSWORD_FILE"
    if [ "$auth" = "file" ] && [ "$pw_file" = "$PASSWORD_FILE" ] && { [ -n "$PASSWORD" ] || [ ! -f "$PASSWORD_FILE" ]; }; then
      # xpra re-reads the file when its mtime changes, so this applies at once.
      # Rewriting a missing file keeps a live session reachable.
      prepare_password
      info "password file written to $PASSWORD_FILE; the running session uses it on the next connection"
    fi
    print_result "$session" "$display" "$bind_host" "$port" "$auth" "" "$pw_file"
    [ "$auth" = "none" ] && warn_if_unauthenticated "$bind_host" "$port"
    return 0
  fi

  if [ "$requested_live" = 1 ]; then
    fail "session $display is live but has no TCP listener; stop $display first, or choose another --display"
  fi

  if [ -z "$display" ]; then
    display=$(pick_display) || fail "no free display number found in :10-:99"
  fi

  session="created"
  if ! port_is_free "$HOST" "$PORT"; then
    fail "cannot bind $HOST:$PORT (already in use, or not a local address); drop --port to let the kernel pick one"
  fi
  if [ "$skipped" != "0" ]; then
    if [ -n "$reason" ]; then
      info "$skipped live session(s) left alone: $reason"
    else
      info "$skipped live session(s) do not match host=$HOST, port=$PORT, auth=$AUTH_MODE; starting a new one"
    fi
  fi
  if [ "$AUTH_MODE" = "none" ]; then
    bind_opt="$HOST:$PORT"
    info "starting xpra session $display on $HOST:$PORT with no password (auth=none)"
  else
    prepare_password
    bind_opt="$HOST:$PORT,auth=file,filename=$PASSWORD_FILE"
    info "starting xpra session $display on $HOST:$PORT (password in $PASSWORD_FILE)"
  fi
  if ! "$XPRA" start "$display" \
    --bind-tcp="$bind_opt" \
    --daemon=yes \
    --mdns=no \
    --start-new-commands=yes >/dev/null 2>&1; then
    report_server_log "$display"
    fail "xpra failed to start on $display (see the log above)"
  fi

  listener=$(wait_for_listener "$display") || {
    report_server_log "$display"
    fail "xpra started but no TCP listener appeared within ${WAIT_SECONDS}s"
  }
  bind_host=${listener%% *}
  port=${listener##* }
  if [ "$AUTH_MODE" = "none" ]; then
    print_result "$session" "$display" "$bind_host" "$port" "none" "" ""
    warn_if_unauthenticated "$bind_host" "$port"
  else
    print_result "$session" "$display" "$bind_host" "$port" "file" "$(cat "$PASSWORD_FILE")" "$PASSWORD_FILE"
  fi
}

# Resolve the display of the session to reuse, starting one if needed.
ensure_display() {
  local out
  out=$(ensure_session)
  printf '%s\n' "$out" >&2
  printf '%s\n' "$out" | sed -n 's/^DISPLAY=//p'
}

cmd_list() {
  local display listener windows programs found=0 all_windows
  # xpra lists every display at once; keep the rows that belong to this one.
  all_windows=$("$XPRA" list-windows 2>/dev/null || true)
  while IFS= read -r display; do
    found=1
    listener=$(tcp_listener "$display" || true)
    [ -n "$listener" ] || listener="none"
    windows=$(
      printf '%s\n' "$all_windows" |
        awk -v d="$display" '$1 == d { sub(/^[^ \t]+[ \t]+[^ \t]+[ \t]*/, ""); print }' |
        paste -sd ', ' -
    ) || windows=""
    programs=$(child_table "$display" | format_programs || true)
    printf '%s\ttcp=%s\twindows=%s\tprograms=%s\n' \
      "$display" "${listener// /:}" "${windows:-none}" "${programs:-none}"
  done < <(live_displays)
  [ "$found" = 1 ] || printf 'no live xpra sessions\n'
}

# Say what a destructive command is about to take down, before it does.
report_inventory() {
  local display=$1 table
  table=$(child_table "$display" || true)
  if [ -n "$table" ]; then
    printf '%s\n' "about to stop $display, running programs:" >&2
    printf '%s\n' "$table" | while IFS=$'\t' read -r pid cmd; do
      printf '  %s (pid %s)\n' "$(label_of "$cmd")" "$pid" >&2
    done
  else
    printf '%s\n' "about to stop $display, no programs running" >&2
  fi
}

cmd_stop() {
  local display="" all=0 arg sessions
  for arg in "$@"; do
    case "$arg" in
      --all) all=1 ;;
      "") ;;
      *) display=$arg ;;
    esac
  done

  if [ "$all" = 1 ]; then
    sessions=$(live_displays)
    [ -n "$sessions" ] || { printf 'no live xpra sessions\n'; return 0; }
    while IFS= read -r display; do
      report_inventory "$display"
    done <<< "$sessions"
    while IFS= read -r display; do
      info "stopping xpra session $display"
      "$XPRA" stop "$display" || true
    done <<< "$sessions"
    return 0
  fi

  if [ -z "$display" ]; then
    printf '%s\n' 'ERROR: stop needs an explicit display (:N) or --all' >&2
    if [ -n "$(live_displays)" ]; then
      printf '%s\n' 'Other work may be live in these sessions; check `list` and name the one to stop:' >&2
      live_displays | sed 's/^/  /' >&2
    else
      printf '%s\n' 'No live xpra sessions right now.' >&2
    fi
    exit 2
  fi
  report_inventory "$display"
  info "stopping xpra session $display"
  "$XPRA" stop "$display"
}

# Close programs inside one session, leaving the session and its port alive.
# Args: DISPLAY FORCE ALL [PATTERN ...]
close_session_programs() {
  local display=$1 force=$2 all=$3
  shift 3
  local -a patterns=("$@") pids=() labels=() alive=()
  local table pid cmd label pattern i deadline

  table=$(child_table "$display" || true)
  if [ -z "$table" ]; then
    printf 'DISPLAY=%s\nCLOSED=0\n' "$display"
    printf 'no programs running in session %s\n' "$display" >&2
    return 0
  fi

  while IFS=$'\t' read -r pid cmd; do
    label=$(label_of "$cmd")
    if [ "$all" = 1 ]; then
      pids+=("$pid"); labels+=("$label")
      continue
    fi
    for pattern in "${patterns[@]}"; do
      if printf '%s\n' "$label" | grep -qiF -- "$pattern"; then
        pids+=("$pid"); labels+=("$label")
        break
      fi
    done
  done <<< "$table"

  if [ "${#pids[@]}" = 0 ]; then
    printf 'DISPLAY=%s\nCLOSED=0\n' "$display"
    printf 'no program matched on %s; run `list` to see what is running\n' "$display" >&2
    return 0
  fi

  info "closing ${#pids[@]} program(s) in $display:"
  for i in "${!pids[@]}"; do
    printf '  %s (pid %s)\n' "${labels[$i]}" "${pids[$i]}" >&2
  done
  for pid in "${pids[@]}"; do
    kill -TERM "$pid" 2>/dev/null || true
  done

  deadline=$((SECONDS + 5))
  while [ "$SECONDS" -lt "$deadline" ]; do
    alive=()
    for pid in "${pids[@]}"; do
      kill -0 "$pid" 2>/dev/null && alive+=("$pid")
    done
    [ "${#alive[@]}" = 0 ] && break
    sleep 0.3
  done

  if [ "${#alive[@]}" -gt 0 ] && [ "$force" = 1 ]; then
    for pid in "${alive[@]}"; do kill -KILL "$pid" 2>/dev/null || true; done
    sleep 0.5
    alive=()
    for pid in "${pids[@]}"; do
      kill -0 "$pid" 2>/dev/null && alive+=("$pid")
    done
  fi

  printf 'DISPLAY=%s\nCLOSED=%s\n' "$display" "$(( ${#pids[@]} - ${#alive[@]} ))"
  printf 'STILL_RUNNING=%s\n' "${alive[*]:-none}"
}

# Close programs in one session, named with --display or the only live one.
cmd_close() {
  local display="$DISPLAY_ARG" all=0 force=0 arg sessions count
  local -a patterns=()

  for arg in "$@"; do
    case "$arg" in
      --all) all=1 ;;
      --force) force=1 ;;
      -*) fail "unknown option for close: $arg" ;;
      "") fail "close pattern must not be empty" ;;
      *) patterns+=("$arg") ;;
    esac
  done

  # Never pick a session on the user's behalf: a wrong guess closes unrelated work.
  if [ -z "$display" ]; then
    sessions=$(live_displays)
    count=$(printf '%s\n' "$sessions" | grep -c . || true)
    if [ "$count" = "0" ]; then
      fail "no live xpra session to close programs in"
    fi
    if [ "$count" != "1" ]; then
      printf 'ERROR: %s live sessions, pass --display :N to choose one, or use close-all\n' "$count" >&2
      printf '%s\n' "$sessions" | sed 's/^/  /' >&2
      exit 2
    fi
    display=$sessions
  fi

  if [ "$all" = 0 ] && [ "${#patterns[@]}" = 0 ]; then
    fail "close needs a program name, a pattern, or --all"
  fi

  if [ "$all" = 1 ]; then
    close_session_programs "$display" "$force" 1
  else
    close_session_programs "$display" "$force" 0 "${patterns[@]}"
  fi
}

# Close every program in every session and then stop those sessions, so nothing
# survives and every port is released.
cmd_close_all() {
  local force=0 arg display sessions stopped=0

  for arg in "$@"; do
    case "$arg" in
      --force) force=1 ;;
      "") ;;
      *) fail "close-all takes no arguments except --force (got: $arg)" ;;
    esac
  done

  sessions=$(live_displays)
  if [ -z "$sessions" ]; then
    printf 'no live xpra sessions\n'
    return 0
  fi

  while IFS= read -r display; do
    [ -n "$display" ] || continue
    close_session_programs "$display" "$force" 1
  done <<< "$sessions"

  while IFS= read -r display; do
    [ -n "$display" ] || continue
    info "stopping xpra session $display"
    "$XPRA" stop "$display" || true
    stopped=$((stopped + 1))
  done <<< "$sessions"

  printf 'SESSIONS_STOPPED=%s\n' "$stopped"
}

# Print "<pid>\t<command>" for the programs running in a display.
# xpra marks its own infrastructure children (Xvfb, ibus) with ignore=True.
child_table() {
  local display=$1
  "$XPRA" info "$display" 2>/dev/null | awk -F'=' '
    /^child\.[0-9]+\./ {
      split($1, key, ".")
      idx = key[2]; field = key[3]
      value = substr($0, index($0, "=") + 1)
      if (field == "pid") pid[idx] = value
      else if (field == "command") cmd[idx] = value
      else if (field == "ignore") ignore[idx] = value
      else if (field == "dead") dead[idx] = value
    }
    END {
      for (i in pid)
        if (ignore[i] == "False" && dead[i] == "False") print pid[i] "\t" cmd[i]
    }
  ' | sort -n
}

format_programs() {
  local pid cmd out=""
  while IFS=$'\t' read -r pid cmd; do
    [ -n "$pid" ] || continue
    out+="$(label_of "$cmd")($pid), "
  done
  printf '%s\n' "${out%, }"
}

# xpra reports a child command as a python tuple repr; turn it back into a
# readable command line and drop the `xpra-run-in.sh DIR` prefix added by run.
label_of() {
  printf '%s\n' "$1" |
    sed -e "s/[()']//g" -e "s/, / /g" -e "s/,$//" -e "s|^.*xpra-run-in\.sh [^ ]* ||"
}

# Quote one argument so python's shlex.split, which xpra applies to the command
# string, reads it back unchanged.
quote_arg() {
  case "$1" in
    "") printf "''" ;;
    *[!A-Za-z0-9_@%+=:,./-]*)
      # Parameter expansion keeps trailing newlines, command substitution would not.
      printf "'%s'" "${1//\'/\'\\\'\'}"
      ;;
    *) printf '%s' "$1" ;;
  esac
}

cmd_run() {
  local display out pid cwd=$PWD cmdline arg
  # A launched program joins a live session: sharing one port is the point of run.
  REUSE_POLICY="always"
  display=$(ensure_display)

  # Pass the whole command as one shlex-quoted string: xpra drops extra argv
  # entries, and splits a string itself.
  cmdline="$(quote_arg "$RUN_IN") $(quote_arg "$cwd")"
  for arg in "$@"; do
    cmdline="$cmdline $(quote_arg "$arg")"
  done

  info "launching in session $display (cwd=$cwd): $*"
  out=$("$XPRA" control "$display" start-child "$cmdline" 2>&1) ||
    fail "xpra refused to launch $*: $out"
  printf '%s\n' "$out" >&2
  pid=$(printf '%s\n' "$out" | sed -n 's/.*pid=\([0-9][0-9]*\).*/\1/p' | head -1)
  printf 'DISPLAY=%s\nCWD=%s\nAPP_PID=%s\n' "$display" "$cwd" "${pid:-unknown}"
}

main() {
  local command="${1:-ensure}"

  case "$command" in
    -h|--help|help) usage; exit 0 ;;
  esac

  XPRA=$(xpra_bin) || missing_xpra

  shift || true
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --host) [ "$#" -ge 2 ] || fail "--host requires a value"; HOST=$2; shift 2 ;;
      --port) [ "$#" -ge 2 ] || fail "--port requires a value"; PORT=$2; shift 2 ;;
      --display) [ "$#" -ge 2 ] || fail "--display requires a value"; DISPLAY_ARG=$2; shift 2 ;;
      --password) [ "$#" -ge 2 ] || fail "--password requires a value"; PASSWORD=$2; shift 2 ;;
      --no-password) AUTH_MODE="none"; shift ;;
      --) shift; break ;;
      *) break ;;
    esac
  done

  if [ "$AUTH_MODE" = "none" ] && [ -n "$PASSWORD" ]; then
    fail "--password and --no-password are mutually exclusive"
  fi

  case "$command" in
    ensure) ensure_session ;;
    run) [ "$#" -gt 0 ] || fail "run requires a command after --"; cmd_run "$@" ;;
    list|ls) cmd_list ;;
    close) cmd_close "$@" ;;
    close-all) cmd_close_all "$@" ;;
    stop) cmd_stop "$@" ;;
    *) usage; fail "unknown command: $command" ;;
  esac
}

main "$@"
