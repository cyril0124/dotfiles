#!/usr/bin/env bash
# Install OpenCode binary if not already present.

set -euo pipefail

if command -v opencode &>/dev/null; then
    echo "OpenCode is already installed: $(command -v opencode)"
    exit 0
fi

if command -v brew &>/dev/null; then
    brew install anomalyco/tap/opencode
elif command -v npm &>/dev/null; then
    npm i -g opencode-ai@latest
elif command -v curl &>/dev/null; then
    curl -fsSL https://opencode.ai/install | bash
else
    echo "ERROR: Cannot install OpenCode: no supported package manager found (brew, npm, or curl)" >&2
    exit 1
fi

echo "OpenCode installed"
