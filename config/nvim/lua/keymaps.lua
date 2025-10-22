-----------------
-- Normal mode --
-----------------
-- Hint: see `:h vim.map.set()`
-- Better window navigation
vim.keymap.set("n", "<C-h>", "<C-w>h", { noremap = true, silent = true })
vim.keymap.set("n", "<C-j>", "<C-w>j", { noremap = true, silent = true })
vim.keymap.set("n", "<C-k>", "<C-w>k", { noremap = true, silent = true })
vim.keymap.set("n", "<C-l>", "<C-w>l", { noremap = true, silent = true })

-- Resize with arrows
-- delta: 2 lines
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
vim.keymap.set("n", "<leader>t", "<CMD>ToggleTerm direction=float<CR>", { desc = "Toggle terminal" })
-- vim.keymap.set("n", "<leader>ft", "<CMD>ToggleTerm direction=float<CR>", { desc = "Toggle float terminal" })

-- Telescope live_grep/grep_string
local builtin = require("telescope.builtin")
vim.keymap.set("n", "<leader>ff", builtin.find_files, { desc = "Telescope find files" })
vim.keymap.set("n", "<leader>fw", builtin.live_grep, { desc = "Telescope live grep" })
vim.keymap.set("n", "<leader>gs", function()
    require("telescope.builtin").grep_string()
end, { desc = "Grep word under cursor" })

-- Search and replace
vim.keymap.set("n", "<leader>sr", "<CMD>GrugFar<CR>", { desc = "Search and replace" })

-- Toggle neo-tree
vim.keymap.set("n", "<leader>e", function()
    local is_term = vim.bo.buftype == "terminal"
    if is_term then
        vim.notify("Cannot toggle neo-tree when current buffer type is 'terminal'", vim.log.levels.WARN)
    else
        local dir = vim.fn.expand("%:p:h")
        require("neo-tree.command").execute({ toggle = true, dir = is_term and nil or dir })
    end
end, { desc = "Toggle NeoTree" })

-- Comment
vim.keymap.set("n", "<leader>/", "gcc", { desc = "Toggle comment", remap = true })
vim.keymap.set("v", "<leader>/", "gc", { desc = "Toggle comment", remap = true })

-- Tabbufline
vim.keymap.set("n", "<tab>", "<CMD>BufferLineCycleNext<CR>", { desc = "Buffer goto next" })
vim.keymap.set("n", "<S-tab>", "<CMD>BufferLineCyclePrev<CR>", { desc = "Buffer goto prev" })

-- Which key
vim.keymap.set("n", "<leader>wk", "<CMD>WhichKey<CR>", { desc = "Show whichkey all keymaps" })

vim.keymap.set('n', '<leader>pa', function()
    print(vim.fn.expand('%:p'))
end, { desc = 'Print absolute path' })

-- LSP diagnostic
-- vim.keymap.set("n", "<leader>ds", vim.diagnostic.setloclist, { desc = "LSP diagnostic localist" })
vim.keymap.set("n", "<leader>ds", "<CMD>Telescope diagnostics<CR>", { desc = "LSP telescope diagnostic" })

-- Code format
vim.keymap.set("n", "<leader>f", function()
    require("conform").format({ async = true, lsp_fallback = true })
end, { desc = "Format code(using conform.nvim)" })
vim.api.nvim_create_user_command("F", function()
    require("conform").format({ async = true, lsp_fallback = true })
end, { desc = "Format code(using conform.nvim)" })
vim.api.nvim_create_user_command("FF", function()
    require("conform").format({ async = true, lsp_fallback = true })
    vim.cmd("w") -- Save file
end, { desc = "Format and save" })
vim.api.nvim_create_user_command("FW", function()
    require("conform").format({ async = true, lsp_fallback = true })
    vim.cmd("w") -- Save file
end, { desc = "Format and save" })

-- Trim whitespace
vim.api.nvim_create_user_command("TS", function()
    -- `MiniTrailspace` is provided by `mini.trailspace` plugin
    MiniTrailspace.trim()
end, { desc = "Trim whitespace" })

-- Menu
local show_menu = function()
    local menu = require("menu")
    local winid = vim.api.nvim_get_current_win()
    local buf = vim.api.nvim_win_get_buf(winid)
    local buftype = vim.bo[buf].ft
    vim.notify("[show_menu] buftype: " .. vim.inspect(buftype), vim.log.levels.INFO)

    if buftype == "neo-tree" then
        menu.open("neo-tree")
    elseif buftype == "grug-far" then
        menu.open("grug-far")
    elseif buftype == "markdown" then
        menu.open("markdown")
    else
        if vim.g.diffview_is_open then
            local diffview_menu = require("lua.menus.diffview")
            menu.open(diffview_menu)
        else
            local mydefault_menu = require("lua.menus.mydefault")
            menu.open(mydefault_menu)
        end
    end
end
vim.keymap.set("n", "<leader>m", show_menu, { desc = "Show menu" })
vim.keymap.set("n", "<leader>M", show_menu, { desc = "Show menu" })


-----------------
-- Visual mode --
-----------------
-- Hint: start visual mode with the same area as the previous area and the same mode
vim.keymap.set("v", "<", "<gv", { noremap = true, silent = true })
vim.keymap.set("v", ">", ">gv", { noremap = true, silent = true })

vim.keymap.set("v", "<leader>m", show_menu, { desc = "Show menu" })
vim.keymap.set("v", "<leader>M", show_menu, { desc = "Show menu" })

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
