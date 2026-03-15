-- define your colorscheme here
local config = require("lua.config")

local is_ok, _ = pcall(vim.cmd, "colorscheme " .. config.colorscheme)
if not is_ok then
    vim.notify('colorscheme ' .. config.colorscheme .. ' not found!')
    return
end
