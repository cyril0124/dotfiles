return {
    {
        name = "Trim spaces",
        cmd = function()
            MiniTrailspace.trim()
        end,
        rtxt = "ts",
    },

    {
        name = "Format",
        cmd = function()
            require("conform").format({ async = true, lsp_fallback = true })
        end,
        rtxt = "f",
    },

    {
        name = "Find files(no-ignore)",
        cmd = function()
            local builtin = require("telescope.builtin")
            builtin.find_files({
                find_command = { "rg", "--files", "--hidden", "--no-ignore", "--glob", "!**/.git/*" }
            })
        end,
        rtxt = "ff",
    },

    {
        name = "Find words(no-ignore)",
        cmd = function()
            local builtin = require("telescope.builtin")
            builtin.live_grep({
                additional_args = { "--no-ignore" }
            })
        end,
        rtxt = "fw",
    },

    {
        name = "Search and replace globally(grug-far)",
        cmd = function()
            vim.cmd("GrugFar")
        end,
        rtxt = "rg",
    },

    {
        name = "DiffviewOpen",
        cmd = function()
            vim.g.diffview_is_open = true
            vim.cmd("DiffviewOpen")
        end,
        rtxt = "df",
    },

    {
        name = "  LSP Actions",
        hl = "Exblue",
        items = "lsp",
    },

    {
        name = "󰊢  Git Actions",
        hl = "Exblue",
        items = "gitsigns",
    },

    { name = "separator" },

    {
        name = "Edit Config",
        cmd = function()
            vim.cmd "tabnew"
            local conf = vim.fn.stdpath "config"
            vim.cmd("tcd " .. conf .. " | e init.lua")
        end,
        rtxt = "ed",
    },
}
