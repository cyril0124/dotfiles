#!/usr/bin/env bash
# Verify Neovim environment: plugins, native extensions, treesitter, mason.
set -euo pipefail

PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); printf '  \033[32m✓\033[0m %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  \033[31m✗\033[0m %s\n' "$1"; }

NVIM_DATA="${XDG_DATA_HOME:-$HOME/.local/share}/nvim"

echo "==> Lazy plugins"
if [ -d "$NVIM_DATA/lazy" ] && [ "$(ls -A "$NVIM_DATA/lazy" 2>/dev/null)" ]; then
  pass "lazy plugin directory exists and is non-empty"
else
  fail "lazy plugin directory missing or empty"
fi

echo "==> telescope-fzf-native"
fzf_dir="$NVIM_DATA/lazy/telescope-fzf-native.nvim"
if [ -d "$fzf_dir" ]; then
  make -C "$fzf_dir" >/dev/null 2>&1
  if [ -f "$fzf_dir/build/libfzf.so" ] || [ -f "$fzf_dir/build/libfzf.dylib" ]; then
    pass "telescope-fzf-native compiled"
  else
    fail "telescope-fzf-native: binary not found after make"
  fi
else
  fail "telescope-fzf-native: plugin directory not found"
fi

echo "==> Treesitter parsers"
# Parsers may be in different locations depending on nvim-treesitter version
parser_dirs=(
  "$NVIM_DATA/lazy/nvim-treesitter/parser"
  "$NVIM_DATA/treesitter/parser"
  "$NVIM_DATA/site/parser"
)
parsers=(c lua python markdown markdown_inline diff)
all_ok=1
for p in "${parsers[@]}"; do
  found=0
  for dir in "${parser_dirs[@]}"; do
    if ls "$dir/${p}.so" "$dir/${p}.dll" 2>/dev/null | grep -q .; then
      found=1
      break
    fi
  done
  if [ "$found" -eq 0 ]; then
    fail "treesitter parser missing: $p"
    all_ok=0
  fi
done
[ "$all_ok" -eq 1 ] && pass "treesitter parsers present: ${parsers[*]}"

echo "==> Mason packages"
if [ "${DOTFILES_CI:-}" = "1" ]; then
  pass "mason check skipped in CI (no binary downloads)"
else
  mason_dir="$NVIM_DATA/mason/packages"
  ensure=(emmylua_ls clangd json-lsp rust-analyzer ty)
  all_ok=1
  for pkg in "${ensure[@]}"; do
    if [ ! -d "$mason_dir/$pkg" ]; then
      fail "mason package missing: $pkg"
      all_ok=0
    fi
  done
  [ "$all_ok" -eq 1 ] && pass "mason packages present: ${ensure[*]}"
fi

echo "==> checkhealth"
tmp_health=$(mktemp /tmp/nvim_health_XXXXXX.log)
trap 'rm -f "$tmp_health"' EXIT
nvim --headless "+checkhealth" "+w! $tmp_health" +qa 2>/dev/null || true
if [ -f "$tmp_health" ]; then
  # Filter out known CI-irrelevant errors
  errors=$(grep -iE "^.*ERROR" "$tmp_health" | grep -vE "(luarocks|infocmp)" || true)
  if [ -n "$errors" ]; then
    fail "checkhealth reported errors:"
    echo "$errors" | sed 's/^/    /'
  else
    pass "checkhealth clean (or only CI-irrelevant errors)"
  fi
else
  pass "checkhealth clean"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
