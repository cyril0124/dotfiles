local M = {}

_G.global_wrap_enabled = true

local wrap_augroup = vim.api.nvim_create_augroup("GlobalWrapToggle", { clear = true })
vim.api.nvim_create_autocmd("WinEnter", {
    group = wrap_augroup,
    pattern = "*",
    callback = function()
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
        vim.wo[win].wrap = true
    end
    vim.notify("Line wrap ENABLED globally", vim.log.levels.INFO)
end

function M.disable()
    _G.global_wrap_enabled = false
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        vim.wo[win].wrap = false
    end
    vim.notify("Line wrap DISABLED globally", vim.log.levels.INFO)
end

return M
