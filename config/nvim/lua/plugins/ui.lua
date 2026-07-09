local function get_codediff_tabline_buffer()
	local ok, codediff = pcall(require, "lua.codediff")
	if not ok then
		return nil
	end

	return codediff.get_tabline_buffer(vim.api.nvim_get_current_tabpage())
end

local function should_show_buffer(codediff_shared, buf)
	local name = vim.api.nvim_buf_get_name(buf)
	local buffer_options = vim.bo[buf]

	if codediff_shared.is_auxiliary_filetype(buffer_options.filetype) then
		return false
	end

	if buffer_options.buftype == "nofile" and name == "" then
		return false
	end

	local codediff_tab_buf = get_codediff_tabline_buffer()
	if codediff_tab_buf then
		return buf == codediff_tab_buf
	end

	if codediff_shared.is_virtual_buffer_name(name) then
		return false
	end

	return true
end

local function is_codediff_reactive_buffer()
	local ok, codediff_shared = pcall(require, "lua.codediff_shared")
	return ok and codediff_shared.is_codediff_buffer(vim.api.nvim_get_current_buf())
end

local function is_codediff_window(codediff_shared, buf, win)
	if not (buf and vim.api.nvim_buf_is_valid(buf) and win and vim.api.nvim_win_is_valid(win)) then
		return false
	end

	if vim.w[win].codediff_restore then
		return true
	end

	if codediff_shared.is_auxiliary_filetype(vim.bo[buf].filetype) then
		return true
	end

	local tabpage = vim.api.nvim_win_get_tabpage(win)
	local session = codediff_shared.get_session(tabpage)
	if not session then
		return false
	end

	if codediff_shared.is_session_window(win, session) then
		return true
	end

	return codediff_shared.get_explorer_window(tabpage) == win
end

return {
	-- https://github.com/nvzone/menu
	{
		{
			"nvzone/volt",
			lazy = true,
		},
		{
			"nvzone/menu",
			lazy = true,
		},
	},

	-- https://github.com/akinsho/bufferline.nvim
	{
		"akinsho/bufferline.nvim",
		version = "*",
		dependencies = "nvim-tree/nvim-web-devicons",
		config = function()
			local codediff_shared = require("lua.codediff_shared")

			vim.opt.termguicolors = true
			vim.opt.showtabline = 2

			require("bufferline").setup({
				options = {
					always_show_bufferline = true,
					custom_filter = function(buf)
						return should_show_buffer(codediff_shared, buf)
					end,
					offsets = {
						{
							-- filetype = "NvimTree",
							filetype = "neo-tree",
							text = "Neo-tree",
							highlight = "Directory",
							text_align = "left",
							separator = true, -- use a "true" to enable the default, or set your own character
						},
					},
				},
			})
		end,
	},

	-- https://github.com/nvim-lualine/lualine.nvim
	{
		"nvim-lualine/lualine.nvim",
		event = "VeryLazy",
		dependencies = {
			"nvim-tree/nvim-web-devicons",
		},
		config = function()
			require("lualine").setup({
				options = {
					icons_enabled = true,
					theme = "auto",

					-- Do not show lualine on neo-tree
					disabled_filetypes = {
						"neo-tree",
						sections = {},
						winbar = {},
					},
				},
				sections = {
					lualine_a = { "mode" },
					lualine_b = { "branch", "diff", "diagnostics" },
					lualine_c = {
						"filename",
						"lsp_status",
						vim.g.minuet_ai_enabled and { require("minuet.lualine") } or nil,
					},
					lualine_x = { "encoding", "fileformat", "filetype" },
					lualine_y = { "progress" },
					lualine_z = { "location" },
				},
			})
		end,
	},

	-- https://github.com/nvim-neo-tree/neo-tree.nvim
	{
		{
			"nvim-neo-tree/neo-tree.nvim",
			branch = "v3.x",
			cmd = { "Neotree" },
			dependencies = {
				"nvim-lua/plenary.nvim",
				"MunifTanjim/nui.nvim",
				"nvim-tree/nvim-web-devicons", -- optional, but recommended
			},
			lazy = true,
			config = function()
				require("neo-tree").setup({
					source_selector = {
						winbar = true,
						statusline = true,
					},
					filesystem = {
						filtered_items = {
							hide_dotfiles = false,
							hide_gitignored = false,
							hide_ignored = false,
						},
						follow_current_file = {
							enabled = true,
							leave_dirs_open = true,
						},
						use_libuv_file_watcher = false,
					},
					buffers = {
						follow_current_file = {
							enabled = true,
						},
					},
					event_handlers = {
						{
							event = "vim_buffer_enter",
							handler = function()
								vim.opt_local.number = true
								vim.opt_local.foldenable = false
								vim.opt_local.foldlevel = 99
								vim.opt_local.foldmethod = "manual"
							end,
						},
					},
				})
			end,
		},
	},

	-- https://github.com/rachartier/tiny-inline-diagnostic.nvim
	{
		"rachartier/tiny-inline-diagnostic.nvim",
		event = "VeryLazy",
		priority = 1000,
		config = function()
			require("tiny-inline-diagnostic").setup({
				preset = "powerline",
				options = {
					show_source = {
						enable = true,
						if_many = false,
					},
					multilines = {
						-- Enable multiline diagnostic messages
						enabled = true,
						-- Always show messages on all lines for multiline diagnostics
						always_show = true,
					},
				},
			})
			vim.diagnostic.config({ virtual_text = false }) -- Disable default virtual text
		end,
	},

	-- https://github.com/folke/which-key.nvim
	{
		"folke/which-key.nvim",
		event = "VeryLazy",
		opts = {
			-- your configuration comes here
			-- or leave it empty to use the default settings
			-- refer to the configuration section below
		},
		keys = {
			{
				"<leader>?",
				function()
					require("which-key").show({ global = false })
				end,
				desc = "Buffer Local Keymaps (which-key)",
			},
			{
				"<localleader>?",
				function()
					require("which-key").show({ global = false })
				end,
				desc = "Buffer Local Keymaps (which-key)",
			},
		},
	},

	-- https://github.com/sphamba/smear-cursor.nvim
	{
		"sphamba/smear-cursor.nvim",
		opts = {
			filetypes_disabled = {
				"codediff-explorer",
				"codediff-help",
				"codediff-history",
			},
		},
	},

	-- https://github.com/Bekaboo/dropbar.nvim
	{
		"Bekaboo/dropbar.nvim",
		event = { "BufReadPost", "BufNewFile" },
		opts = function()
			local codediff_shared = require("lua.codediff_shared")

			return {
				bar = {
					enable = function(buf, win, _)
						buf = vim._resolve_bufnr(buf)
						if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_win_is_valid(win) then
							return false
						end

						if is_codediff_window(codediff_shared, buf, win) then
							return false
						end

						if vim.fn.win_gettype(win) ~= "" or vim.wo[win].winbar ~= "" or vim.bo[buf].ft == "help" then
							return false
						end

						local stat = vim.uv.fs_stat(vim.api.nvim_buf_get_name(buf))
						if stat and stat.size > 1024 * 1024 then
							return false
						end

						return vim.bo[buf].bt == "terminal"
							or vim.bo[buf].ft == "markdown"
							or pcall(vim.treesitter.get_parser, buf)
							or not vim.tbl_isempty(vim.lsp.get_clients({
								bufnr = buf,
								method = "textDocument/documentSymbol",
							}))
					end,
				},
			}
		end,
	},

	{
		"lukas-reineke/indent-blankline.nvim",
		main = "ibl",
		opts = {},
	},

	{
		"hedyhli/outline.nvim",
		lazy = true,
		cmd = { "Outline", "OutlineOpen" },
		keys = { -- Example mapping to toggle outline
			{ "<leader>o", "<cmd>Outline<CR>", desc = "Toggle outline" },
		},
		opts = {
			-- Your setup opts here
		},
	},

	-- The goal of nvim-ufo is to make Neovim's fold look modern and keep high performance.
	{
		"kevinhwang91/nvim-ufo",
		event = { "BufReadPost", "BufNewFile" },
		dependencies = "kevinhwang91/promise-async",
		config = function()
			vim.o.foldlevel = 99
			vim.o.foldlevelstart = 99
			vim.o.foldenable = true

			vim.keymap.set("n", "zR", require("ufo").openAllFolds)
			vim.keymap.set("n", "zM", require("ufo").closeAllFolds)

			require("ufo").setup()
		end,
	},

	{
		"nvim-zh/colorful-winsep.nvim",
		opts = {
			excluded_ft = {
				"packer",
				"TelescopePrompt",
				"mason",
				"codediff-explorer",
				"codediff-help",
				"codediff-history",
			},
		},
		event = { "WinLeave" },
	},

	-- https://github.com/folke/trouble.nvim
	{
		"folke/trouble.nvim",
		cmd = "Trouble",
		keys = {
			{ "<leader>T", "<cmd>Trouble diagnostics toggle<cr>", desc = "Diagnostics (Trouble)" },
		},
		opts = {},
	},

	-- https://github.com/lewis6991/satellite.nvim
	-- {
	--     "lewis6991/satellite.nvim",
	--     event = "VeryLazy",
	--     opts = {},
	-- },

	-- https://github.com/rasulomaroff/reactive.nvim
	{
		"rasulomaroff/reactive.nvim",
		event = "UIEnter",
		opts = {
			load = { "catppuccin-mocha-cursor", "catppuccin-mocha-cursorline" },
			configs = {
				["catppuccin-mocha-cursor"] = {
					skip = is_codediff_reactive_buffer,
				},
				["catppuccin-mocha-cursorline"] = {
					skip = is_codediff_reactive_buffer,
				},
			},
		},
	},
}
