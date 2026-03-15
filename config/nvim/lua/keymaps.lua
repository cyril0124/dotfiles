local menus = require("lua.menus")

-----------------
-- Normal mode --
-----------------
-- Better window navigation
vim.keymap.set("n", "<C-h>", "<C-w>h", { noremap = true, silent = true })
vim.keymap.set("n", "<C-j>", "<C-w>j", { noremap = true, silent = true })
vim.keymap.set("n", "<C-k>", "<C-w>k", { noremap = true, silent = true })
vim.keymap.set("n", "<C-l>", "<C-w>l", { noremap = true, silent = true })

-- Resize with arrows
vim.keymap.set("n", "<C-Up>", "<CMD>resize -2<CR>", { noremap = true, silent = true })
vim.keymap.set("n", "<C-Down>", "<CMD>resize +2<CR>", { noremap = true, silent = true })
vim.keymap.set("n", "<C-Left>", "<CMD>vertical resize -2<CR>", { noremap = true, silent = true })
vim.keymap.set("n", "<C-Right>", "<CMD>vertical resize +2<CR>", { noremap = true, silent = true })

-- Close current buffer
vim.keymap.set("n", "<leader>x", "<CMD>bdelete<CR>", { noremap = true, silent = true, desc = "Close current buffer" })

-- Save file
vim.keymap.set("n", "<leader>w", "<CMD>w<CR>", { noremap = true, silent = true, desc = "Save file" })

-- Quit nvim
vim.keymap.set("n", "<leader>q", "<CMD>qa<CR>", { silent = true, desc = "Quit nvim" })

-- Toggle terminal
vim.keymap.set("n", "<leader>t", "<CMD>ToggleTerm direction=float<CR>", { desc = "Toggle terminal(float)" })
vim.keymap.set("n", "<leader>dt", "<CMD>ToggleTerm direction=horizontal<CR>", { desc = "Toggle terminal(down)" })

-- Telescope
local builtin = require("telescope.builtin")
vim.keymap.set("n", "<leader>ff", builtin.find_files, { desc = "Telescope find files" })
vim.keymap.set("n", "<leader>fw", builtin.live_grep, { desc = "Telescope live grep" })
vim.keymap.set("n", "<leader>gs", function()
    require("telescope.builtin").grep_string({ additional_args = { "-w" } })
end, { desc = "Grep word under cursor(wholeword)" })
vim.keymap.set("n", "<leader>gS", function()
    require("telescope.builtin").grep_string()
end, { desc = "Grep word under cursor" })

-- Search and replace
vim.keymap.set("n", "<leader>sr", "<CMD>GrugFar<CR>", { desc = "Search and replace" })

-- Toggle neo-tree
vim.keymap.set("n", "<leader>e", function()
    local is_term = vim.bo.buftype == "terminal"
    local dir = is_term and nil or vim.fn.expand("%:p:h")
    require("neo-tree.command").execute({ toggle = true, position = "float", dir = dir })
end, { desc = "Toggle NeoTree(float)" })
vim.keymap.set("n", "<leader>E", function()
    local is_term = vim.bo.buftype == "terminal"
    local dir = is_term and nil or vim.fn.expand("%:p:h")
    require("neo-tree.command").execute({ toggle = true, position = "left", dir = dir })
end, { desc = "Toggle NeoTree(left-side)" })

-- Comment
vim.keymap.set("n", "<leader>/", "gcc", { desc = "Toggle comment", remap = true })
vim.keymap.set("v", "<leader>/", "gc", { desc = "Toggle comment", remap = true })

-- Bufferline
vim.keymap.set("n", "<tab>", "<CMD>BufferLineCycleNext<CR>", { desc = "Buffer goto next" })
vim.keymap.set("n", "<S-tab>", "<CMD>BufferLineCyclePrev<CR>", { desc = "Buffer goto prev" })

-- Which key
vim.keymap.set("n", "<leader>wk", "<CMD>WhichKey<CR>", { desc = "Show whichkey all keymaps" })

vim.keymap.set('n', '<leader>pa', function()
    print(vim.fn.expand('%:p'))
end, { desc = 'Print absolute path' })

-- LSP diagnostic
vim.keymap.set("n", "<leader>ds", function()
    require("telescope.builtin").diagnostics()
end, { desc = "LSP telescope diagnostic" })
vim.keymap.set("n", "<leader>dS", function()
    require("telescope.builtin").diagnostics({ severity_limit = vim.diagnostic.severity.WARN })
end, { desc = "LSP telescope diagnostic(only warning and error)" })

-- Code format
vim.keymap.set("n", "<leader>f", function()
    require("conform").format({ async = true, lsp_fallback = true })
end, { desc = "Format code(using conform.nvim)" })

-- Menu
vim.keymap.set("n", "<leader>m", menus.show, { desc = "Show menu" })
vim.keymap.set("n", "<leader>M", menus.show, { desc = "Show menu" })

-- Diffview
vim.keymap.set("n", "<leader>gD", function()
    if vim.g.diffview_is_open then
        vim.g.diffview_is_open = false
        vim.cmd("DiffviewClose")
    else
        vim.g.diffview_is_open = true
        vim.cmd("DiffviewOpen")
    end
end, { desc = "Toggle diffview" })


-----------------
-- Visual mode --
-----------------
vim.keymap.set("v", "<", "<gv", { noremap = true, silent = true })
vim.keymap.set("v", ">", ">gv", { noremap = true, silent = true })

vim.keymap.set("v", "<leader>m", menus.show, { desc = "Show menu" })
vim.keymap.set("v", "<leader>M", menus.show, { desc = "Show menu" })

vim.keymap.set("v", "<leader>gs",
    '"ay<CMD>lua require("telescope.builtin").grep_string({ search = vim.fn.getreg("a") })<CR>', {
        noremap = true,
        silent = true,
        desc = "Grep selection into register 'a'",
    })

vim.keymap.set("x", "<leader>sr", "<CMD>'<,'>GrugFarWithin<CR>", { desc = "Search and replace in selection" })


-------------------
-- Terminal mode --
-------------------
vim.keymap.set("t", "<Esc>", [[<C-\><C-n>]], {
    desc = "Exit terminal insert mode",
})
