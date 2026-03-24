local M = {}

local quit_locked = false

local function notify(message, level)
    vim.notify(message, level or vim.log.levels.INFO, { title = "Quit Guard" })
end

function M.is_locked()
    return quit_locked
end

function M.toggle()
    quit_locked = not quit_locked

    if quit_locked then
        notify("Leader quit is locked. <leader>q will be ignored.")
    else
        notify("Leader quit is unlocked. <leader>q can exit Neovim again.")
    end
end

function M.quit_all()
    if quit_locked then
        notify("Quit is locked. Open the menu and choose Unlock quit first.", vim.log.levels.WARN)
        return
    end

    vim.cmd("qa")
end

function M.menu_item()
    return {
        name = quit_locked and "Unlock quit" or "Lock quit",
        cmd = M.toggle,
        rtxt = "lq",
    }
end

return M
