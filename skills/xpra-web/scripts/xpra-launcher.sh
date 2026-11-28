#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "$0")/xpra-web.sh"

action=$1
dir=$2
shift 2
command_args=()
force=0
port_override=
if [[ $action == open ]]; then
  working_dir=$1
  shift
  if [[ ${1:-} =~ ^[0-9]+$ ]]; then
    # Previously generated wrappers pass an argument count before the saved command.
    command_arg_count=$1
    shift
    command_args=("${@:1:command_arg_count}")
    shift "$command_arg_count"
  else
    launcher_options=()
    while (($#)) && [[ $1 != -- ]]; do
      launcher_options+=("$1")
      shift
    done
    (($#)) || fail 'missing -- before the saved command'
    shift
    command_args=("$@")
    set -- "${launcher_options[@]}"
  fi
fi

for option in "$@"; do
  case $option in
    -h|--help)
      case $action in
        open)
          printf '%s\n' 'Usage: open.sh [--port PORT] [--force] [-h|--help]' \
            'Start the saved Xpra session and program.' \
            'Reuses the first successful port, or picks a free port if it is busy.' \
            '  --port PORT  Use this port for this open (0 selects a free port).' \
            '  --force      Restart the recorded session, closing its programs.' \
            '               Kill owned listeners blocking the saved or specified loopback port.' ;;
        status) printf '%s\n' 'Usage: status.sh [-h|--help]' 'Show session state, connection details and running programs.' ;;
        close) printf '%s\n' 'Usage: close.sh [-h|--help]' 'Stop the recorded session and its programs, and release the port.' ;;
      esac
      exit 0 ;;
  esac
done

if [[ $action == open ]]; then
  cd -- "$working_dir"
  HOST=${XPRA_LAUNCH_HOST:-127.0.0.1}
  PORT=${XPRA_LAUNCH_PORT:-0}
  AUTH_MODE=${XPRA_LAUNCH_AUTH:-file}
  SSL_CERT=${XPRA_LAUNCH_CERT:-}
  SSL_KEY=${XPRA_LAUNCH_KEY:-}
  ALLOW_INSECURE=${XPRA_LAUNCH_INSECURE:-0}
  PASSWORD_SOURCE=${XPRA_LAUNCH_PASSWORD_FILE:-}
  if [[ ${XPRA_LAUNCH_PROMPT:-} == yes ]]; then
    read -rs -p 'Session password: ' PASSWORD </dev/tty || fail 'cannot read session password'
    printf '\n' >&2
    [[ -n $PASSWORD ]] || fail 'empty password'
  fi
  while (($#)); do
    case $1 in
      --port)
        [[ ${2:-} =~ ^(0|[1-9][0-9]{0,4})$ ]] && (( $2 <= 65535 )) || fail '--port requires 0 to 65535'
        port_override=$2
        shift 2 ;;
      --force) force=1; shift ;;
      *) fail "unknown option: $1" ;;
    esac
  done
else
  [[ $action == close || $action == status ]] || fail "unknown launcher: $action"
  (($# == 0)) || fail "usage: $action.sh"
fi

# Displays can be recycled. Match the recorded identity before acting on one.
recorded_session_is_live() {
  local identity_key expected_identity displays identity
  [[ -f $state ]] || return 1
  read -r display identity_key < "$state" || fail "cannot read $state"
  [[ $display =~ ^:[0-9]+$ ]] || fail "invalid display in $state"
  if [[ $identity_key =~ ^uuid=[a-fA-F0-9-]+$ ]]; then
    expected_identity=$identity_key
  elif [[ $identity_key =~ ^xpra-web-[0-9a-f-]+$ ]]; then
    expected_identity="session-name=$identity_key"
  else
    fail "invalid session record: $state"
  fi

  displays=$(query_displays) || fail 'cannot list sessions'
  grep -Fxq "$display" <<< "$displays" || return 1
  identity=$(bounded "$XPRA" id "$display") || fail "cannot identify $display"
  grep -Fxq "$expected_identity" <<< "$identity"
}

print_running_status() {
  local display=$1 listener port programs host browser_host scheme=http
  listener=$(tcp_listener "$display") || fail "cannot read TCP listener for $display"
  port=${listener##* }
  programs=$(child_table "$display" | format_programs) || fail "cannot list programs on $display"
  host=$(hostname -f 2>/dev/null || hostname)
  browser_host=$host
  if is_loopback_host "${listener%% *}"; then browser_host=127.0.0.1; fi
  if [[ $(session_transport "$display") == wss ]]; then scheme=https; fi

  printf 'STATUS=running\nDISPLAY=%s\nPORT=%s\nBROWSER=%s://%s:%s/\n' "$display" "$port" "$scheme" "$browser_host" "$port"
  printf 'SSH=ssh -L %s:127.0.0.1:%s %s@%s\nPROGRAMS=%s\n' "$port" "$port" "$USER" "$host" "${programs:-none}"
}

XPRA=$(xpra_bin) || missing_xpra
state=$dir/.session
live=0
if recorded_session_is_live; then
  live=1
  if [[ $action == status ]]; then
    print_running_status "$display"
    exit 0
  fi
  if [[ ! -e $dir/.port ]] && listener=$(tcp_listener "$display"); then
    remember_launcher_port "$dir" "${listener##* }"
  fi
elif [[ $action == status ]]; then
  printf 'STATUS=stopped\n'
  exit 0
fi

if [[ $action == open ]]; then
  validate_access_request
  if [[ -n $port_override ]]; then
    PORT=$port_override
  elif [[ -e $dir/.port ]]; then
    read -r PORT < "$dir/.port" || fail "cannot read $dir/.port"
    [[ $PORT =~ ^[1-9][0-9]{0,4}$ ]] && (( PORT <= 65535 )) || fail "invalid port in $dir/.port"
  fi
  (( !force )) || [[ $PORT != 0 ]] || fail '--force requires a saved port or a non-zero --port'
  if (( live && !force )); then
    fail "already open on $display; run close.sh first or use --force"
  fi
fi

if (( live )); then
  cmd_stop "$display"
fi
rm -f -- "$state"
[[ $action == open ]] || exit 0

release_port() {
  [[ $HOST == 127.0.0.1 ]] || fail '--force currently requires a 127.0.0.1 listener'
  command -v lsof >/dev/null || fail 'releasing an occupied port requires lsof'
  # Only loopback and wildcard listeners can block this IPv4 loopback bind.
  listeners=$(lsof -w -nP -a -u "$(id -u)" -iTCP:"$PORT" -sTCP:LISTEN -Fpn) || fail "cannot identify an owned listener on $HOST:$PORT"
  mapfile -t pids < <(awk -v port="$PORT" '/^p/{pid=substr($0,2)} $0=="n*:"port || $0=="n127.0.0.1:"port || $0=="n0.0.0.0:"port {print pid}' <<< "$listeners" | sort -u)
  ((${#pids[@]})) || fail "no matching listener on $HOST:$PORT"
  info "releasing $HOST:$PORT (SIGKILL to PID ${pids[*]})"
  kill -KILL -- "${pids[@]}" || fail "cannot release $HOST:$PORT"
  local deadline=$((SECONDS + 3))
  until port_is_free "$HOST" "$PORT"; do
    (( SECONDS < deadline )) || fail "cannot release $HOST:$PORT"
    sleep 0.1
  done
}

DISPLAY_ARG=$(pick_display) || fail 'cannot find a free display'
bind_status=0
if [[ $PORT != 0 ]]; then
  port_is_free "$HOST" "$PORT" || bind_status=$?
fi
if (( bind_status == 1 )); then
  if (( force )); then
    release_port
  elif [[ -z $port_override ]]; then
    info "$HOST:$PORT is occupied; using a free port for this session"
    PORT=0
  else
    fail "cannot bind $HOST:$PORT; use --port 0 or --force"
  fi
elif (( bind_status != 0 )); then
  fail "cannot bind $HOST:$PORT"
fi

name=xpra-web-$(< /proc/sys/kernel/random/uuid)
SESSION_NAME_ARGS=("--session-name=$name")
printf '%s %s\n' "$DISPLAY_ARG" "$name" > "$state.tmp"
mv -- "$state.tmp" "$state"
LAUNCHER_DIR=$dir
ensure_session
printf 'LAUNCHER_DIR=%s\n' "$LAUNCHER_DIR"
if ((${#command_args[@]})); then launch_program "$DISPLAY_ARG" "${command_args[@]}"; fi
