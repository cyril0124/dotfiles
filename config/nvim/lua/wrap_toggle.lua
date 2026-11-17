local M = {}

_G.global_wrap_enabled = true

-- The outline sidebar manages its own wrap setting; the global toggle must not touch it.
local function is_outline(win)
    local buf = vim.api.nvim_win_get_buf(win)
    return vim.bo[buf].filetype == "Outline"
end

local wrap_augroup = vim.api.nvim_create_augroup("GlobalWrapToggle", { clear = true })
vim.api.nvim_create_autocmd("WinEnter", {
    group = wrap_augroup,
    pattern = "*",
    callback = function()
        if vim.api.nvim_win_get_config(0).relative ~= "" or is_outline(0) then
            return
        end

        if _G.global_wrap_enabled then
            vim.wo.wrap = true
        else
            vim.wo.wrap = false
        end
    end,
})

function M.enable()
    _G.global_wrap_enabled = true
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        if not is_outline(win) then
            vim.wo[win].wrap = true
        end
    end
    vim.notify("Line wrap ENABLED globally", vim.log.levels.INFO)
end

function M.disable()
    _G.global_wrap_enabled = false
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        if not is_outline(win) then
            vim.wo[win].wrap = false
        end
    end
    vim.notify("Line wrap DISABLED globally", vim.log.levels.INFO)
end

return M
