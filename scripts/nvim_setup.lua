-- Neovim headless setup: restore plugins, install treesitter parsers and Mason LSP servers.
--
-- Designed to be deterministic and idempotent in headless mode:
--   * Treesitter parsers are filtered through has_parser() so we never trigger
--     nvim-treesitter's interactive "reinstall? y/n" prompt (fn.input), which
--     hangs forever without a stdin in headless mode.
--   * Async Mason operations are driven synchronously via vim.wait() instead of
--     vim.defer_fn + "+qa", avoiding event-loop races that cause hangs.
--
-- Exit codes: 0 on success, 1 on any failure (via cquit).

local TS_PARSERS = {
  "c", "cpp", "lua", "python", "rust",
  "scala", "markdown", "markdown_inline", "diff", "verilog",
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

-- nvim-treesitter is lazy-loaded (event = BufReadPost); force it so the
-- TSInstallSync command and parsers module are available.
do
  local ok, err = pcall(vim.cmd, "Lazy load nvim-treesitter")
  if not ok then
    fail("failed to load nvim-treesitter: " .. tostring(err))
  end
end

-- 2. Install treesitter parsers (only the missing ones).
do
  local ok_mod, parsers = pcall(require, "nvim-treesitter.parsers")
  if not ok_mod then
    fail("nvim-treesitter.parsers module unavailable: " .. tostring(parsers))
  end

  local missing = {}
  for _, lang in ipairs(TS_PARSERS) do
    if not parsers.has_parser(lang) then
      table.insert(missing, lang)
    end
  end

  if #missing == 0 then
    log("treesitter: all parsers already installed: " .. table.concat(TS_PARSERS, " "))
  else
    log("treesitter: installing missing parsers: " .. table.concat(missing, " "))
    -- TSInstallSync is synchronous; missing-only avoids the reinstall prompt.
    local ok = pcall(vim.cmd, "TSInstallSync " .. table.concat(missing, " "))
    if not ok then
      log("treesitter: TSInstallSync raised an error, verifying results")
    end

    -- Verify every parser is actually present now.
    local still_missing = {}
    for _, lang in ipairs(missing) do
      if not parsers.has_parser(lang) then
        table.insert(still_missing, lang)
      end
    end
    if #still_missing > 0 then
      fail("treesitter parsers failed to install: " .. table.concat(still_missing, " "))
    end
    log("treesitter: installed " .. table.concat(missing, " "))
  end
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
