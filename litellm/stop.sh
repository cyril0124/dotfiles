#!/usr/bin/env bash

set -euo pipefail

LITELLM_BIN="$(command -v litellm || true)"

if [ -z "$LITELLM_BIN" ]; then
    printf 'No litellm executable found in PATH. Nothing to stop.\n' >&2
    exit 0
fi

pattern="$LITELLM_BIN"

if ! pgrep -af "$pattern" >/dev/null 2>&1; then
    printf 'No LiteLLM processes are running.\n'
    exit 0
fi

pkill -f "$pattern"

for _ in 1 2 3 4 5; do
    if ! pgrep -af "$pattern" >/dev/null 2>&1; then
        printf 'Stopped all LiteLLM processes.\n'
        exit 0
    fi
    sleep 1
done

printf 'Timed out waiting for LiteLLM processes to exit.\n' >&2
pgrep -af "$pattern" >&2
exit 1
