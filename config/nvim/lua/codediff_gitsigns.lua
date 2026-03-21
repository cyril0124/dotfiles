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

local function is_real_file_buffer(bufnr)
    if not (bufnr and vim.api.nvim_buf_is_valid(bufnr)) then
        return false
    end

    if vim.bo[bufnr].buftype ~= "" then
        return false
    end

    local name = vim.api.nvim_buf_get_name(bufnr)
    if name == "" or name:match("^codediff://") then
        return false
    end

    return true
end

local function get_candidate_windows()
    local current_win = vim.api.nvim_get_current_win()
    local session = get_session()
    if not session then
        return unique_windows({ current_win })
    end

    return unique_windows({
        current_win,
        session.modified_win,
        session.result_win,
        session.original_win,
    })
end

local function try_attach_window(winid)
    if not (winid and vim.api.nvim_win_is_valid(winid)) then
        return false
    end

    local bufnr = vim.api.nvim_win_get_buf(winid)
    if is_attached(bufnr) then
        return true
    end

    if not is_real_file_buffer(bufnr) then
        return false
    end

    local ok, attach = pcall(require, "gitsigns.attach")
    if not ok then
        return false
    end

    attach.attach(bufnr, nil, nil)

    return vim.wait(800, function()
        return is_attached(bufnr)
    end, 20, false)
end

local function ensure_target_window()
    for _, winid in ipairs(get_candidate_windows()) do
        if try_attach_window(winid) then
            return winid
        end
    end

    return nil
end

local function notify_unavailable(action)
    local session = get_session()
    if not session then
        vim.notify("No gitsigns-attached buffer in current CodeDiff view", vim.log.levels.WARN)
        return
    end

    if session.modified_revision == ":0" then
        vim.notify(action .. " is unavailable in staged/index-only CodeDiff views", vim.log.levels.WARN)
        return
    end

    if session.modified_path == "" or session.modified_path == nil then
        vim.notify(action .. " requires a working-tree buffer; current CodeDiff entry is virtual or deleted", vim.log.levels.WARN)
        return
    end

    vim.notify("No gitsigns-attached buffer in current CodeDiff view", vim.log.levels.WARN)
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
    local target_win = ensure_target_window()
    if not target_win then
        notify_unavailable(action)
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
