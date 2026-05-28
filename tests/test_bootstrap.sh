#!/usr/bin/env bash
# Verify bootstrap results: symlinks, shell source, idempotency.
set -euo pipefail

PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); printf '  \033[32m✓\033[0m %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  \033[31m✗\033[0m %s\n' "$1"; }

check_link() {
  local path=$1
  if [ -L "$path" ]; then
    pass "$path is a symlink"
  else
    fail "$path is not a symlink"
  fi
}

echo "==> Checking symlinks"
check_link "$HOME/.config/nvim"
check_link "$HOME/.config/wezterm"
check_link "$HOME/.bashrc"
check_link "$HOME/.zshrc"
check_link "$HOME/.tmux.conf"
check_link "$HOME/.tmux.conf.local"

echo "==> Checking shell configs source correctly"
if bash -i -c 'true' 2>/dev/null; then
  pass "bash interactive shell sources ok"
else
  fail "bash interactive shell failed"
fi

if command -v zsh &>/dev/null; then
  if zsh -i -c 'true' 2>/dev/null; then
    pass "zsh interactive shell sources ok"
  else
    fail "zsh interactive shell failed"
  fi
else
  echo "  (skipped zsh: not installed)"
fi

echo "==> Checking idempotency (no backup files from second run)"
backups=$(find "$HOME" -maxdepth 3 -name "*.backup.*" 2>/dev/null | head -5)
if [ -n "$backups" ]; then
  fail "backup files found (not idempotent): $backups"
else
  pass "no backup files created"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
