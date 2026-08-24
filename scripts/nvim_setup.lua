-- Neovim headless setup: restore plugins, install treesitter parsers and Mason LSP servers.
--
-- Designed to be deterministic and idempotent in headless mode:
--   * Treesitter parsers are installed through ts-install with skip.installed,
--     so already-built parsers are never recompiled and no interactive prompt
--     can block a session that has no stdin.
--   * Async Mason operations are driven synchronously via vim.wait() instead of
--     vim.defer_fn + "+qa", avoiding event-loop races that cause hangs.
--
-- Exit codes: 0 on success, 1 on any failure (via cquit).

local TS_PARSERS = {
  "c", "cpp", "lua", "python", "rust",
  "scala", "markdown", "markdown_inline", "diff", "systemverilog",
}

local MASON_PACKAGES = {
  "emmylua_ls", "clangd", "json-lsp", "rust-analyzer", "ty",
}

-- Per-operation timeouts (ms). Generous because CI runners compile parsers and
-- download LSP binaries (clangd/rust-analyzer are hundreds of MB).
local TS_TIMEOUT_MS = 10 * 60 * 1000
local MASON_REFRESH_TIMEOUT_MS = 2 * 60 * 1000
local MASON_INSTALL_TIMEOUT_MS = 15 * 60 * 1000

local function log(msg)
  io.stderr:write(("[nvim_setup] %s\n"):format(msg))
  io.stderr:flush()
end

local function fail(msg)
  vim.api.nvim_err_writeln("[nvim_setup] FAIL: " .. msg)
  vim.cmd("cquit 1")
end

-- 1. Restore plugins to the versions pinned in lazy-lock.json.
log("restoring plugins (Lazy! restore)")
do
  local ok, err = pcall(vim.cmd, "Lazy! restore")
  if not ok then
    fail("Lazy restore failed: " .. tostring(err))
  end
end

-- ts-install is lazy-loaded (event = BufReadPost); force it so its setup() has
-- run (which also puts the install dir on the runtimepath) and the install API
-- is available. nvim-treesitter comes along as a dependency.
do
  local ok, err = pcall(vim.cmd, "Lazy load ts-install.nvim")
  if not ok then
    fail("failed to load ts-install.nvim: " .. tostring(err))
  end
end

-- 2. Install treesitter parsers (only the missing ones).
do
  local async = require("ts-install.async")
  local install = require("ts-install.install")
  local install_dir = require("ts-install.config").config.install_dir

  log("treesitter: ensuring parsers: " .. table.concat(TS_PARSERS, " "))
  local task = async.run(install.install, TS_PARSERS, { skip = { installed = true } })
  local ok, err = pcall(task.wait, task, TS_TIMEOUT_MS)
  if not ok then
    log("treesitter: install raised an error (" .. tostring(err) .. "), verifying results")
  end

  -- Verify every parser is actually present now. Probe ts-install's own install
  -- dir, not the runtimepath: nvim bundles parsers for c/lua/markdown and those
  -- would mask a failed install.
  local missing = {}
  for _, lang in ipairs(TS_PARSERS) do
    if not vim.uv.fs_stat(vim.fs.joinpath(install_dir, "parser", lang .. ".so")) then
      table.insert(missing, lang)
    end
  end
  if #missing > 0 then
    fail("treesitter parsers failed to install: " .. table.concat(missing, " "))
  end
  log("treesitter: ready: " .. table.concat(TS_PARSERS, " "))
end

-- 3. Install Mason LSP servers (refresh registry, then install missing).
do
  local ok_reg, registry = pcall(require, "mason-registry")
  if not ok_reg then
    fail("mason-registry unavailable: " .. tostring(registry))
  end

  -- Refresh the registry index synchronously.
  local refresh_done = false
  local refresh_ok = false
  registry.refresh(function(success)
    refresh_ok = success ~= false
    refresh_done = true
  end)
  if not vim.wait(MASON_REFRESH_TIMEOUT_MS, function() return refresh_done end, 200) then
    fail("mason registry refresh timed out")
  end
  if not refresh_ok then
    fail("mason registry refresh failed")
  end
  log("mason: registry refreshed")

  -- Resolve packages and kick off installs for the ones not present.
  local pending = 0
  local failed = {}
  local installed = {}

  for _, name in ipairs(MASON_PACKAGES) do
    local ok_pkg, pkg = pcall(registry.get_package, name)
    if not ok_pkg then
      table.insert(failed, name .. " (not found in registry)")
    elseif pkg:is_installed() then
      table.insert(installed, name)
    else
      pending = pending + 1
      log("mason: installing " .. name)
      pkg:install():once("closed", function()
        if not pkg:is_installed() then
          table.insert(failed, name)
        else
          table.insert(installed, name)
        end
        pending = pending - 1
      end)
    end
  end

  if pending > 0 then
    if not vim.wait(MASON_INSTALL_TIMEOUT_MS, function() return pending == 0 end, 500) then
      fail("mason install timed out; still pending: " .. tostring(pending))
    end
  end

  if #failed > 0 then
    fail("mason packages failed: " .. table.concat(failed, ", "))
  end
  log("mason: ready: " .. table.concat(installed, " "))
end

log("neovim setup complete")
vim.cmd("qa")
