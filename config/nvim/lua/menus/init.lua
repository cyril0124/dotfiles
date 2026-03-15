local M = {}

function M.show()
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

return M
