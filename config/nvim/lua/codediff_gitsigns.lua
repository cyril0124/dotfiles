local M = {}
local unpack_args = table.unpack or unpack
local shared = require("lua.codediff_shared")

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
    return shared.get_session()
end

local function to_relative_path(git_root, path)
    if not (git_root and path and path ~= "") then
        return nil
    end

    return vim.fs.relpath(git_root, path) or path
end

local function get_explorer()
    local session = get_session()
    return session and session.mode == "explorer" and session.explorer or nil
end

local function is_conflict_revision(revision)
    return revision == ":2" or revision == ":3"
end

local function is_conflict_session(session)
    return session
        and (is_conflict_revision(session.original_revision) or is_conflict_revision(session.modified_revision))
        or false
end

local function get_current_buf()
    return vim.api.nvim_get_current_buf()
end

local function in_explorer_buffer(explorer, bufnr)
    return explorer and explorer.bufnr and bufnr == explorer.bufnr
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
    return shared.is_real_file_buffer(bufnr)
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

local function get_view_keymap_lhs(action)
    local ok, config = pcall(require, "codediff.config")
    if not ok then
        return nil
    end

    local keymaps = config.options and config.options.keymaps
    keymaps = keymaps and keymaps.view or nil
    if type(keymaps) ~= "table" then
        return nil
    end

    return keymaps[action]
end

local function find_buffer_keymap_callback(bufnr, lhs)
    if not (bufnr and vim.api.nvim_buf_is_valid(bufnr)) then
        return nil
    end

    return vim.api.nvim_buf_call(bufnr, function()
        local map = vim.fn.maparg(lhs, "n", false, true)
        return map and type(map.callback) == "function" and map.callback or nil
    end)
end

local function get_preferred_diff_window()
    local session = get_session()
    if not session then
        return nil
    end

    local current_win = vim.api.nvim_get_current_win()
    if current_win == session.original_win or current_win == session.modified_win then
        return current_win
    end

    if session.modified_win and vim.api.nvim_win_is_valid(session.modified_win) then
        return session.modified_win
    end

    if session.original_win and vim.api.nvim_win_is_valid(session.original_win) then
        return session.original_win
    end

    return nil
end

local function run_codediff_hunk_action(action)
    local target_win = get_preferred_diff_window()
    if not target_win then
        vim.notify("No active CodeDiff diff window", vim.log.levels.WARN)
        return true
    end

    local bufnr = vim.api.nvim_win_get_buf(target_win)
    local lhs = get_view_keymap_lhs(action)
    local callback = lhs and find_buffer_keymap_callback(bufnr, lhs) or nil
    if not callback then
        vim.notify("CodeDiff hunk action is unavailable in the current view", vim.log.levels.WARN)
        return true
    end

    vim.api.nvim_win_call(target_win, callback)
    return true
end

local function notify_file_action_unavailable(action, reason)
    local label = action == "stage_buffer" and "Stage buffer" or "Reset buffer"

    if reason == "history" then
        vim.notify(label .. " is unavailable in CodeDiff history views", vim.log.levels.WARN)
        return
    end

    if reason == "conflicts" then
        vim.notify(label .. " is unavailable in CodeDiff conflict views", vim.log.levels.WARN)
        return
    end

    if reason == "immutable" then
        vim.notify(label .. " is unavailable in revision-only CodeDiff views", vim.log.levels.WARN)
        return
    end
end

local function get_current_file_context()
    local session = get_session()
    if not (session and session.git_root) then
        vim.notify("Not in a git repository", vim.log.levels.WARN)
        return nil, "not_git"
    end

    local explorer = get_explorer()
    if explorer and explorer.current_file_path then
        local selection = explorer.current_selection
        local status = selection and selection.path == explorer.current_file_path and selection.status or nil
        return {
            git_root = session.git_root,
            rel_path = explorer.current_file_path,
            group = explorer.current_file_group,
            status = status,
            base_revision = explorer.base_revision,
        }
    end

    if session.mode == "history" then
        return nil, "history"
    end

    local original_rel = to_relative_path(session.git_root, session.original_path)
    local modified_rel = to_relative_path(session.git_root, session.modified_path)
    local rel_path = original_rel or modified_rel
    if not rel_path then
        vim.notify("No file selected in current CodeDiff view", vim.log.levels.WARN)
        return nil, "no_file"
    end

    if is_conflict_session(session) then
        return nil, "conflicts"
    end

    if session.modified_revision ~= nil and session.modified_revision ~= ":0" then
        return nil, "immutable"
    end

    return {
        git_root = session.git_root,
        rel_path = rel_path,
        group = session.modified_revision == ":0" and "staged" or "unstaged",
        status = (not original_rel and modified_rel and session.modified_revision == nil) and "??" or nil,
        base_revision = explorer and explorer.base_revision or nil,
    }
end

local function notify_git_error(err)
    if err then
        vim.schedule(function()
            vim.notify(err, vim.log.levels.ERROR)
        end)
    end
end

local function confirm_reset(rel_path, is_untracked)
    local prompt = (is_untracked and "Delete " or "Discard changes to ") .. rel_path .. "?"
    local choice = vim.fn.confirm(prompt, "&Discard\n&Cancel", 2, "Warning")
    vim.cmd("echo ''")
    return choice == 1
end

local function run_explorer_file_action(action, explorer)
    local explorer_module = require("codediff.ui.explorer")

    if action == "stage_buffer" then
        explorer_module.toggle_stage_entry(explorer, explorer.tree)
        return true
    end

    if action == "reset_buffer" then
        explorer_module.restore_entry(explorer, explorer.tree)
        return true
    end

    return false
end

local function run_diff_file_action(action)
    local explorer = get_explorer()
    local session = get_session()
    local ctx, reason = get_current_file_context()
    if not ctx then
        if reason then
            notify_file_action_unavailable(action, reason)
        end
        return true
    end

    local explorer_module = require("codediff.ui.explorer")
    local git = require("codediff.core.git")
    if action == "stage_buffer" then
        if ctx.group ~= nil and (ctx.group == "staged" or ctx.group == "unstaged" or ctx.group == "conflicts") then
            explorer_module.toggle_stage_file(ctx.git_root, ctx.rel_path, ctx.group)
            return true
        end

        if session and session.modified_revision == ":0" then
            vim.notify("Current file is already staged in this CodeDiff view", vim.log.levels.INFO)
            return true
        end

        git.stage_file(ctx.git_root, ctx.rel_path, notify_git_error)
        return true
    end

    if action == "reset_buffer" then
        if ctx.group == "conflicts" then
            notify_file_action_unavailable(action, "conflicts")
            return true
        end

        if ctx.group == "staged" then
            vim.notify("Reset buffer only works on unstaged changes", vim.log.levels.WARN)
            return true
        end

        local is_untracked = ctx.status == "??"
        if not confirm_reset(ctx.rel_path, is_untracked) then
            return true
        end

        if is_untracked then
            git.delete_untracked(ctx.git_root, ctx.rel_path, notify_git_error)
        else
            git.restore_file(ctx.git_root, ctx.rel_path, ctx.base_revision, notify_git_error)
        end
        return true
    end

    return false
end

local function run_file_action(action)
    local session = get_session()
    local explorer = session and session.mode == "explorer" and get_explorer() or nil
    if not explorer then
        return run_diff_file_action(action)
    end

    if in_explorer_buffer(explorer, get_current_buf()) then
        local ok = run_explorer_file_action(action, explorer)
        if ok then
            return true
        end
    end

    return run_diff_file_action(action)
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
    if action == "stage_hunk" then
        return run_codediff_hunk_action(action)
    end

    if action == "undo_stage_hunk" then
        return run_codediff_hunk_action("unstage_hunk")
    end

    if action == "reset_hunk" then
        return run_codediff_hunk_action("discard_hunk")
    end

    if action == "stage_buffer" or action == "reset_buffer" then
        return run_file_action(action)
    end

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
