#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: get-litellm.sh

Install or upgrade the LiteLLM proxy CLI via uv.

Requirements:
  - uv

Example:
  ./get-litellm.sh
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
fi

if [ "$#" -ne 0 ]; then
    usage >&2
    exit 1
fi

if ! command -v uv >/dev/null 2>&1; then
    printf 'Missing required command: uv\n' >&2
    exit 1
fi

exec uv tool install --upgrade --python 3.13 'litellm[proxy]'
