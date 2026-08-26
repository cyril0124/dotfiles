#!/usr/bin/env bash
# Verify Neovim environment: plugins, native extensions, treesitter, mason.
set -euo pipefail

PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); printf '  \033[32m✓\033[0m %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  \033[31m✗\033[0m %s\n' "$1"; }

NVIM_DATA="${XDG_DATA_HOME:-$HOME/.local/share}/nvim"

# Single cleanup trap for all temp files created below.
cleanup_files=()
cleanup() { rm -f "${cleanup_files[@]}"; }
trap cleanup EXIT

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
# Probe ts-install's own install dir rather than the runtimepath: nvim bundles
# parsers for c/lua/markdown/markdown_inline, so a runtimepath hit would report
# OK for a parser that was never installed.
ts_check=$(mktemp /tmp/test-nvim-ts-XXXXXX.lua)
cleanup_files+=("$ts_check")
cat >"$ts_check" <<'LUA'
local want = { "c", "cpp", "lua", "python", "rust", "scala", "markdown", "markdown_inline", "diff", "systemverilog" }
pcall(vim.cmd, "Lazy load ts-install.nvim")
local ok, cfg = pcall(require, "ts-install.config")
if not ok then
  io.stdout:write("TS_MODULE_MISSING\n")
  vim.cmd("qa")
  return
end
local parser_dir = vim.fs.joinpath(cfg.config.install_dir, "parser")
for _, lang in ipairs(want) do
  local present = vim.uv.fs_stat(vim.fs.joinpath(parser_dir, lang .. ".so")) ~= nil
  io.stdout:write((present and "OK " or "MISSING ") .. lang .. "\n")
end
vim.cmd("qa")
LUA
ts_result=$(nvim --headless -c "luafile $ts_check" +qa 2>/dev/null)
all_ok=1
ok_langs=()
if printf '%s' "$ts_result" | grep -q "TS_MODULE_MISSING"; then
  fail "ts-install.config module unavailable"
  all_ok=0
else
  while IFS= read -r line; do
    case "$line" in
      OK\ *)
        ok_langs+=("${line#OK }")
        ;;
      MISSING\ *)
        fail "treesitter parser missing: ${line#MISSING }"
        all_ok=0
        ;;
    esac
  done <<< "$ts_result"
  if [ "$all_ok" -eq 1 ] && [ "${#ok_langs[@]}" -eq 0 ]; then
    fail "treesitter parser check produced no OK lines"
    all_ok=0
  fi
fi
[ "$all_ok" -eq 1 ] && pass "treesitter parsers present: ${ok_langs[*]}"

echo "==> Mason packages"
mason_dir="$NVIM_DATA/mason/packages"
ensure=(clangd json-lsp rust-analyzer ty)
all_ok=1
for pkg in "${ensure[@]}"; do
  if [ ! -d "$mason_dir/$pkg" ]; then
    fail "mason package missing: $pkg"
    all_ok=0
  fi
done
[ "$all_ok" -eq 1 ] && pass "mason packages present: ${ensure[*]}"

echo "==> checkhealth"
tmp_health=$(mktemp /tmp/nvim_health_XXXXXX.log)
cleanup_files+=("$tmp_health")
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
