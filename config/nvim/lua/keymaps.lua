local menus = require("lua.menus")
local codediff = require("lua.codediff")
local quit_guard = require("lua.quit_guard")
local formatter = require("lua.format")

local function navigate_window(direction, fallback)
    return function()
        if not codediff.navigate(direction) then
            vim.cmd("wincmd " .. fallback)
        end
    end
end

local function current_file_path()
    local path = vim.api.nvim_buf_get_name(0)
    return path ~= "" and path or nil
end

local function current_file_dir()
    if vim.bo.buftype == "terminal" then
        return nil
    end

    local path = current_file_path()
    return path and vim.fs.dirname(path) or nil
end

local function run_outside_codediff(callback)
    return function()
        codediff.run_outside_current_session(callback)
    end
end

-----------------
-- Normal mode --
-----------------
-- Better window navigation
vim.keymap.set("n", "<C-h>", navigate_window("left", "h"), { noremap = true, silent = true })
vim.keymap.set("n", "<C-j>", navigate_window("down", "j"), { noremap = true, silent = true })
vim.keymap.set("n", "<C-k>", navigate_window("up", "k"), { noremap = true, silent = true })
vim.keymap.set("n", "<C-l>", navigate_window("right", "l"), { noremap = true, silent = true })

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
vim.keymap.set("n", "<leader>q", quit_guard.quit_all, { silent = true, desc = "Quit nvim" })

-- Toggle terminal
vim.keymap.set("n", "<leader>t", "<CMD>ToggleTerm direction=float<CR>", { desc = "Toggle terminal(float)" })
vim.keymap.set("n", "<leader>dt", "<CMD>ToggleTerm direction=horizontal<CR>", { desc = "Toggle terminal(down)" })

-- File search
vim.keymap.set("n", "<leader>ff", function()
    require("fff").find_files()
end, { desc = "FFF find files" })
vim.keymap.set("n", "<leader>fw", run_outside_codediff(function()
    require("fff").live_grep()
end), { desc = "FFF live grep" })
vim.keymap.set("n", "<leader>gs", run_outside_codediff(function()
    require("fff").live_grep({
        query = vim.fn.expand("<cword>"),
        grep = {
            modes = { "fuzzy", "plain", "regex" },
        },
    })
end), { desc = "FFF grep word under cursor (fuzzy first)" })
vim.keymap.set("n", "<leader>gS", run_outside_codediff(function()
    require("fff").live_grep({
        query = vim.fn.expand("<cword>"),
        grep = {
            modes = { "plain", "regex", "fuzzy" },
        },
    })
end), { desc = "FFF grep word under cursor (plain first)" })

-- Search and replace
vim.keymap.set("n", "<leader>sr", "<CMD>GrugFar<CR>", { desc = "Search and replace" })

-- Toggle neo-tree
vim.keymap.set("n", "<leader>e", function()
    require("neo-tree.command").execute({ toggle = true, position = "float", dir = current_file_dir() })
end, { desc = "Toggle NeoTree(float)" })
vim.keymap.set("n", "<leader>E", function()
    require("neo-tree.command").execute({ toggle = true, position = "left", dir = current_file_dir() })
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
    print(current_file_path() or "")
end, { desc = 'Print absolute path' })

-- LSP diagnostic
vim.keymap.set("n", "<leader>ds", run_outside_codediff(function()
    require("telescope.builtin").diagnostics()
end), { desc = "LSP telescope diagnostic" })
vim.keymap.set("n", "<leader>dS", run_outside_codediff(function()
    require("telescope.builtin").diagnostics({ severity_limit = vim.diagnostic.severity.WARN })
end), { desc = "LSP telescope diagnostic(only warning and error)" })

-- Code format
vim.keymap.set("n", "<leader>f", function()
    formatter.format({ async = true })
end, { desc = "Format code(using conform.nvim)" })

-- Menu
vim.keymap.set("n", "<leader>m", menus.show, { desc = "Show menu" })
vim.keymap.set("n", "<leader>M", menus.show, { desc = "Show menu" })

-- CodeDiff
vim.keymap.set("n", "<leader>gD", function()
    require("lua.codediff").open()
end, { desc = "Toggle CodeDiff" })

-- Git hunk navigation
vim.keymap.set("n", "]h", function()
    require("gitsigns").nav_hunk("next")
end, { desc = "Next git hunk" })
vim.keymap.set("n", "[h", function()
    require("gitsigns").nav_hunk("prev")
end, { desc = "Previous git hunk" })

-- View last commit diff (incremental depth)
vim.keymap.set("n", "<leader>gl", function()
    require("lua.git_diff").open_last_commit_diff()
end, { desc = "Last commit diff (deeper each press)" })

-- View current file commit history
vim.keymap.set("n", "<leader>gL", function()
    require("lua.codediff").open("history %")
end, { desc = "Current file commit history" })


-----------------
-- Visual mode --
-----------------
vim.keymap.set("v", "<", "<gv", { noremap = true, silent = true })
vim.keymap.set("v", ">", ">gv", { noremap = true, silent = true })

vim.keymap.set("v", "<leader>m", menus.show, { desc = "Show menu" })
vim.keymap.set("v", "<leader>M", menus.show, { desc = "Show menu" })

vim.keymap.set("v", "<leader>gs", function()
    local saved = vim.fn.getreg("a")
    vim.cmd('noautocmd normal! "ay')
    local query = vim.fn.getreg("a")
    vim.fn.setreg("a", saved)
    require("lua.codediff").run_outside_current_session(function()
        require("fff").live_grep({ query = query })
    end)
end, { desc = "Grep selection" })

vim.keymap.set("x", "<leader>sr", "<CMD>'<,'>GrugFarWithin<CR>", { desc = "Search and replace in selection" })


-------------------
-- Terminal mode --
-------------------
vim.keymap.set("t", "<Esc>", [[<C-\><C-n>]], {
    desc = "Exit terminal insert mode",
})
