-- Set leader key to <space>
vim.g.mapleader = " "

-- Set localleader key to <->
vim.g.maplocalleader = "-"

-- [nvim-tree] Disable netrw at the very start of your init.lua
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

vim.filetype.add({
	extension = {
		jsonl = "json",
	},
})

local function configure_package_path()
	local config_dir = vim.fn.stdpath("config")
	local package_paths = {
		config_dir .. "/?.lua",
		config_dir .. "/lua/?.lua",
		config_dir .. "/?/init.lua",
		config_dir .. "/lua/?/init.lua",
	}

	for _, path in ipairs(package_paths) do
		if not package.path:find(path, 1, true) then
			package.path = package.path .. ";" .. path
		end
	end
end

local function bootstrap_lazy()
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
end

configure_package_path()

-- Initialize Lazy.nvim(package manager for Neovim plugins)
bootstrap_lazy()
require("lazy").setup("plugins")

require("lua.options")
require("lua.keymaps")
require("lua.commands")
require("lua.colorscheme")
require("lua.lsp")

-- Disable mini.animate globally
-- vim.g.minianimate_disable = true
