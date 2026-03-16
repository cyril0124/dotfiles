-- Shared menu items appended to all menus
return {
    { name = "separator" },

    {
        name = "Notification history",
        cmd = function()
            require("mini.notify").show_history()
        end,
        rtxt = "nh",
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
        name = "DiffviewFileHistory",
        cmd = function()
            vim.cmd("DiffviewFileHistory %")
        end,
        rtxt = "fh",
    },

    {
        name = "Toggle git blame",
        cmd = function()
            vim.cmd("Gitsigns toggle_current_line_blame")
        end,
        rtxt = "gb",
    },

    {
        name = "Last commit diff",
        cmd = function()
            vim.g._last_commit_depth = (vim.g._last_commit_depth or 0) + 1
            vim.cmd("DiffviewClose")
            vim.cmd("DiffviewFileHistory --range=HEAD~" .. vim.g._last_commit_depth .. "..HEAD")
        end,
        rtxt = "lc",
    },

    {
        name = "Reset commit depth",
        cmd = function()
            vim.g._last_commit_depth = 0
            vim.cmd("DiffviewClose")
        end,
        rtxt = "rc",
    },

    {
        name = "Switch colorscheme",
        cmd = function()
            local config = require("lua.config")
            vim.ui.select(
                config.themes,
                { prompt = "Select colorscheme:" },
                function(choice)
                    if choice then vim.cmd("colorscheme " .. choice) end
                end
            )
        end,
        rtxt = "cs",
    },
}
