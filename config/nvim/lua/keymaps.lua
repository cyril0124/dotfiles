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
vim.keymap.set("n", "<leader>t", "<CMD>ToggleTerm direction=float<CR>", { desc = "Toggle terminal(float)" })
vim.keymap.set("n", "<leader>dt", "<CMD>ToggleTerm direction=horizontal<CR>", { desc = "Toggle terminal(down)" })

-- Telescope live_grep/grep_string
local builtin = require("telescope.builtin")
local diffview = require("lua.menus.diffview")
vim.keymap.set("n", "<leader>ff", builtin.find_files, { desc = "Telescope find files" })
vim.keymap.set("n", "<leader>fw", builtin.live_grep, { desc = "Telescope live grep" })
vim.keymap.set("n", "<leader>gs", function()
    require("telescope.builtin").grep_string({
        additional_args = {
            "-w"
        }
    })
end, { desc = "Grep word under cursor(wholeword)" })
vim.keymap.set("n", "<leader>gS", function()
    require("telescope.builtin").grep_string()
end, { desc = "Grep word under cursor" })

-- Search and replace
vim.keymap.set("n", "<leader>sr", "<CMD>GrugFar<CR>", { desc = "Search and replace" })

-- Toggle neo-tree
vim.keymap.set("n", "<leader>e", function()
    local is_term = vim.bo.buftype == "terminal"
    local dir
    if is_term then
        dir = nil
    else
        dir = vim.fn.expand("%:p:h")
    end

    require("neo-tree.command").execute({ toggle = true, position = "float", dir = is_term and nil or dir })
end, { desc = "Toggle NeoTree(float)" })
vim.keymap.set("n", "<leader>E", function()
    local is_term = vim.bo.buftype == "terminal"
    local dir
    if is_term then
        dir = nil
    else
        dir = vim.fn.expand("%:p:h")
    end

    require("neo-tree.command").execute({ toggle = true, position = "left", dir = is_term and nil or dir })
end, { desc = "Toggle NeoTree(left-side)" })

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
local telescope_diagnostic = require("telescope.builtin").diagnostics
vim.keymap.set("n", "<leader>ds", function()
    telescope_diagnostic()
end, { desc = "LSP telescope diagnostic" })
vim.keymap.set("n", "<leader>dS", function()
    telescope_diagnostic({ severity_limit = vim.diagnostic.severity.WARN })
end, { desc = "LSP telescope diagnostic(only warning and error)" })

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

    if vim.g.diffview_is_open then
        local diffview_menu = require("lua.menus.diffview")
        menu.open(diffview_menu)
    elseif buftype == "neo-tree" then
        menu.open("neo-tree")
    elseif buftype == "grug-far" then
        menu.open("grug-far")
    elseif buftype == "markdown" then
        menu.open("markdown")
    else
        local mydefault_menu = require("lua.menus.mydefault")
        menu.open(mydefault_menu)
    end
end
vim.keymap.set("n", "<leader>m", show_menu, { desc = "Show menu" })
vim.keymap.set("n", "<leader>M", show_menu, { desc = "Show menu" })

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

do
    -- 1. Initialize a global state variable to track the wrap setting.
    --    true = wrap enabled, false = wrap disabled.
    --    The default is set to true (wrap on). You can change this to match your preference.
    _G.global_wrap_enabled = true

    -- 2. Create an autocommand to set the wrap option for new windows
    --    based on the global state.
    local wrap_augroup = vim.api.nvim_create_augroup("GlobalWrapToggle", { clear = true })
    vim.api.nvim_create_autocmd("WinEnter", {
        group = wrap_augroup,
        pattern = "*",
        callback = function()
            -- vim.wo is a shortcut for setting window-local options for the current window.
            if _G.global_wrap_enabled then
                vim.wo.wrap = true
            else
                vim.wo.wrap = false
            end
        end,
    })

    -- 3. Create the :NW (No Wrap) command.
    vim.api.nvim_create_user_command("NW", function()
        -- Update the global state.
        _G.global_wrap_enabled = false

        -- Iterate over all current windows and disable wrap immediately.
        for _, win in ipairs(vim.api.nvim_list_wins()) do
            vim.wo[win].wrap = false
        end

        vim.notify("Line wrap DISABLED globally", vim.log.levels.INFO)
    end, {
        desc = "Globally disable line wrapping for all windows"
    })

    -- 4. Create the :WW (With Wrap) command.
    vim.api.nvim_create_user_command("WW", function()
        -- Update the global state.
        _G.global_wrap_enabled = true

        -- Iterate over all current windows and enable wrap immediately.
        for _, win in ipairs(vim.api.nvim_list_wins()) do
            vim.wo[win].wrap = false
        end

        vim.notify("Line wrap ENABLED globally", vim.log.levels.INFO)
    end, {
        desc = "Globally enable line wrapping for all windows"
    })
end


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
