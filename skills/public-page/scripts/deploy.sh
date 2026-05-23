#!/usr/bin/env bash
set -euo pipefail

INPUT=""
PROVIDER="auto"
TTL="72h"
PIN=""

usage() {
  cat <<'USAGE'
Usage:
  deploy.sh <index.html|static-dir> [options]

Options:
  --provider auto|pagedrop|aired  Provider to use (default: auto)
  --ttl 72h|1d|86400              TTL target
  --pin PIN                       Aired PIN protection
  -h, --help                      Show help

Publishes a static page/site to a temporary public URL with automatic expiry.
Auto provider order: pagedrop -> aired.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --provider)
      [ "$#" -ge 2 ] || { echo "Error: --provider requires a value" >&2; exit 2; }
      PROVIDER="$2"
      shift 2
      ;;
    --ttl)
      [ "$#" -ge 2 ] || { echo "Error: --ttl requires a value" >&2; exit 2; }
      TTL="$2"
      shift 2
      ;;
    --pin)
      [ "$#" -ge 2 ] || { echo "Error: --pin requires a value" >&2; exit 2; }
      PIN="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      if [ -n "$INPUT" ]; then
        echo "Error: only one input path is supported" >&2
        exit 2
      fi
      INPUT="$1"
      shift
      ;;
  esac
done

case "$PROVIDER" in
  auto|pagedrop|aired) ;;
  *) echo "Error: unsupported provider: $PROVIDER" >&2; exit 2 ;;
esac

if [ -z "$INPUT" ]; then
  usage >&2
  exit 2
fi

command -v curl >/dev/null 2>&1 || { echo "Error: curl is required" >&2; exit 127; }
command -v python3 >/dev/null 2>&1 || { echo "Error: python3 is required" >&2; exit 127; }

TMP_DIR=""
cleanup() {
  if [ -n "$TMP_DIR" ] && [ -d "$TMP_DIR" ]; then
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

INPUT_KIND=""
HTML_PATH=""
ZIP_PATH=""

prepare_input() {
  if [ -f "$INPUT" ]; then
    case "$INPUT" in
      *.html|*.htm)
        INPUT_KIND="html"
        HTML_PATH="$INPUT"
        ;;
      *)
        echo "Error: file input must be .html or .htm" >&2
        exit 2
        ;;
    esac
  elif [ -d "$INPUT" ]; then
    [ -f "$INPUT/index.html" ] || { echo "Error: static directory must contain index.html at its root" >&2; exit 2; }
    if ! command -v zip >/dev/null 2>&1; then
      echo "Error: zip is required for static directory deployment" >&2
      exit 127
    fi
    TMP_DIR=$(mktemp -d)
    INPUT_KIND="directory"
    ZIP_PATH="$TMP_DIR/site.zip"
    (cd "$INPUT" && zip -qr "$ZIP_PATH" .)
  else
    echo "Error: input path does not exist: $INPUT" >&2
    exit 2
  fi
}

bytes_of() {
  wc -c < "$1" | tr -d '[:space:]'
}

check_size() {
  local path=$1 max_bytes=$2 label=$3 bytes
  bytes=$(bytes_of "$path")
  if [ "$bytes" -gt "$max_bytes" ]; then
    echo "Error: $label is $bytes bytes; limit is $max_bytes bytes" >&2
    return 1
  fi
}

ttl_to_seconds() {
  python3 - "$TTL" <<'PY'
import re
import sys
s = sys.argv[1].strip().lower()
if s.isdigit():
    print(int(s))
    raise SystemExit
m = re.fullmatch(r"(\d+)([hdm])", s)
if not m:
    raise SystemExit(f"Error: unsupported TTL format: {s}; use seconds, 24h, or 1d")
n = int(m.group(1))
unit = m.group(2)
print(n * {"h": 3600, "d": 86400, "m": 2592000}[unit])
PY
}

ttl_to_pagedrop() {
  python3 - "$TTL" <<'PY'
import re
import sys
s = sys.argv[1].strip().lower()
if s.isdigit():
    seconds = int(s)
    hours = max(1, (seconds + 3599) // 3600)
    print(f"{hours}h")
    raise SystemExit
m = re.fullmatch(r"(\d+)([hdm])", s)
if not m:
    raise SystemExit(f"Error: unsupported TTL format: {s}; use seconds, 24h, or 1d")
print(s)
PY
}

emit_result() {
  local provider=$1 raw_json=$2
  python3 - "$provider" "$raw_json" <<'PY'
import json
import sys
provider = sys.argv[1]
raw = sys.argv[2]
try:
    data = json.loads(raw)
except json.JSONDecodeError:
    print(raw)
    raise SystemExit("Error: provider response was not JSON")

if provider == "pagedrop":
    payload = data.get("data") or {}
    url = payload.get("url")
    expires = payload.get("expiresAt")
    token = payload.get("deleteToken")
elif provider == "aired":
    url = data.get("url")
    expires = data.get("expiresAt")
    token = data.get("update_token")
else:
    raise SystemExit(f"Error: unknown provider: {provider}")

if not url:
    print(json.dumps(data, ensure_ascii=False, indent=2))
    raise SystemExit("Error: provider response did not include a URL")

print(json.dumps({
    "provider": provider,
    "url": url,
    "expires_at": expires,
    "token": token,
    "raw": data,
}, ensure_ascii=False, indent=2))
PY
}

deploy_pagedrop() {
  local endpoint="https://pagedrop.dev/api/v1/sites" response ttl_pd
  ttl_pd=$(ttl_to_pagedrop)
  if [ "$INPUT_KIND" = "html" ]; then
    check_size "$HTML_PATH" $((5 * 1024 * 1024)) "PageDrop HTML" || return 1
    response=$(python3 - "$HTML_PATH" "$ttl_pd" <<'PY' | curl -sS -X POST "https://pagedrop.dev/api/v1/sites" -H "Content-Type: application/json" --data-binary @-
import json
import sys
from pathlib import Path
html = Path(sys.argv[1]).read_text()
ttl = sys.argv[2]
print(json.dumps({"html": html, "ttl": ttl}))
PY
)
  else
    check_size "$ZIP_PATH" $((10 * 1024 * 1024)) "PageDrop ZIP" || return 1
    response=$(curl -sS -X POST "$endpoint" -F "file=@$ZIP_PATH" -F "ttl=$ttl_pd")
  fi
  if echo "$response" | grep -q '"error"'; then
    echo "$response" >&2
    return 1
  fi
  emit_result pagedrop "$response"
}

deploy_aired() {
  local ttl_seconds response
  ttl_seconds=$(ttl_to_seconds)
  if [ "$INPUT_KIND" != "html" ]; then
    echo "Aired fallback in this script supports single HTML files only" >&2
    return 1
  fi
  check_size "$HTML_PATH" $((2 * 1024 * 1024)) "Aired HTML" || return 1
  response=$(python3 - "$HTML_PATH" "$ttl_seconds" "$PIN" <<'PY' | curl -sS -X POST "https://aired.sh/api/publish" -H "Content-Type: application/json" --data-binary @-
import json
import sys
from pathlib import Path
html = Path(sys.argv[1]).read_text()
ttl = int(sys.argv[2])
pin = sys.argv[3]
payload = {"html": html, "ttl": ttl}
if pin:
    payload["pin"] = pin
print(json.dumps(payload))
PY
)
  if echo "$response" | grep -q '"error"'; then
    echo "$response" >&2
    return 1
  fi
  emit_result aired "$response"
}

try_provider() {
  local provider=$1
  echo "Trying provider: $provider" >&2
  case "$provider" in
    pagedrop) deploy_pagedrop ;;
    aired) deploy_aired ;;
    *) echo "Error: unknown provider: $provider" >&2; return 1 ;;
  esac
}

prepare_input

if [ "$PROVIDER" != "auto" ]; then
  try_provider "$PROVIDER"
  exit $?
fi

errors=""
for provider in pagedrop aired; do
  out_file=$(mktemp)
  err_file=$(mktemp)
  if try_provider "$provider" >"$out_file" 2>"$err_file"; then
    cat "$out_file"
    rm -f "$out_file" "$err_file"
    exit 0
  fi
  echo "Provider failed: $provider" >&2
  cat "$err_file" >&2
  errors="$errors\n[$provider]\n$(cat "$err_file")"
  rm -f "$out_file" "$err_file"
done

echo "Error: all providers failed" >&2
printf '%b\n' "$errors" >&2
exit 1
