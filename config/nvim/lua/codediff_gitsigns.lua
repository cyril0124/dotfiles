local M = {}
local unpack_args = table.unpack or unpack

local cursor_actions = {
    preview_hunk = true,
    reset_hunk = true,
    stage_hunk = true,
}

local function get_gitsigns_cache()
    local ok, cache = pcall(require, "gitsigns.cache")
    if not ok then
        return nil
    end

    return cache.cache
end

local function is_attached(bufnr)
    local cache = get_gitsigns_cache()
    return cache ~= nil and cache[bufnr] ~= nil
end

local function get_session()
    local ok, lifecycle = pcall(require, "codediff.ui.lifecycle")
    if not ok then
        return nil
    end

    return lifecycle.get_session(vim.api.nvim_get_current_tabpage())
end

local function unique_windows(wins)
    local seen = {}
    local result = {}

    for _, winid in ipairs(wins) do
        if winid and not seen[winid] and vim.api.nvim_win_is_valid(winid) then
            seen[winid] = true
            result[#result + 1] = winid
        end
    end

    return result
end

local function find_target_window()
    local current_win = vim.api.nvim_get_current_win()
    if is_attached(vim.api.nvim_win_get_buf(current_win)) then
        return current_win
    end

    local session = get_session()
    if not session then
        return nil
    end

    for _, winid in ipairs(unique_windows({
        session.modified_win,
        session.result_win,
        session.original_win,
    })) do
        if is_attached(vim.api.nvim_win_get_buf(winid)) then
            return winid
        end
    end

    return nil
end

local function sync_cursor(source_win, target_win)
    if source_win == target_win then
        return
    end

    local source_cursor = vim.api.nvim_win_get_cursor(source_win)
    local target_buf = vim.api.nvim_win_get_buf(target_win)
    local target_line_count = vim.api.nvim_buf_line_count(target_buf)
    local target_line = math.min(source_cursor[1], math.max(target_line_count, 1))
    local target_line_text = vim.api.nvim_buf_get_lines(target_buf, target_line - 1, target_line, false)[1] or ""
    local target_col = math.min(source_cursor[2], #target_line_text)

    pcall(vim.api.nvim_win_set_cursor, target_win, { target_line, target_col })
end

function M.run(action, ...)
    local source_win = vim.api.nvim_get_current_win()
    local target_win = find_target_window()
    if not target_win then
        vim.notify("No gitsigns-attached buffer in current CodeDiff view", vim.log.levels.WARN)
        return
    end

    local gitsigns = require("gitsigns")
    local fn = gitsigns[action]
    if type(fn) ~= "function" then
        vim.notify("Unsupported gitsigns action: " .. tostring(action), vim.log.levels.ERROR)
        return
    end

    local args = { ... }
    vim.api.nvim_win_call(target_win, function()
        if cursor_actions[action] then
            sync_cursor(source_win, target_win)
        end
        fn(unpack_args(args))
    end)
end

return M
