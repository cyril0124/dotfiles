#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
CONFIG_PATH="$SCRIPT_DIR/config.yaml"
HOST="${HOST:-0.0.0.0}"
PORT="${PORT:-4000}"

if ! command -v litellm >/dev/null 2>&1; then
    printf 'Missing required command: litellm\n' >&2
    printf 'Run %s first to install LiteLLM.\n' "$SCRIPT_DIR/get-litellm.sh" >&2
    exit 1
fi

if [ ! -f "$CONFIG_PATH" ]; then
    printf 'Missing config file: %s\n' "$CONFIG_PATH" >&2
    exit 1
fi

NUM_WORKERS=4

exec litellm --config "$CONFIG_PATH" --host "$HOST" --port "$PORT" --num_workers "$NUM_WORKERS" "$@"
