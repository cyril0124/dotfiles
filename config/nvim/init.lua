-- Set leader key to <space>
vim.g.mapleader = " "

-- Set localleader key to <->
vim.g.maplocalleader = "-"

-- [nvim-tree] Disable netrw at the very start of your init.lua
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

-- vim.o.clipboard = 'unamedplus'
-- vim.g.clipboard = 'osc52'
-- local function no_paste(reg)
--     return function() end
-- end
-- vim.g.clipboard = {
--     name = 'OSC52',
--     copy = {
--         ['+'] = require('vim.ui.clipboard.osc52').copy('+'),
--         ['*'] = require('vim.ui.clipboard.osc52').copy('*'),
--     },
--     paste = {
--         ['+'] = no_paste('+'),
--         ['*'] = no_paste('*'),
--     },
-- }

local config_dir = vim.fn.stdpath('config')
local pacakge_paths = {
    config_dir .. "/?.lua",
    config_dir .. "/lua/?.lua",
}
package.path = table.concat(pacakge_paths, ";")

-- Initialize Lazy.nvim(package manager for Neovim plugins)
do
    local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
    if not (vim.uv or vim.loop).fs_stat(lazypath) then
        vim.fn.system({
            "git",
            "clone",
            "--filter=blob:none",
            "https://github.com/folke/lazy.nvim.git",
            "--branch=stable", -- latest stable release
            lazypath,
        })
    end
    vim.opt.rtp:prepend(lazypath)
    require("lazy").setup("plugins")
end

require("lua.options")
require("lua.keymaps")
require("lua.colorscheme")
require("lua.lsp")

-- Disable mini.animate globally
vim.g.minianimate_disable = true
if os.getenv("NVIM_NO_ANIM") then
    vim.g.minianimate_disable = true
end
