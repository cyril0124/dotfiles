local wrap_toggle = require("lua.wrap_toggle")
local formatter = require("lua.format")

-- Format code
vim.api.nvim_create_user_command("F", function()
    formatter.format({ async = true })
end, { desc = "Format code(using conform.nvim)" })

vim.api.nvim_create_user_command("FF", function()
    formatter.format()
    vim.cmd("w")
end, { desc = "Format and save" })

vim.api.nvim_create_user_command("FW", function()
    formatter.format()
    vim.cmd("w")
end, { desc = "Format and save" })

-- Trim whitespace
vim.api.nvim_create_user_command("TS", function()
    require("mini.trailspace").trim()
end, { desc = "Trim whitespace" })

-- Wrap toggle
vim.api.nvim_create_user_command("NW", function()
    wrap_toggle.disable()
end, { desc = "Globally disable line wrapping for all windows" })

vim.api.nvim_create_user_command("WW", function()
    wrap_toggle.enable()
end, { desc = "Globally enable line wrapping for all windows" })
