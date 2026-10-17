#!/usr/bin/env bash
# Whole-host CPU/MEM line for the Herdr tab bar ([ui] tab_bar_right).
# Prints one line, e.g. "CPU: 29% MEM: 36%"; unknown values print "?".
# CPU is 100 * (1 - Δidle/Δtotal) between invocations, the same figure top shows.

set -u

STAT_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/herdr-tab-host.cpu"

# Read aggregate CPU counters from /proc/stat: total and idle.
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

cpu_busy_pct() {
  local cur prev t0 i0 t1 i1 dt di
  cur=$(read_cpu_stat)
  if [ -z "$cur" ]; then
    printf '?'
    return
  fi
  set -- $cur
  t1=$1
  i1=$2

  prev=""
  if [ -f "$STAT_FILE" ]; then
    prev=$(cat "$STAT_FILE" 2>/dev/null || true)
  fi
  if [ -n "$prev" ]; then
    set -- $prev
    t0=$1
    i0=$2
  else
    # No previous sample: take a short pair so the first call still answers.
    t0=$t1
    i0=$i1
    sleep 0.5
    cur=$(read_cpu_stat)
    if [ -z "$cur" ]; then
      printf '?'
      return
    fi
    set -- $cur
    t1=$1
    i1=$2
  fi

  mkdir -p "${STAT_FILE%/*}" 2>/dev/null || true
  printf '%s %s\n' "$t1" "$i1" >"$STAT_FILE" 2>/dev/null || true

  dt=$((t1 - t0))
  di=$((i1 - i0))
  if [ "$dt" -le 0 ] 2>/dev/null; then
    printf '?'
    return
  fi
  awk -v dt="$dt" -v di="$di" 'BEGIN {
    p = (1 - di / dt) * 100
    if (p < 0) p = 0
    if (p > 100) p = 100
    printf "%.0f", p
  }'
}

mem_used_pct() {
  local total avail
  total=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null)
  avail=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo 2>/dev/null)
  if [ -z "${total:-}" ] || [ -z "${avail:-}" ] || [ "$total" -le 0 ] 2>/dev/null; then
    printf '?'
    return
  fi
  awk -v t="$total" -v a="$avail" 'BEGIN {
    p = (t - a) / t * 100
    if (p < 0) p = 0
    if (p > 100) p = 100
    printf "%.0f", p
  }'
}

printf 'CPU: %s%% MEM: %s%%\n' "$(cpu_busy_pct)" "$(mem_used_pct)"
