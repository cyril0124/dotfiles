local M = {}

local function with_shared(items)
    local shared = require("lua.menus.shared")
    local result = {}
    for _, item in ipairs(items) do
        result[#result + 1] = item
    end
    for _, item in ipairs(shared) do
        result[#result + 1] = item
    end
    return result
end

function M.show()
    local menu = require("menu")
    local winid = vim.api.nvim_get_current_win()
    local buf = vim.api.nvim_win_get_buf(winid)
    local buftype = vim.bo[buf].ft
    vim.notify("[show_menu] buftype: " .. vim.inspect(buftype), vim.log.levels.INFO)

    if vim.g.diffview_is_open then
        menu.open(with_shared(require("lua.menus.diffview")))
    elseif buftype == "neo-tree" then
        menu.open(with_shared(require("lua.menus.neo-tree")))
    elseif buftype == "grug-far" then
        menu.open(with_shared(require("lua.menus.grug-far")))
    elseif buftype == "markdown" then
        menu.open(with_shared(require("lua.menus.markdown")))
    else
        menu.open(with_shared(require("lua.menus.mydefault")))
    end
end

return M
