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
