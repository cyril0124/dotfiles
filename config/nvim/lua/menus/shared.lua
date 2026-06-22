-- Shared menu items appended to all menus
return function()
    return {
        { name = "separator" },

        {
            name = "Notification history",
            cmd = function()
                require("mini.notify").show_history()
            end,
            rtxt = "nh",
        },

        require("lua.quit_guard").menu_item(),

        {
            name = "Toggle line numbers",
            cmd = function()
                vim.wo.number = not vim.wo.number
            end,
            rtxt = "ln",
        },

        {
            name = "CodeDiffOpen",
            cmd = function()
                require("lua.codediff").open()
            end,
            rtxt = "df",
        },

        {
            name = "CodeDiffFileHistory",
            cmd = function()
                require("lua.codediff").open("history %")
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
                require("lua.git_diff").open_last_commit_diff()
            end,
            rtxt = "lc",
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
end
