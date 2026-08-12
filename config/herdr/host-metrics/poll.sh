#!/usr/bin/env bash
# Whole-host load + memory → herdr workspace metadata token `$host`.
# Usage: poll.sh --run | --spawn | --once | --stop

set -u

SOURCE_ID="host-metrics"
TOKEN_NAME="host"
INTERVAL_SEC="${HOST_METRICS_INTERVAL_SEC:-5}"
TTL_MS="${HOST_METRICS_TTL_MS:-15000}"

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
STATE_DIR="${HERDR_PLUGIN_STATE_DIR:-$SCRIPT_DIR/.state}"
PIDFILE="$STATE_DIR/host-metrics.pid"
LOCKFILE="$STATE_DIR/host-metrics.lock"
LOGFILE="$STATE_DIR/host-metrics.log"
CPUSTAT_FILE="$STATE_DIR/cpu.stat"

herdr_bin() {
  if [ -n "${HERDR_BIN_PATH:-}" ] && [ -x "${HERDR_BIN_PATH}" ]; then
    printf '%s\n' "${HERDR_BIN_PATH}"
    return
  fi
  command -v herdr
}

log() {
  mkdir -p "$STATE_DIR"
  printf '%s %s\n' "$(date -Iseconds 2>/dev/null || date)" "$*" >>"$LOGFILE"
}

fmt_gb() {
  # $1 = bytes → GiB with one decimal, e.g. 221.5G
  awk -v b="$1" 'BEGIN { printf "%.1fG", b / (1024 * 1024 * 1024) }'
}

# Read aggregate CPU counters from /proc/stat: total idle
# Fields: user nice system idle iowait irq softirq steal ...
read_cpu_stat() {
  awk '/^cpu / {
    idle = $5 + $6
    total = 0
    for (i = 2; i <= NF; i++) total += $i
    print total, idle
    exit
  }' /proc/stat 2>/dev/null
}

# Whole-machine busy% like top: 100 * (1 - Δidle/Δtotal). Uses last sample
# in CPUSTAT_FILE when present; otherwise takes a short 0.5s pair.
cpu_busy_pct() {
  local prev cur t0 i0 t1 i1 dt di pct
  cur=$(read_cpu_stat) || cur=""
  if [ -z "$cur" ]; then
    printf '?'
    return
  fi
  set -- $cur
  t1=$1
  i1=$2
  prev=""
  if [ -f "$CPUSTAT_FILE" ]; then
    prev=$(cat "$CPUSTAT_FILE" 2>/dev/null || true)
  fi
  if [ -n "$prev" ]; then
    set -- $prev
    t0=$1
    i0=$2
  else
    t0=$t1
    i0=$i1
    sleep 0.5
    cur=$(read_cpu_stat) || cur=""
    if [ -z "$cur" ]; then
      printf '?'
      return
    fi
    set -- $cur
    t1=$1
    i1=$2
  fi
  mkdir -p "$STATE_DIR"
  printf '%s %s
' "$t1" "$i1" >"$CPUSTAT_FILE"
  dt=$((t1 - t0))
  di=$((i1 - i0))
  if [ "$dt" -le 0 ] 2>/dev/null; then
    printf '?'
    return
  fi
  pct=$(awk -v dt="$dt" -v di="$di" 'BEGIN {
    p = (1 - di / dt) * 100
    if (p < 0) p = 0
    if (p > 100) p = 100
    printf "%.0f", p
  }')
  printf '%s' "$pct"
}

sample_host_line() {
  local cpu_pct mem_total_kb mem_avail_kb used_b
  cpu_pct=$(cpu_busy_pct)
  mem_total_kb=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null) || mem_total_kb=""
  mem_avail_kb=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo 2>/dev/null) || mem_avail_kb=""
  if [ -z "$mem_total_kb" ] || [ -z "$mem_avail_kb" ]; then
    printf 'CPU: %s%% MEM: ?' "$cpu_pct"
    return
  fi
  used_b=$(( (mem_total_kb - mem_avail_kb) * 1024 ))
  # fmt_gb prints e.g. 222.8G → show as 222.8GB
  printf 'CPU: %s%% MEM: %sB' "$cpu_pct" "$(fmt_gb "$used_b")"
}

workspace_ids() {
  local bin
  bin=$(herdr_bin) || return 1
  # herdr prints one JSON object; extract every workspace_id (may be one line).
  "$bin" workspace list 2>/dev/null | grep -oE '"workspace_id":"[^"]+"' | sed 's/.*:"//;s/"$//'
}

push_once() {
  local bin line id
  bin=$(herdr_bin) || {
    log "herdr not found"
    return 1
  }
  line=$(sample_host_line)
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    if ! "$bin" workspace report-metadata "$id" \
      --source "$SOURCE_ID" \
      --token "${TOKEN_NAME}=${line}" \
      --ttl-ms "$TTL_MS" >/dev/null 2>&1; then
      log "report-metadata failed workspace=$id"
    fi
  done < <(workspace_ids)
}

cmd_stop() {
  local pid
  if [ -f "$PIDFILE" ]; then
    pid=$(cat "$PIDFILE" 2>/dev/null || true)
    if [ -n "${pid:-}" ] && kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
      log "stopped pid=$pid"
    fi
  fi
  rm -f "$PIDFILE"
}

cmd_run() {
  mkdir -p "$STATE_DIR"
  exec 9>"$LOCKFILE"
  if ! flock -n 9; then
    log "already running (lock held)"
    exit 0
  fi
  echo $$ >"$PIDFILE"
  log "run start interval=${INTERVAL_SEC}s ttl_ms=${TTL_MS}"
  trap 'rm -f "$PIDFILE"; exit 0' INT TERM
  while true; do
    push_once || true
    sleep "$INTERVAL_SEC"
  done
}

cmd_spawn() {
  mkdir -p "$STATE_DIR"
  # Always refresh once (works even when a poller is already up).
  push_once || true
  if [ -f "$PIDFILE" ]; then
    pid=$(cat "$PIDFILE" 2>/dev/null || true)
    if [ -n "${pid:-}" ] && kill -0 "$pid" 2>/dev/null; then
      log "spawn skipped; already running pid=$pid"
      exit 0
    fi
  fi
  nohup bash "$SCRIPT_DIR/poll.sh" --run >>"$LOGFILE" 2>&1 &
  log "spawned pid=$!"
}

cmd_once() {
  push_once
}

case "${1:-}" in
  --run) cmd_run ;;
  --spawn) cmd_spawn ;;
  --once) cmd_once ;;
  --stop) cmd_stop ;;
  *)
    printf 'usage: %s --run|--spawn|--once|--stop\n' "$(basename "$0")" >&2
    exit 2
    ;;
esac
