local function setup_notify()
	local notify = require("mini.notify")
	notify.setup()
	vim.notify = notify.make_notify({
		-- ERROR = { duration = 50000 },
		-- WARN = { duration = 40000 },
		-- INFO = { duration = 30000 },
	})
end

local function setup_hipatterns()
	local hipatterns = require("mini.hipatterns")
	hipatterns.setup({
		highlighters = {
			-- Highlight standalone 'FIXME', 'HACK', 'TODO', 'NOTE'
			fixme = { pattern = "%f[%w]()FIXME()%f[%W]", group = "MiniHipatternsFixme" },
			hack = { pattern = "%f[%w]()HACK()%f[%W]", group = "MiniHipatternsHack" },
			todo = { pattern = "%f[%w]()TODO()%f[%W]", group = "MiniHipatternsTodo" },
			note = { pattern = "%f[%w]()NOTE()%f[%W]", group = "MiniHipatternsNote" },

			-- Highlight hex color strings (`#rrggbb`) using that color
			hex_color = hipatterns.gen_highlighter.hex_color(),
		},
	})
end

local function should_animate_scroll(total_scroll)
	return total_scroll > 3
end

local function setup_animate()
	local animate = require("mini.animate")
	animate.setup({
		cursor = {
			enable = false,
		},
		open = {
			enable = false,
		},
		close = {
			enable = false,
		},
		scroll = {
			enable = true,
			timing = animate.gen_timing.linear({ duration = 60, unit = "total" }),
			subscroll = animate.gen_subscroll.equal({
				max_output_steps = 4,
				predicate = should_animate_scroll,
			}),
		},
		resize = {
			enable = false,
		},
	})
end

return {
	"echasnovski/mini.nvim",
	version = "*",
	config = function()
		-- Autopairs
		require("mini.pairs").setup({
			modes = { insert = true, command = true, terminal = false },
		})

		-- Surround text with brackets, quotes, etc.
		-- https://github.com/nvim-mini/mini.nvim/blob/main/readmes/mini-surround.md
		-- Add brackets: `sa` + <bracket>
		-- Delete brackets: `sd` + <bracket>
		require("mini.surround").setup()

		-- Git support
		require("mini.git").setup()

		-- Trailspace (highlight and remove)
		require("mini.trailspace").setup()

		-- Show notifications
		setup_notify()

		-- Highlight patterns in text
		setup_hipatterns()

		-- Start screen
		-- require('mini.starter').setup()

		-- Jump to next/previous single character
		require("mini.jump").setup({
			mappings = {
				forward = "f",
				backward = "F",
				forward_till = "t",
				backward_till = "T",
				repeat_jump = ";",
			},
		})

		-- Automatic highlighting of word under cursor
		require("mini.cursorword").setup()

		-- Animate common Neovim actions
		setup_animate()
	end,
}
