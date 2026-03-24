local M = {}

local function resolve_items(items)
    if type(items) == "function" then
        return items()
    end
    return items
end

local function with_shared(items)
    local shared = resolve_items(require("lua.menus.shared"))
    items = resolve_items(items)
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
    local filetype = vim.bo[buf].filetype

    local is_diffview = require("lua.codediff").is_current_session()
        or filetype == "DiffviewFiles"
        or filetype == "DiffviewFileHistory"

    if is_diffview then
        menu.open(with_shared(require("lua.menus.diffview")))
    elseif filetype == "neo-tree" then
        menu.open(with_shared(require("lua.menus.neo-tree")))
    elseif filetype == "grug-far" then
        menu.open(with_shared(require("lua.menus.grug-far")))
    elseif filetype == "markdown" then
        menu.open(with_shared(require("lua.menus.markdown")))
    else
        menu.open(with_shared(require("lua.menus.mydefault")))
    end
end

return M
