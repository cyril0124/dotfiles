-- Tab size
vim.opt.tabstop = 4
vim.opt.shiftwidth = 4
vim.opt.softtabstop = 4
vim.opt.expandtab = true
vim.opt.smartindent = true

-- Hint: use `:h <option>` to figure out the meaning if needed
vim.opt.clipboard = "unnamedplus" -- use system clipboard
vim.opt.completeopt = { "menu", "menuone", "noselect" }
vim.opt.mouse = "a" -- allow the mouse to be used in nvim
vim.opt.mousemoveevent = true

-- UI config
vim.opt.number = true -- show line numbers
vim.opt.cursorline = true -- highlight the current line
vim.opt.splitbelow = true -- open new vertical split bottom
vim.opt.splitright = true -- open new horizontal splits right

-- Search config
vim.opt.ignorecase = true -- ignore case in searches by default
vim.opt.smartcase = true -- but make it case sensitive if an uppercase is entered

-- Undo
vim.opt.undofile = true
vim.opt.undodir = vim.fs.joinpath(vim.fn.stdpath("data"), "undo")
vim.fn.mkdir(vim.o.undodir, "p")

-- Scroll
vim.opt.scrolloff = 4 -- keep 4 lines above/below cursor when scrolling

local resize_group = vim.api.nvim_create_augroup("window_resize_equalize", { clear = true })

vim.api.nvim_create_autocmd("VimResized", {
	group = resize_group,
	callback = function()
		local ok_codediff, codediff = pcall(require, "lua.codediff")
		if ok_codediff and codediff.is_current_session() then
			return
		end

		local normal_windows = 0
		for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
			local config = vim.api.nvim_win_get_config(win)
			if config.relative == "" and vim.fn.win_gettype(win) == "" then
				normal_windows = normal_windows + 1
			end
		end

		if normal_windows > 1 then
			vim.cmd("wincmd =")
		end
	end,
})
