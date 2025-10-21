-- Tab size
vim.opt.tabstop = 2
vim.opt.shiftwidth = 4
vim.opt.softtabstop = 2
vim.opt.expandtab = true
vim.opt.smartindent = true

-- Hint: use `:h <option>` to figure out the meaning if needed
vim.opt.clipboard = 'unnamedplus' -- use system clipboard
vim.opt.completeopt = { 'menu', 'menuone', 'noselect' }
vim.opt.mouse = 'a'               -- allow the mouse to be used in nvim
vim.opt.mousemoveevent = true

-- UI config
vim.opt.number = true     -- show line numbers
vim.opt.cursorline = true -- highlight the current line
vim.opt.splitbelow = true -- open new vertical split bottom
vim.opt.splitright = true -- open new horizontal splits right

-- Search config
vim.opt.ignorecase = true -- ignore case in searches by default
vim.opt.smartcase = true  -- but make it case sensitive if an uppercase is entered

-- Undo
vim.opt.undofile = true
vim.opt.undodir = vim.fn.stdpath("data") .. "/undo"
os.execute("mkdir -p " .. vim.o.undodir)

-- Scroll
vim.opt.scrolloff = 4 -- keep 4 lines above/below cursor when scrolling

