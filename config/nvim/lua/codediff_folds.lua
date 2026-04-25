local M = {}

local state_by_tabpage = {}
local closing_session_by_tabpage = {}
local default_enabled = true
local profile_option_names = {
    "foldmethod",
    "foldenable",
    "foldlevel",
}

local cached_context_lines = nil
local restore_window_profile

local function get_session(tabpage)
    local ok, lifecycle = pcall(require, "codediff.ui.lifecycle")
    if not ok then
        return nil
    end

    return lifecycle.get_session(tabpage or vim.api.nvim_get_current_tabpage())
end

local function is_valid_window(winid)
    return winid and vim.api.nvim_win_is_valid(winid)
end

local function window_matches_buffer(winid, bufnr)
    return is_valid_window(winid)
        and bufnr
        and vim.api.nvim_buf_is_valid(bufnr)
        and vim.api.nvim_win_get_buf(winid) == bufnr
end

local function prune_state()
    local valid_tabs = {}
    for _, tabpage in ipairs(vim.api.nvim_list_tabpages()) do
        valid_tabs[tabpage] = true
    end

    for tabpage, _ in pairs(state_by_tabpage) do
        if not valid_tabs[tabpage] then
            state_by_tabpage[tabpage] = nil
        end
    end

    for tabpage, _ in pairs(closing_session_by_tabpage) do
        if not valid_tabs[tabpage] then
            closing_session_by_tabpage[tabpage] = nil
        end
    end
end

local function get_state(tabpage)
    if not state_by_tabpage[tabpage] then
        state_by_tabpage[tabpage] = {
            enabled = default_enabled,
            window_profiles = {},
            window_ids = {},
        }
    end

    return state_by_tabpage[tabpage]
end

local function invalidate_diffopt_cache()
    cached_context_lines = nil
end

local function is_supported_side_by_side(session)
    return session
        and session.layout ~= "inline"
        and session.original_win ~= session.modified_win
        and not (session.result_win and vim.api.nvim_win_is_valid(session.result_win))
        and window_matches_buffer(session.original_win, session.original_bufnr)
        and window_matches_buffer(session.modified_win, session.modified_bufnr)
end

local function capture_window_profile(state, side, winid)
    if not is_valid_window(winid) then
        return
    end

    local previous_winid = state.window_ids[side]
    if previous_winid and previous_winid ~= winid then
        restore_window_profile(state.window_profiles[side], previous_winid)
        state.window_profiles[side] = nil
    end

    state.window_ids[side] = winid

    if state.window_profiles[side] then
        return
    end

    local profile = {}
    for _, name in ipairs(profile_option_names) do
        profile[name] = vim.wo[winid][name]
    end
    state.window_profiles[side] = profile
end

restore_window_profile = function(profile, winid)
    if not profile or not is_valid_window(winid) then
        return
    end

    vim.api.nvim_win_call(winid, function()
        pcall(vim.cmd, "normal! zE")
        for name, value in pairs(profile) do
            vim.wo[winid][name] = value
        end
    end)
end

local function restore_tracked_window(state, side)
    restore_window_profile(state.window_profiles[side], state.window_ids[side])
    state.window_profiles[side] = nil
    state.window_ids[side] = nil
end

local function add_fold_range(ranges, start_line, end_line)
    if start_line > end_line then
        return
    end

    local last = ranges[#ranges]
    if last and start_line - last[2] == 1 then
        last[2] = end_line
        return
    end

    ranges[#ranges + 1] = { start_line, end_line }
end

local function get_diff_context_lines()
    if cached_context_lines ~= nil then
        return cached_context_lines
    end

    local context = 6

    for _, item in ipairs(vim.opt.diffopt:get()) do
        local value = item:match("^context:(%d+)$")
        if value then
            context = tonumber(value) or context
            break
        end
    end

    if context == 0 then
        context = 1
    end

    cached_context_lines = context
    return context
end

local function build_fold_ranges(changes, side, line_count)
    local ranges = {}
    local previous_last = 0
    local context = get_diff_context_lines()

    if context >= 999999 then
        return ranges
    end

    for index = 1, #changes + 1 do
        local mapping = changes[index]
        local first_line
        local last_line

        if mapping then
            local range = mapping[side]
            first_line = range.start_line
            last_line = range.end_line - 1
        else
            first_line = line_count + 1
        end

        if first_line - previous_last > 1 then
            local fold_start = previous_last + context + 1
            local fold_end = first_line - context - 1
            add_fold_range(ranges, fold_start, fold_end)
        end

        if mapping then
            previous_last = last_line
        end
    end

    return ranges
end

local function apply_window_folds(winid, folds)
    if not is_valid_window(winid) then
        return
    end

    vim.api.nvim_win_call(winid, function()
        vim.wo[winid].foldmethod = "manual"
        vim.wo[winid].foldenable = true
        pcall(vim.cmd, "normal! zE")

        for _, fold in ipairs(folds) do
            vim.cmd(string.format("%d,%dfold", fold[1], fold[2]))
        end

        vim.wo[winid].foldlevel = 0
        pcall(vim.cmd, "normal! zM")
    end)
end

local function resync_scrollbind(session)
    if not is_supported_side_by_side(session) then
        return
    end

    local original_cursor = vim.api.nvim_win_get_cursor(session.original_win)
    local modified_cursor = vim.api.nvim_win_get_cursor(session.modified_win)
    local current_tab = vim.api.nvim_get_current_tabpage()
    local target_tab = vim.api.nvim_win_get_tabpage(session.modified_win)

    vim.wo[session.original_win].scrollbind = false
    vim.wo[session.modified_win].scrollbind = false
    vim.wo[session.original_win].scrollbind = true
    vim.wo[session.modified_win].scrollbind = true

    pcall(vim.api.nvim_win_set_cursor, session.original_win, original_cursor)
    pcall(vim.api.nvim_win_set_cursor, session.modified_win, modified_cursor)

    if current_tab == target_tab then
        pcall(vim.cmd, "syncbind")
    end
end

local function clear_session_folds(tabpage, keep_enabled)
    local state = state_by_tabpage[tabpage]
    if not state then
        return
    end

    restore_tracked_window(state, "original")
    restore_tracked_window(state, "modified")

    if not keep_enabled then
        state_by_tabpage[tabpage] = nil
    end
end

local function clear_orphaned_folds()
    for tabpage, _ in pairs(state_by_tabpage) do
        if not get_session(tabpage) then
            clear_session_folds(tabpage, false)
        end
    end
end

local function sync_tracked_windows(tabpage)
    local state = state_by_tabpage[tabpage]
    if not state then
        return
    end

    local session = get_session(tabpage)
    if not session then
        clear_session_folds(tabpage, false)
        return
    end

    if state.window_ids.original and not window_matches_buffer(state.window_ids.original, session.original_bufnr) then
        restore_tracked_window(state, "original")
    end

    if state.window_ids.modified and not window_matches_buffer(state.window_ids.modified, session.modified_bufnr) then
        restore_tracked_window(state, "modified")
    end
end

local function sync_all_tracked_windows()
    for tabpage, _ in pairs(state_by_tabpage) do
        sync_tracked_windows(tabpage)
    end
end

function M.reapply(tabpage)
    tabpage = tabpage or vim.api.nvim_get_current_tabpage()

    local state = get_state(tabpage)
    if not state.enabled then
        return
    end

    local session = get_session(tabpage)
    if not session then
        clear_session_folds(tabpage, false)
        return
    end

    if not is_supported_side_by_side(session) then
        clear_session_folds(tabpage, true)
        return
    end

    local diff_result = session.stored_diff_result
    local changes = diff_result and diff_result.changes or nil

    capture_window_profile(state, "original", session.original_win)
    capture_window_profile(state, "modified", session.modified_win)

    if not (changes and #changes > 0) then
        clear_session_folds(tabpage, true)
        return
    end

    local original_line_count = vim.api.nvim_buf_line_count(session.original_bufnr)
    local modified_line_count = vim.api.nvim_buf_line_count(session.modified_bufnr)
    local original_folds = build_fold_ranges(changes, "original", original_line_count)
    local modified_folds = build_fold_ranges(changes, "modified", modified_line_count)

    apply_window_folds(session.original_win, original_folds)
    apply_window_folds(session.modified_win, modified_folds)
    resync_scrollbind(session)
end

function M.schedule_reapply(tabpage, delay_ms)
    tabpage = tabpage or vim.api.nvim_get_current_tabpage()
    local delay = delay_ms or 0
    local scheduled_session = get_session(tabpage)

    local function run()
        local closing_session = closing_session_by_tabpage[tabpage]
        if closing_session then
            if scheduled_session == closing_session then
                return
            end

            closing_session_by_tabpage[tabpage] = nil
        end

        M.reapply(tabpage)
    end

    if delay > 0 then
        vim.defer_fn(run, delay)
    else
        vim.schedule(run)
    end
end

function M.toggle_current_session()
    local tabpage = vim.api.nvim_get_current_tabpage()
    local session = get_session(tabpage)
    if not session then
        vim.notify("No active CodeDiff session", vim.log.levels.WARN)
        return
    end

    if not is_supported_side_by_side(session) then
        vim.notify("CodeDiff unchanged folds are only available in side-by-side view", vim.log.levels.WARN)
        return
    end

    local state = get_state(tabpage)
    closing_session_by_tabpage[tabpage] = nil
    state.enabled = not state.enabled

    if state.enabled then
        M.reapply(tabpage)
        return
    end

    clear_session_folds(tabpage, true)
end

function M.clear_closed(tabpage)
    if tabpage then
        closing_session_by_tabpage[tabpage] = get_session(tabpage)
        clear_session_folds(tabpage, false)
        return
    end

    clear_orphaned_folds()
end

local fold_group = vim.api.nvim_create_augroup("MyCodeDiffFoldPrune", { clear = true })

vim.api.nvim_create_autocmd("TabClosed", {
    group = fold_group,
    callback = function()
        prune_state()
        invalidate_diffopt_cache()
    end,
})

vim.api.nvim_create_autocmd("OptionSet", {
    group = fold_group,
    pattern = "diffopt",
    callback = invalidate_diffopt_cache,
})

vim.api.nvim_create_autocmd({ "BufWinEnter", "TabEnter" }, {
    group = fold_group,
    callback = function()
        vim.schedule(sync_all_tracked_windows)
    end,
})

return M
