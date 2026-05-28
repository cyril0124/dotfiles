#!/usr/bin/env bash
# Verify Neovim environment: plugins, native extensions, treesitter, mason.
set -euo pipefail

PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); printf '  \033[32m✓\033[0m %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  \033[31m✗\033[0m %s\n' "$1"; }

NVIM_DATA="${XDG_DATA_HOME:-$HOME/.local/share}/nvim"

echo "==> Lazy restore"
tmp_lazy_script=$(mktemp /tmp/test-nvim-lazy-XXXXXX.lua)
tmp_ts_script=$(mktemp /tmp/test-nvim-ts-XXXXXX.lua)
tmp_fff_script=$(mktemp /tmp/test-nvim-fff-XXXXXX.lua)
tmp_mason_script=$(mktemp /tmp/test-nvim-mason-XXXXXX.lua)
trap 'rm -f "$tmp_lazy_script" "$tmp_ts_script" "$tmp_fff_script" "$tmp_mason_script" /tmp/nvim_health.log' EXIT
cat >"$tmp_lazy_script" <<'LUA'
local function fail(msg)
  vim.api.nvim_err_writeln(msg)
  vim.cmd("cquit 1")
end
local ok, err = pcall(vim.cmd, "Lazy! restore")
if not ok then
  fail(err)
end
vim.cmd("qa")
LUA
if nvim --headless -c "luafile $tmp_lazy_script" +qa 2>&1; then
  pass "Lazy restore"
else
  fail "Lazy restore"
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
parsers=(c cpp lua python rust scala markdown markdown_inline diff verilog)
cat >"$tmp_ts_script" <<'LUA'
local function fail(msg)
  vim.api.nvim_err_writeln(msg)
  vim.cmd("cquit 1")
end
local ok, err = pcall(vim.cmd, "TSInstallSync c cpp lua python rust scala markdown markdown_inline diff verilog")
if not ok then
  fail(err)
end
vim.cmd("qa")
LUA
if nvim --headless -c "luafile $tmp_ts_script" +qa 2>&1; then
  pass "treesitter parsers installed: ${parsers[*]}"
else
  fail "treesitter parsers install failed"
fi

echo "==> fff binary"
cat >"$tmp_fff_script" <<'LUA'
local function fail(msg)
  vim.api.nvim_err_writeln(msg)
  vim.cmd("cquit 1")
end
local ok, err = pcall(function()
  require("fff.download").download_or_build_binary()
end)
if not ok then
  fail(err)
end
vim.cmd("qa")
LUA
if nvim --headless -c "luafile $tmp_fff_script" +qa 2>&1; then
  pass "fff binary downloaded"
else
  fail "fff binary download failed"
fi

echo "==> Mason ensure_installed"
cat >"$tmp_mason_script" <<'LUA'
local function fail(msg)
  vim.api.nvim_err_writeln(msg)
  vim.cmd("cquit 1")
end

vim.defer_fn(function()
  local ok_reg, registry = pcall(require, "mason-registry")
  if not ok_reg then
    fail("mason-registry unavailable")
  end
  registry.refresh(function()
    local ensure = { "emmylua_ls", "clangd", "json-lsp", "rust-analyzer", "ty" }
    local pending = #ensure
    local failed = {}
    local function finish()
      if pending ~= 0 then
        return
      end
      if #failed > 0 then
        fail("mason failures: " .. table.concat(failed, ", "))
      else
        vim.cmd("qa")
      end
    end
    if pending == 0 then
      finish()
      return
    end
    for _, name in ipairs(ensure) do
      local ok_pkg, pkg = pcall(registry.get_package, name)
      if not ok_pkg then
        table.insert(failed, name .. " (not found)")
        pending = pending - 1
        finish()
      elseif pkg:is_installed() then
        pending = pending - 1
        finish()
      else
        pkg:install():once("closed", function()
          if not pkg:is_installed() then
            table.insert(failed, name)
          end
          pending = pending - 1
          finish()
        end)
      end
    end
  end)
end, 1000)
LUA
if nvim --headless -c "luafile $tmp_mason_script" +qa 2>&1; then
  pass "mason ensure_installed"
else
  fail "mason ensure_installed"
fi

echo "==> checkhealth"
nvim --headless "+checkhealth" "+w! /tmp/nvim_health.log" +qa 2>/dev/null || true
if [ -f /tmp/nvim_health.log ] && grep -qiE "^.*ERROR" /tmp/nvim_health.log; then
  fail "checkhealth reported errors:"
  grep -iE "^.*ERROR" /tmp/nvim_health.log | sed 's/^/    /'
else
  pass "checkhealth clean"
fi
rm -f /tmp/nvim_health.log

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
