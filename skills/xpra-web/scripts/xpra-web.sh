#!/usr/bin/env bash
set -euo pipefail

# Serve Linux X11 GUI programs from this machine over TCP, so they can be viewed
# in a browser (xpra html5 client) or with a local `xpra attach`.
#
# One session holds many GUI programs. `ensure` and `run` both start a fresh
# session on a fresh port by default, and join a live one only when
# `--display`/`--port` names it, so every program gets its own port unless the
# caller asks to share one.

HOST="127.0.0.1"
PORT="0"
DISPLAY_ARG=""
PASSWORD=""
PASSWORD_SOURCE=""
AUTH_MODE="file"
SSL_CERT=""
SSL_KEY=""
SSL_SERVER_VERIFY_MODE="${XPRA_WEB_SSL_SERVER_VERIFY_MODE:-required}"
SSL_CHECK_HOSTNAME="${XPRA_WEB_SSL_CHECK_HOSTNAME:-yes}"
ALLOW_INSECURE=0
WAIT_SECONDS="${XPRA_WEB_WAIT_SECONDS:-10}"
# Every probe of a live session is bounded: a busy-looping server leaves its
# control channel unanswered for minutes, which would otherwise hang the command
# that asked about it.
PROBE_SECONDS="${XPRA_WEB_PROBE_SECONDS:-5}"
STOP_SECONDS="${XPRA_WEB_STOP_SECONDS:-10}"

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
RUN_IN="$SCRIPT_DIR/xpra-run-in.sh"

# Each display gets its own password file. XDG_RUNTIME_DIR is per-boot and
# private to the user, which is the right lifetime for session credentials.
PASSWORD_DIR="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/xpra-web-$USER"

usage() {
  cat <<'USAGE'
Usage:
  xpra-web.sh ensure [options]          Start a network-visible xpra session
  xpra-web.sh run [options] -- CMD ...  Start or name a session, then launch CMD inside it
  xpra-web.sh list | ls                 Show live sessions, ports, windows, programs and directories
  xpra-web.sh doctor                    Check that a browser client can complete a handshake
  xpra-web.sh close PATTERN | --all     Close matching programs, keep the session alive
  xpra-web.sh close-all [--force]       Close every program everywhere, then stop every session
  xpra-web.sh stop :N | --all           Stop one named session, or every session
  xpra-web.sh help                      Show this message

  --all                 With stop: stop every live session. With close: every program
  --force               With close/close-all: SIGKILL programs that ignore SIGTERM

Options:
  --host HOST          Bind address (default: 127.0.0.1)
  --port PORT          Bind port; 0 lets the kernel pick one (default: 0)
  --display :N         Use display :N instead of the first free one
  --password PW        Password for the TCP bind (default: random for each session)
  --password-file FILE Read the password from FILE instead of the command line
  --no-password        Bind with no password at all (auth=none)
  --ssl-cert FILE      PEM certificate for HTTPS/WSS on the same TCP port
  --ssl-key FILE       PEM private key for the certificate
  --allow-insecure     Allow a non-loopback listener without WSS and authentication

--password, --password-file and --no-password are mutually exclusive.

ensure and run start a new session on a free port by default. A live session is
joined only when the request names it: --display names that live session, or
--port N names the port it holds. A named session must also match --host and the
auth mode, so a different program gets its own port unless you ask to share one.

Output: KEY=value lines (SESSION, DISPLAY, BIND, PORT, BROWSER, ATTACH, AUTH,
PASSWORD, PASSWORD_FILE, WEB, ...).
USAGE
}

info() { printf '==> %s\n' "$1" >&2; }
fail() { printf 'ERROR: %s\n' "$1" >&2; exit 1; }

xpra_bin() {
  if command -v xpra >/dev/null 2>&1; then
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

# Run a command with a hard time limit. Missing timeout is an error, not a reason
# to remove the bound and risk hanging every later command.
bounded_for() {
  local seconds=$1
  shift
  if ! command -v timeout >/dev/null 2>&1; then
    printf 'ERROR: timeout is required for bounded xpra commands\n' >&2
    return 127
  fi
  timeout -k 2s "$seconds" "$@"
}

bounded() {
  bounded_for "$PROBE_SECONDS" "$@"
}

# Query displays without converting a failed listing into an empty session list.
query_displays() {
  local listing
  listing=$(bounded "$XPRA" list 2>/dev/null) || return 1
  printf '%s\n' "$listing" | sed -n 's/.*LIVE session at \(:[0-9][0-9]*\).*/\1/p' | sort -u
}

# Best-effort listing used by display selection and inventory output.
live_displays() {
  query_displays 2>/dev/null || true
}

# xpra info for one display, bounded by PROBE_SECONDS. Prints nothing and fails
# when the session does not answer in time.
xpra_info() {
  bounded "$XPRA" info "$1" 2>/dev/null || return 1
}

# "live" when the session answers, "unresponsive" when xpra has it registered
# but its control channel stayed silent, "absent" when xpra does not know it.
session_state() {
  local display=$1
  live_displays | grep -qx -- "$display" || { printf 'absent\n'; return 0; }
  if xpra_info "$display" >/dev/null; then
    printf 'live\n'
  else
    printf 'unresponsive\n'
  fi
}

# Print "<host> <port>" for the first TCP listener of a display, or fail.
tcp_listener() {
  local display=$1 line parsed
  line=$(xpra_info "$display" | grep -m1 '^network.sockets.tcp.listeners=' || true)
  [ -n "$line" ] || return 1
  parsed=$(printf '%s\n' "$line" | sed -n "s/.*(('\([^']*\)', '\([0-9][0-9]*\)').*/\1 \2/p")
  [ -n "$parsed" ] || return 1
  printf '%s\n' "$parsed"
}

# First display number that is free for both xpra and the X socket directory.
pick_display() {
  local used n live known
  live=$(query_displays) || return 1
  known=$(bounded "$XPRA" displays 2>/dev/null) || return 1
  used=$(
    {
      printf '%s\n' "$live"
      printf '%s\n' "$known" | sed -n 's/.*\(:[0-9][0-9]*\).*/\1/p'
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

# The Xvfb command xpra will run, taken from its own effective configuration.
configured_xvfb() {
  local config
  config=$(bounded "$XPRA" showconfig 2>/dev/null) || return 1
  printf '%s\n' "$config" | awk -F"'" '/^xvfb +\(used\)/{print $2; exit}'
}

# Fail before starting when the configured Xvfb cannot run: xpra otherwise waits
# out its whole startup timeout and leaves a traceback in server.log.
xvfb_is_runnable() {
  local bin
  bin=$(configured_xvfb) || return 1
  [ -n "$bin" ] || return 0
  bin=${bin%% *}
  case "$bin" in
    /*) [ -x "$bin" ] ;;
    *) command -v "$bin" >/dev/null 2>&1 ;;
  esac
}

require_xvfb() {
  xvfb_is_runnable && return 0
  fail "xpra's configured Xvfb is not runnable: $(configured_xvfb | awk '{print $1}')
point xvfb at a working binary in ~/.config/xpra/xpra.conf, keeping the extensions xpra needs:
  xvfb = /path/to/Xvfb +extension GLX +extension Composite +extension RANDR +extension RENDER -screen 0 1920x1080x24 -nolisten tcp -noreset -dpi 96x96"
}

# The html5 web root xpra serves the browser client from.
configured_html() {
  local config
  config=$(bounded "$XPRA" showconfig 2>/dev/null) || return 1
  printf '%s\n' "$config" | awk -F"'" '/^html +\(used\)/{print $2; exit}'
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
# The TLS probe skips certificate verification but never sends credentials.
web_status() {
  local bind_host=$1 port=$2 transport=$3 probe code scheme="http"
  local -a tls_options=()
  command -v curl >/dev/null 2>&1 || { printf 'unknown\n'; return 0; }
  if [ "$transport" = "wss" ]; then
    scheme="https"
    tls_options=(-k)
  fi
  for probe in "$bind_host" 127.0.0.1; do
    [ "$probe" = "0.0.0.0" ] && probe=127.0.0.1
    code=$(curl -s -o /dev/null -m 5 -w '%{http_code}' "${tls_options[@]}" "$scheme://$probe:$port/" || true)
    [ "$code" = "200" ] && { printf 'yes\n'; return 0; }
  done
  printf 'no\n'
}

is_loopback_host() {
  case "$1" in
    127.0.0.1|::1|localhost) return 0 ;;
    *) return 1 ;;
  esac
}

requested_transport() {
  if [ -n "$SSL_CERT" ]; then
    printf 'wss\n'
  else
    printf 'ws\n'
  fi
}

session_transport() {
  # Accept joined and separate SSL certificate arguments in server.argv.
  local argv
  argv=$(xpra_info "$1" | grep -m1 '^server.argv=' || true)
  case "$argv" in
    *--ssl-cert=*|*--ssl-cert\',*) printf 'wss\n' ;;
    *) printf 'ws\n' ;;
  esac
}

validate_access_request() {
  if [ -n "$SSL_CERT" ] || [ -n "$SSL_KEY" ]; then
    [ -n "$SSL_CERT" ] && [ -n "$SSL_KEY" ] || fail "--ssl-cert and --ssl-key must be used together for WSS"
    [ -r "$SSL_CERT" ] || fail "cannot read SSL certificate: $SSL_CERT"
    [ -r "$SSL_KEY" ] || fail "cannot read SSL private key: $SSL_KEY"
  fi
  is_loopback_host "$HOST" && return 0
  [ "$ALLOW_INSECURE" = "1" ] && return 0
  [ -z "$SSL_CERT" ] && fail "non-loopback access requires WSS (--ssl-cert and --ssl-key) or explicit --allow-insecure"
  [ "$AUTH_MODE" = "none" ] && fail "non-loopback access without a password requires explicit --allow-insecure"
  return 0
}

warn_if_insecure() {
  local bind_host=$1 transport=$2
  is_loopback_host "$bind_host" && return 0
  [ "$transport" = "wss" ] && return 0
  printf 'WARNING: %s is unencrypted; the HTML5 client may refuse its password. Use WSS or an SSH tunnel.\n' "$bind_host" >&2
}

print_result() {
  local session=$1 display=$2 bind_host=$3 port=$4 auth=$5 password=$6 password_file=$7 transport=$8
  local host url_host scheme="http" attach_scheme="tcp"
  host=$(hostname -f 2>/dev/null || hostname)
  url_host=$host
  if is_loopback_host "$bind_host"; then
    url_host=127.0.0.1
  fi
  if [ "$transport" = "wss" ]; then
    scheme="https"
    attach_scheme="wss"
  fi
  printf 'SESSION=%s\n' "$session"
  printf 'DISPLAY=%s\n' "$display"
  printf 'BIND=%s:%s\n' "$bind_host" "$port"
  printf 'PORT=%s\n' "$port"
  printf 'TRANSPORT=%s\n' "$transport"
  printf 'BROWSER=%s://%s:%s/\n' "$scheme" "$url_host" "$port"
  if [ "$auth" = "file" ]; then
    printf 'ATTACH=xpra attach --password-file=%s %s://%s:%s\n' "$password_file" "$attach_scheme" "$host" "$port"
  else
    printf 'ATTACH=xpra attach %s://%s:%s\n' "$attach_scheme" "$host" "$port"
  fi
  printf 'LOCAL=%s://127.0.0.1:%s/\n' "$scheme" "$port"
  printf 'SSH=ssh -L %s:127.0.0.1:%s %s@%s\n' "$port" "$port" "$USER" "$host"
  printf 'AUTH=%s\n' "$auth"
  if [ -n "$password" ]; then
    printf 'PASSWORD=%s\n' "$password"
  fi
  if [ "$auth" = "file" ]; then
    printf 'PASSWORD_FILE=%s\n' "$password_file"
  fi
  printf 'WEB=%s\n' "$(web_status "$bind_host" "$port" "$transport")"
}

password_file_for_display() {
  printf '%s/%s/password\n' "$PASSWORD_DIR" "${1#:}"
}

random_password() {
  # 24 bytes become a 48-character hexadecimal password.
  od -An -N24 -tx1 /dev/urandom | tr -d ' \n'
}

# Write credentials atomically and fail closed when their permissions cannot be set.
# Xpra re-reads the file when its mtime changes, so this also works on a live session.
prepare_password() {
  local file=$1 mode=$2 dir tmp
  case "$file" in
    "$PASSWORD_DIR"/*) ;;
    *) fail "refusing to rewrite a password file outside $PASSWORD_DIR: $file" ;;
  esac

  dir=${file%/*}
  mkdir -p -- "$dir" || fail "cannot create $dir"
  chmod 700 -- "$PASSWORD_DIR" "$dir" || fail "cannot restrict password directory permissions under $PASSWORD_DIR"

  if [ "$mode" = "created" ] || [ -n "$PASSWORD" ] || [ -n "$PASSWORD_SOURCE" ] || [ ! -f "$file" ]; then
    tmp=$(mktemp "$dir/.password.XXXXXX") || fail "cannot create a temporary password file in $dir"
    if ! chmod 600 -- "$tmp"; then
      rm -f -- "$tmp"
      fail "cannot restrict temporary password file permissions: $tmp"
    fi
    if [ -n "$PASSWORD_SOURCE" ]; then
      if ! cat -- "$PASSWORD_SOURCE" > "$tmp"; then
        rm -f -- "$tmp"
        fail "cannot read password file: $PASSWORD_SOURCE"
      fi
    elif [ -n "$PASSWORD" ]; then
      if ! printf '%s' "$PASSWORD" > "$tmp"; then
        rm -f -- "$tmp"
        fail "cannot write temporary password file: $tmp"
      fi
    else
      if ! random_password > "$tmp"; then
        rm -f -- "$tmp"
        fail "cannot generate a random password"
      fi
    fi
    if [ ! -s "$tmp" ]; then
      rm -f -- "$tmp"
      fail "password must not be empty"
    fi
    if ! mv -f -- "$tmp" "$file"; then
      rm -f -- "$tmp"
      fail "cannot install password file: $file"
    fi
  fi
  chmod 600 -- "$file" || fail "cannot restrict password file permissions: $file"
}

# Read the authentication module used by the session's TCP bind.
session_auth() {
  local argv auth
  argv=$(xpra_info "$1" | grep -m1 '^server.argv=' || true)
  auth=$(printf '%s\n' "$argv" | sed -n 's/.*,auth=\([A-Za-z0-9_-][A-Za-z0-9_-]*\).*/\1/p' | head -1)
  printf '%s\n' "${auth:-none}"
}

# A live session is reusable only when its listener matches the request on every
# axis. Host, port, auth mode and transport are fixed at startup, so a mismatch
# means a new session, never a silently different one.
listener_matches() {
  local display=$1 listener=$2
  [ "${listener%% *}" = "$HOST" ] || return 1
  if [ "$PORT" != "0" ] && [ "${listener##* }" != "$PORT" ]; then
    return 1
  fi
  [ "$(session_auth "$display")" = "$AUTH_MODE" ] || return 1
  [ "$(session_transport "$display")" = "$(requested_transport)" ] || return 1
  return 0
}

# An unauthenticated listener on a routable address is open to everyone who can
# reach it, which the caller must include in the access report.
warn_if_unauthenticated() {
  local bind_host=$1 port=$2
  case "$bind_host" in
    127.0.0.1|::1|localhost) return 0 ;;
  esac
  printf '%s\n' "WARNING: $bind_host:$port has no password, so anyone who can reach it has full access." >&2
  printf '%s\n' "Use --host 127.0.0.1 to keep it local, or keep the port on a trusted network." >&2
}

# The password file a running file-authenticated session uses, when visible.
session_password_file() {
  local argv
  argv=$(xpra_info "$1" | grep -m1 '^server.argv=' || true)
  printf '%s\n' "$argv" | sed -n \
    -e "s/.*,auth=file,filename=\([^,')]*\).*/\1/p" \
    -e "s/.*,auth=file(filename=\([^,')]*\).*/\1/p" | head -1
}

# Find a reusable session, or start one. Prints the result block.
ensure_session() {
  local display="$DISPLAY_ARG" session="reused" listener="" bind_host="" port=""
  local requested_live=0 skipped=0 bind_opt="" may_reuse=1 reason=""
  local password_file="" display_password="" transport
  local -a ssl_args=()
  transport=$(requested_transport)
  validate_access_request
  if [ "$transport" = "wss" ]; then
    ssl_args=(--ssl=auto "--ssl-cert=$SSL_CERT" "--ssl-key=$SSL_KEY")
  fi

  # A fresh session is the default: only a named display or port joins a live one.
  if [ "$PORT" = "0" ] && [ -z "$DISPLAY_ARG" ]; then
    may_reuse=0
    reason="default is a fresh session; pass --port N or --display :N to reuse one"
  fi

  if [ -n "$display" ]; then
    case "$(session_state "$display")" in
    live)
      requested_live=1
      listener=$(tcp_listener "$display" || true)
      if [ -n "$listener" ] && ! listener_matches "$display" "$listener"; then
        fail "session $display listens on ${listener%% *}:${listener##* } (auth=$(session_auth "$display"), transport=$(session_transport "$display")); that does not match host=$HOST, port=$PORT, auth=$AUTH_MODE, transport=$transport. Stop $display first, or change the matching options."
      fi
      ;;
    unresponsive)
      fail "session $display is registered but its control channel did not answer within ${PROBE_SECONDS}s; a spinning server blocks every client handshake. Stop it (server.pid $(server_pid "$display" || echo unknown)) or name another display."
      ;;
    esac
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
    if [ "$auth" = "file" ] && [ -z "$pw_file" ]; then
      fail "cannot determine the password file for $display; pass a session created by this script"
    fi
    if [ "$auth" = "file" ] && { [ -n "$PASSWORD" ] || [ -n "$PASSWORD_SOURCE" ] || [ ! -f "$pw_file" ]; }; then
      prepare_password "$pw_file" "reused"
      info "password file written to $pw_file; the running session uses it on the next connection"
    fi
    print_result "$session" "$display" "$bind_host" "$port" "$auth" "" "$pw_file" "$(session_transport "$display")"
    [ "$auth" = "none" ] && warn_if_unauthenticated "$bind_host" "$port"
    warn_if_insecure "$bind_host" "$(session_transport "$display")"
    return 0
  fi

  if [ "$requested_live" = 1 ]; then
    fail "session $display is live but has no TCP listener; stop $display first, or choose another --display"
  fi

  if [ -z "$display" ]; then
    display=$(pick_display) || fail "cannot find a free display in :10-:99 (xpra list/displays failed or all are in use)"
  fi

  session="created"
  require_xvfb
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
    password_file=$(password_file_for_display "$display")
    prepare_password "$password_file" "created"
    bind_opt="$HOST:$PORT,auth=file,filename=$password_file"
    info "starting xpra session $display on $HOST:$PORT (password in $password_file)"
  fi
  if ! "$XPRA" start "$display" \
    --bind-tcp="$bind_opt" \
    "${ssl_args[@]}" \
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
    print_result "$session" "$display" "$bind_host" "$port" "none" "" "" "$transport"
    warn_if_unauthenticated "$bind_host" "$port"
  else
    if [ -z "$PASSWORD_SOURCE" ]; then
      display_password=$(cat "$password_file") || fail "cannot read password file: $password_file"
    fi
    print_result "$session" "$display" "$bind_host" "$port" "file" "$display_password" "$password_file" "$transport"
  fi
  warn_if_insecure "$bind_host" "$transport"
}

# Resolve the display to launch in, starting a session when the request names none.
ensure_display() {
  local out
  # ensure_session reports refusal through its exit status; without this the
  # failure dies in the subshell and the launch runs with an empty display.
  out=$(ensure_session) || return 1
  printf '%s\n' "$out" >&2
  printf '%s\n' "$out" | sed -n 's/^DISPLAY=//p'
}

cmd_list() {
  local display listener windows programs dirs found=0 all_windows
  # xpra lists every display at once; keep the rows that belong to this one.
  all_windows=$(bounded "$XPRA" list-windows 2>/dev/null || true)
  while IFS= read -r display; do
    found=1
    if [ "$(session_state "$display")" = "unresponsive" ]; then
      printf '%s\ttcp=unresponsive\twindows=unresponsive\tprograms=unresponsive\tcwd=unresponsive\tnote=no answer from the session within %ss\n' "$display" "$PROBE_SECONDS"
      continue
    fi
    listener=$(tcp_listener "$display" || true)
    [ -n "$listener" ] || listener="none"
    windows=$(
      printf '%s\n' "$all_windows" |
        awk -v d="$display" '$1 == d { sub(/^[^ \t]+[ \t]+[^ \t]+[ \t]*/, ""); print }' |
        paste -sd ', ' -
    ) || windows=""
    programs=$(child_table "$display" | format_programs || true)
    dirs=$(dirs_of "$display")
    printf '%s\ttcp=%s\twindows=%s\tprograms=%s\tcwd=%s\n' \
      "$display" "${listener// /:}" "${windows:-none}" "${programs:-none}" "${dirs:-none}"
  done < <(live_displays)
  [ "$found" = 1 ] || printf 'no live xpra sessions\n'
}

# Say what a destructive command is about to take down, before it does.
report_inventory() {
  local display=$1 table
  if ! table=$(child_table "$display"); then
    printf 'about to stop %s, programs=unknown (inventory query failed)\n' "$display" >&2
    return 0
  fi
  if [ -n "$table" ]; then
    printf '%s\n' "about to stop $display, running programs:" >&2
    printf '%s\n' "$table" | while IFS=$'\t' read -r pid cmd; do
      printf '  %s (pid %s)\n' "$(label_of "$cmd")" "$pid" >&2
    done
  else
    printf '%s\n' "about to stop $display, no programs running" >&2
  fi
}

cleanup_session_password() {
  local display=$1 dir
  dir="$PASSWORD_DIR/${display#:}"
  [ -f "$dir/password" ] && rm -f -- "$dir/password"
  [ -d "$dir" ] && rmdir -- "$dir" 2>/dev/null || true
}

# Stop 1 display and verify both the command result and its disappearance.
stop_session() {
  local display=$1 status remaining deadline
  info "stopping xpra session $display"
  if bounded_for "$STOP_SECONDS" "$XPRA" stop "$display"; then
    status=0
  else
    status=$?
  fi
  if [ "$status" -ne 0 ]; then
    printf 'STOP_FAILED=%s\n' "$display"
    printf 'ERROR: stopping %s failed with exit %d (limit %ss)\n' "$display" "$status" "$STOP_SECONDS" >&2
    return 1
  fi

  deadline=$((SECONDS + PROBE_SECONDS))
  while [ "$SECONDS" -lt "$deadline" ]; do
    if ! remaining=$(query_displays); then
      printf 'STOP_FAILED=%s\n' "$display"
      printf 'ERROR: cannot verify that %s stopped: xpra list failed\n' "$display" >&2
      return 1
    fi
    if ! printf '%s\n' "$remaining" | grep -qx -- "$display"; then
      cleanup_session_password "$display"
      printf 'SESSION_STOPPED=%s\n' "$display"
      return 0
    fi
    sleep 0.2
  done

  printf 'STOP_FAILED=%s\n' "$display"
  printf 'ERROR: %s is still registered after xpra stop\n' "$display" >&2
  return 1
}

cmd_stop() {
  local display="" all=0 arg sessions stopped=0 failed=0
  for arg in "$@"; do
    case "$arg" in
      --all) all=1 ;;
      "") ;;
      *) display=$arg ;;
    esac
  done

  if [ "$all" = 1 ]; then
    sessions=$(query_displays) || fail "cannot list sessions before stop --all"
    if [ -z "$sessions" ]; then
      printf 'no live xpra sessions\nSESSIONS_STOPPED=0\nSESSIONS_FAILED=0\n'
      return 0
    fi
    while IFS= read -r display; do
      report_inventory "$display"
    done <<< "$sessions"
    while IFS= read -r display; do
      if stop_session "$display"; then
        stopped=$((stopped + 1))
      else
        failed=$((failed + 1))
      fi
    done <<< "$sessions"
    printf 'SESSIONS_STOPPED=%s\nSESSIONS_FAILED=%s\n' "$stopped" "$failed"
    if [ "$failed" -gt 0 ]; then
      return 1
    fi
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
  stop_session "$display"
}

# Close programs inside one session, leaving the session and its port alive.
# Args: DISPLAY FORCE ALL [PATTERN ...]
close_session_programs() {
  local display=$1 force=$2 all=$3
  shift 3
  local -a patterns=("$@") pids=() labels=() alive=()
  local table pid cmd label pattern i deadline

  if ! table=$(child_table "$display"); then
    printf 'DISPLAY=%s\nCLOSED=0\nSTILL_RUNNING=unknown\n' "$display"
    printf 'ERROR: cannot query programs in session %s\n' "$display" >&2
    return 1
  fi
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
  local force=0 arg display sessions stopped=0 failed=0

  for arg in "$@"; do
    case "$arg" in
      --force) force=1 ;;
      "") ;;
      *) fail "close-all takes no arguments except --force (got: $arg)" ;;
    esac
  done

  sessions=$(query_displays) || fail "cannot list sessions before close-all"
  if [ -z "$sessions" ]; then
    printf 'no live xpra sessions\nSESSIONS_STOPPED=0\nSESSIONS_FAILED=0\n'
    return 0
  fi

  while IFS= read -r display; do
    [ -n "$display" ] || continue
    close_session_programs "$display" "$force" 1 || true
  done <<< "$sessions"

  while IFS= read -r display; do
    [ -n "$display" ] || continue
    if stop_session "$display"; then
      stopped=$((stopped + 1))
    else
      failed=$((failed + 1))
    fi
  done <<< "$sessions"

  printf 'SESSIONS_STOPPED=%s\nSESSIONS_FAILED=%s\n' "$stopped" "$failed"
  if [ "$failed" -gt 0 ]; then
    return 1
  fi
  return 0
}

# Print "<pid>\t<command>" for the programs running in a display.
# xpra marks its own infrastructure children (Xvfb, ibus) with ignore=True.
child_table() {
  local display=$1
  xpra_info "$display" | awk -F'=' '
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

# Working directory of one process, empty when procfs does not expose it.
cwd_of() {
  readlink "/proc/$1/cwd" 2>/dev/null || true
}

# Working directories of a display's programs, deduplicated, comma separated.
# Two programs launched with `run` from the same directory collapse into one entry.
dirs_of() {
  local display=$1 pid dir out="" seen=" "
  while IFS=$'\t' read -r pid _; do
    [ -n "$pid" ] || continue
    dir=$(cwd_of "$pid")
    [ -n "$dir" ] || continue
    case "$seen" in *" $dir "*) continue ;; esac
    seen="$seen$dir "
    out+="$dir, "
  done < <(child_table "$display")
  printf '%s\n' "${out%, }"
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
  # Like ensure, a launched program gets a session of its own unless the request
  # names a live one to join with --display/--port.
  display=$(ensure_display) || exit 1

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

# CPU time of one process, in clock ticks, read from procfs.
proc_cpu_ticks() {
  sed -e 's/^[0-9]* (.*) //' "/proc/$1/stat" 2>/dev/null | awk '{print $12 + $13}'
}

# CPU percent of one process, sampled over one second. `ps` reports a lifetime
# average, which stays low on a server that only recently started spinning.
cpu_percent() {
  local pid=$1 before after hz
  before=$(proc_cpu_ticks "$pid")
  [ -n "$before" ] || return 1
  sleep 1
  after=$(proc_cpu_ticks "$pid")
  [ -n "$after" ] || return 1
  hz=$(getconf CLK_TCK 2>/dev/null || echo 100)
  printf '%s\n' $(((after - before) * 100 / hz))
}

# Times this session dropped a client during the protocol handshake. A spinning
# server accepts the TCP connection, receives the hello and never answers.
handshake_timeouts() {
  local log count
  if log=$(server_log "$1"); then
    count=$(grep -c 'connection timed out' "$log" 2>/dev/null || true)
  else
    count=0
  fi
  printf '%s\n' "${count:-0}"
}

html5_version() {
  local html=$1
  sed -n 's/.*<h5>Version \([^<]*\)<\/h5>.*/\1/p' "$html/connect.html" 2>/dev/null | head -1
}

html5_min_protocol() {
  local html=$1
  sed -n 's/^const MIN_PROTOCOL_VERSION = \[\([0-9][0-9]*\), *\([0-9][0-9]*\)\].*/\1.\2/p' \
    "$html/js/Client.js" 2>/dev/null | head -1
}

version_at_least() {
  local actual=${1#xpra v} required=$2 actual_major actual_minor required_major required_minor
  actual=${actual%%[^0-9.]*}
  IFS=. read -r actual_major actual_minor _ <<< "$actual"
  IFS=. read -r required_major required_minor _ <<< "$required"
  [[ "$actual_major" =~ ^[0-9]+$ && "$actual_minor" =~ ^[0-9]+$ ]] || return 1
  [[ "$required_major" =~ ^[0-9]+$ && "$required_minor" =~ ^[0-9]+$ ]] || return 1
  if [ "$actual_major" -gt "$required_major" ]; then
    return 0
  fi
  if [ "$actual_major" -lt "$required_major" ]; then
    return 1
  fi
  [ "$actual_minor" -ge "$required_minor" ]
}

# Check the same WebSocket protocol path used by the HTML5 client, with authentication.
active_handshake() {
  local display=$1 listener=$2 auth=$3 transport=$4
  local host port password_file uri
  local -a args=(id)
  host=${listener%% *}
  port=${listener##* }
  [ "$host" = "0.0.0.0" ] && host=127.0.0.1
  uri="$transport://$host:$port/"

  case "$auth" in
    file)
      password_file=$(session_password_file "$display")
      [ -n "$password_file" ] && [ -r "$password_file" ] || return 1
      args+=("--password-file=$password_file")
      ;;
    none) ;;
    *) return 1 ;;
  esac
  if [ "$transport" = "wss" ]; then
    args+=("--ssl-server-verify-mode=$SSL_SERVER_VERIFY_MODE" "--ssl-check-hostname=$SSL_CHECK_HOSTNAME")
  fi
  args+=("$uri")
  bounded "$XPRA" "${args[@]}" >/dev/null 2>&1
}

# The two pieces a browser client needs from this machine: an Xvfb xpra can
# drive, and a compatible html5 web root it serves the client from.
doctor_environment() {
  local xvfb html xvfb_bin xpra_version html_version min_protocol status=0

  xvfb=$(configured_xvfb || true)
  xvfb_bin=${xvfb%% *}
  if xvfb_is_runnable; then
    printf 'CHECK xvfb=%s status=ok\n' "${xvfb_bin:-none}"
  else
    printf 'CHECK xvfb=%s status=missing\n' "${xvfb_bin:-none}"
    status=1
  fi

  xpra_version=$(bounded "$XPRA" --version 2>/dev/null || true)
  printf 'CHECK xpra-version=%s status=info\n' "${xpra_version#xpra v}"

  html=$(configured_html || true)
  if [ -n "$html" ] && [ -d "$html" ]; then
    html_version=$(html5_version "$html")
    min_protocol=$(html5_min_protocol "$html")
    printf 'CHECK html=%s status=ok\n' "$html"
    printf 'CHECK html5-version=%s status=info protocol-min=%s\n' \
      "${html_version:-unknown}" "${min_protocol:-unknown}"
    if [ -n "$min_protocol" ] && ! version_at_least "$xpra_version" "$min_protocol"; then
      printf 'CHECK html5-compatibility=bad server=%s required=%s\n' "$xpra_version" "$min_protocol"
      status=1
    fi
  else
    printf 'CHECK html=%s status=missing\n' "${html:-none}"
    printf 'CHECK html5-version=unknown status=missing\n'
    status=1
  fi

  return "$status"
}

# Active handshakes and HTTP responses determine readiness. CPU and historical
# timeouts remain diagnostic context because neither proves a current failure.
doctor_sessions() {
  local display pid cpu cpu_text listener transport web timeouts problem_list
  local displays status=0 found=0
  local -a problems

  if ! displays=$(query_displays); then
    printf 'SESSIONS=unknown reason=xpra-list-failed\n'
    return 1
  fi
  if [ -z "$displays" ]; then
    printf 'SESSIONS=0 reason=no-live-sessions\n'
    return 1
  fi

  while IFS= read -r display; do
    [ -n "$display" ] || continue
    found=1
    pid=$(server_pid "$display" || true)

    if [ "$(session_state "$display")" = "unresponsive" ]; then
      printf 'SESSION %s status=unresponsive server=%s note=control channel silent for %ss\n' \
        "$display" "${pid:-unknown}" "$PROBE_SECONDS"
      status=1
      continue
    fi

    listener=$(tcp_listener "$display" || true)
    transport=$(session_transport "$display")
    timeouts=$(handshake_timeouts "$display")
    if cpu=$(cpu_percent "$pid"); then
      cpu_text="${cpu}%"
    else
      cpu_text="unknown"
    fi

    problems=()
    web="unknown"
    if [ -z "$listener" ]; then
      problems+=("no-listener")
    else
      web=$(web_status "${listener%% *}" "${listener##* }" "$transport")
      if ! active_handshake "$display" "$listener" "$(session_auth "$display")" "$transport"; then
        problems+=("handshake-failed")
      fi
      [ "$web" = "yes" ] || problems+=("web-$web")
    fi

    if [ "${#problems[@]}" -eq 0 ]; then
      printf 'SESSION %s status=ok listener=%s transport=%s cpu=%s web=yes handshake=id historical_timeouts=%s\n' \
        "$display" "${listener// /:}" "$transport" "$cpu_text" "$timeouts"
      continue
    fi

    printf -v problem_list '%s,' "${problems[@]}"
    printf 'SESSION %s status=bad listener=%s transport=%s cpu=%s web=%s historical_timeouts=%s problems=%s\n' \
      "$display" "${listener:-none}" "$transport" "$cpu_text" "$web" "$timeouts" "${problem_list%,}"
    status=1
  done <<< "$displays"

  [ "$found" = "1" ] || status=1
  return "$status"
}

# Report what a browser client meets, and fail when any of it is missing.
# The HTML5 files arrive over HTTP(S), and the active probe checks the WebSocket
# transport and authentication that the client will use.
cmd_doctor() {
  local status=0

  doctor_environment || status=1
  doctor_sessions || status=1

  if [ "$status" = 0 ]; then
    printf 'DOCTOR=ok\n'
  else
    printf 'DOCTOR=failed\n'
  fi
  return "$status"
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
      --password-file) [ "$#" -ge 2 ] || fail "--password-file requires a value"; PASSWORD_SOURCE=$2; shift 2 ;;
      --no-password) AUTH_MODE="none"; shift ;;
      --ssl-cert) [ "$#" -ge 2 ] || fail "--ssl-cert requires a value"; SSL_CERT=$2; shift 2 ;;
      --ssl-key) [ "$#" -ge 2 ] || fail "--ssl-key requires a value"; SSL_KEY=$2; shift 2 ;;
      --allow-insecure) ALLOW_INSECURE=1; shift ;;
      --) shift; break ;;
      *) break ;;
    esac
  done

  if [ "$AUTH_MODE" = "none" ] && { [ -n "$PASSWORD" ] || [ -n "$PASSWORD_SOURCE" ]; }; then
    fail "--password, --password-file and --no-password are mutually exclusive"
  fi
  if [ -n "$PASSWORD" ] && [ -n "$PASSWORD_SOURCE" ]; then
    fail "--password and --password-file are mutually exclusive"
  fi

  case "$command" in
    ensure) ensure_session ;;
    run) [ "$#" -gt 0 ] || fail "run requires a command after --"; cmd_run "$@" ;;
    list|ls) cmd_list ;;
    doctor) cmd_doctor ;;
    close) cmd_close "$@" ;;
    close-all) cmd_close_all "$@" ;;
    stop) cmd_stop "$@" ;;
    *) usage; fail "unknown command: $command" ;;
  esac
}

main "$@"
