local M = {}
local shared = require("lua.codediff_shared")
local transition_delay_ms = 120
local state = {
    initialized = false,
    transitioning = false,
    last_close_ms = 0,
    ui_suspended = false,
    paused_winsep = false,
    tabline_buffers = {},
}

local function now_ms()
    return vim.uv.now()
end

local function run_safely(fn, context)
    local ok, err = xpcall(fn, debug.traceback)
    if ok then
        return true
    end

    vim.schedule(function()
        vim.notify((context or "CodeDiff action") .. " failed: " .. tostring(err), vim.log.levels.ERROR)
    end)
    return false
end

local function is_valid_window(winid)
    return winid and vim.api.nvim_win_is_valid(winid)
end

local function is_floating_window(winid)
    if not is_valid_window(winid) then
        return false
    end

    local config = vim.api.nvim_win_get_config(winid)
    return config.relative ~= nil and config.relative ~= ""
end

local function get_session(tabpage)
    return shared.get_session(tabpage)
end

local function is_tabline_candidate(bufnr)
    return shared.is_listable_buffer(bufnr)
end

local function get_window_buffer(winid)
    if not is_valid_window(winid) then
        return nil
    end

    local bufnr = vim.api.nvim_win_get_buf(winid)
    if not is_tabline_candidate(bufnr) then
        return nil
    end

    return bufnr
end

local function remember_tabline_buffer(tabpage, bufnr)
    if not (tabpage and vim.api.nvim_tabpage_is_valid(tabpage)) then
        return nil
    end

    if not is_tabline_candidate(bufnr) then
        return nil
    end

    state.tabline_buffers[tabpage] = bufnr
    return bufnr
end

local function get_live_tabline_buffer(tabpage)
    local session = get_session(tabpage)
    if not session then
        state.tabline_buffers[tabpage] = nil
        return nil
    end

    local current_tab = vim.api.nvim_get_current_tabpage()
    if current_tab == tabpage then
        local current_win = vim.api.nvim_get_current_win()
        if current_win == session.modified_win or current_win == session.result_win or current_win == session.original_win then
            local current_buf = get_window_buffer(current_win)
            if current_buf then
                return remember_tabline_buffer(tabpage, current_buf)
            end
        end
    end

    for _, winid in ipairs({ session.modified_win, session.result_win, session.original_win }) do
        local bufnr = get_window_buffer(winid)
        if bufnr then
            return remember_tabline_buffer(tabpage, bufnr)
        end
    end

    return nil
end

local function prune_tabline_buffers()
    for tabpage, _ in pairs(state.tabline_buffers) do
        if not vim.api.nvim_tabpage_is_valid(tabpage) then
            state.tabline_buffers[tabpage] = nil
        end
    end
end

local function build_outside_context()
    local session = get_session()
    if not session then
        return nil
    end

    local function resolve_existing_file(path)
        if type(path) ~= "string" or path == "" then
            return nil
        end

        if path:match("^codediff://") then
            return nil
        end

        if vim.fn.filereadable(path) == 1 then
            return path
        end

        if session.git_root then
            local candidate = vim.fs.joinpath(session.git_root, path)
            if vim.fn.filereadable(candidate) == 1 then
                return candidate
            end
        end

        return nil
    end

    local function context_from_buffer(bufnr)
        if not shared.is_real_file_buffer(bufnr) then
            return nil
        end

        local file = vim.api.nvim_buf_get_name(bufnr)
        if file == "" then
            return nil
        end

        return {
            file = file,
            cwd = session.git_root or vim.fs.dirname(file),
        }
    end

    local current_context = context_from_buffer(vim.api.nvim_get_current_buf())
    if current_context then
        return current_context
    end

    for _, bufnr in ipairs({ session.modified_bufnr, session.result_bufnr, session.original_bufnr }) do
        local context = context_from_buffer(bufnr)
        if context then
            return context
        end
    end

    local file = resolve_existing_file(session.modified_path) or resolve_existing_file(session.original_path)
    if not file and not session.git_root then
        return nil
    end

    return {
        file = file,
        cwd = session.git_root or (file and vim.fs.dirname(file) or nil),
    }
end

local function apply_outside_context(context)
    if not context then
        return
    end

    if context.cwd and context.cwd ~= "" then
        local ok, err = pcall(vim.cmd, "tcd " .. vim.fn.fnameescape(context.cwd))
        if not ok then
            vim.schedule(function()
                vim.notify("CodeDiff context tcd failed: " .. tostring(err), vim.log.levels.WARN)
            end)
        end
    end

    if context.file and context.file ~= "" then
        local ok, err = pcall(vim.cmd, "edit " .. vim.fn.fnameescape(context.file))
        if not ok then
            vim.schedule(function()
                vim.notify("CodeDiff context edit failed: " .. tostring(err), vim.log.levels.WARN)
            end)
        end
    end
end

local function suspend_ui_effects()
    local ok_winsep, winsep = pcall(require, "colorful-winsep")
    if ok_winsep and winsep.enabled then
        state.paused_winsep = true
        winsep.disable()
    end
end

local function resume_ui_effects()
    if state.paused_winsep then
        local ok_winsep, winsep = pcall(require, "colorful-winsep")
        if ok_winsep then
            winsep.enable()
        end
        state.paused_winsep = false
    end
end

local function sync_ui_effects()
    local should_suspend = M.is_current_session()
    if should_suspend == state.ui_suspended then
        return
    end

    state.ui_suspended = should_suspend
    if should_suspend then
        suspend_ui_effects()
    else
        resume_ui_effects()
    end
end

local function get_explorer_window(tabpage)
    return shared.get_explorer_window(tabpage)
end

local function get_window_box(winid)
    if not is_valid_window(winid) or is_floating_window(winid) then
        return nil
    end

    local pos = vim.api.nvim_win_get_position(winid)
    local width = vim.api.nvim_win_get_width(winid)
    local height = vim.api.nvim_win_get_height(winid)
    local row = pos[1]
    local col = pos[2]

    return {
        winid = winid,
        top = row,
        bottom = row + height - 1,
        left = col,
        right = col + width - 1,
        center_row = row + (height / 2),
        center_col = col + (width / 2),
    }
end

local function collect_session_windows(tabpage)
    local session = get_session(tabpage)
    if not session then
        return {}
    end

    local seen = {}
    local boxes = {}

    local function add_window(winid)
        if seen[winid] then
            return
        end

        local box = get_window_box(winid)
        if not box then
            return
        end

        seen[winid] = true
        table.insert(boxes, box)
    end

    add_window(session.original_win)
    add_window(session.modified_win)
    add_window(session.result_win)
    add_window(get_explorer_window(tabpage))

    return boxes
end

local function find_navigation_target(direction)
    local current_tab = vim.api.nvim_get_current_tabpage()
    local current_win = vim.api.nvim_get_current_win()
    local current_box = get_window_box(current_win)
    if not current_box then
        return nil
    end

    local best_win = nil
    local best_score = nil

    for _, candidate in ipairs(collect_session_windows(current_tab)) do
        if candidate.winid ~= current_win then
            local primary_distance = nil
            local lateral_distance = nil
            local overlaps_axis = false

            if direction == "left" and candidate.center_col < current_box.center_col then
                primary_distance = current_box.center_col - candidate.center_col
                lateral_distance = math.abs(candidate.center_row - current_box.center_row)
                overlaps_axis = candidate.bottom >= current_box.top and candidate.top <= current_box.bottom
            elseif direction == "right" and candidate.center_col > current_box.center_col then
                primary_distance = candidate.center_col - current_box.center_col
                lateral_distance = math.abs(candidate.center_row - current_box.center_row)
                overlaps_axis = candidate.bottom >= current_box.top and candidate.top <= current_box.bottom
            elseif direction == "up" and candidate.center_row < current_box.center_row then
                primary_distance = current_box.center_row - candidate.center_row
                lateral_distance = math.abs(candidate.center_col - current_box.center_col)
                overlaps_axis = candidate.right >= current_box.left and candidate.left <= current_box.right
            elseif direction == "down" and candidate.center_row > current_box.center_row then
                primary_distance = candidate.center_row - current_box.center_row
                lateral_distance = math.abs(candidate.center_col - current_box.center_col)
                overlaps_axis = candidate.right >= current_box.left and candidate.left <= current_box.right
            end

            if primary_distance then
                local score = (primary_distance * 1000) + lateral_distance + (overlaps_axis and 0 or 1000000)
                if not best_score or score < best_score then
                    best_score = score
                    best_win = candidate.winid
                end
            end
        end
    end

    return best_win
end

local function ensure_autocmds()
    if state.initialized then
        return
    end

    local group = vim.api.nvim_create_augroup("MyCodeDiffWrapper", { clear = true })

    vim.api.nvim_create_autocmd("User", {
        group = group,
        pattern = "CodeDiffOpen",
        callback = function()
            state.transitioning = false
            vim.schedule(sync_ui_effects)
        end,
    })

    vim.api.nvim_create_autocmd("User", {
        group = group,
        pattern = "CodeDiffClose",
        callback = function()
            state.last_close_ms = now_ms()
            state.transitioning = true
            vim.defer_fn(function()
                state.transitioning = false
            end, transition_delay_ms)
            vim.schedule(sync_ui_effects)
        end,
    })

    vim.api.nvim_create_autocmd({ "TabEnter", "WinEnter" }, {
        group = group,
        callback = function()
            vim.schedule(sync_ui_effects)
        end,
    })

    vim.api.nvim_create_autocmd("BufWinEnter", {
        group = group,
        callback = function(args)
            local tabpage = vim.api.nvim_get_current_tabpage()
            local session = get_session(tabpage)
            if not session then
                return
            end

            local current_win = vim.api.nvim_get_current_win()
            if not shared.is_session_window(current_win, session) then
                return
            end

            remember_tabline_buffer(tabpage, args.buf)
        end,
    })

    state.initialized = true
end

local function build_command(args)
    if args and args ~= "" then
        return "CodeDiff " .. args
    end

    return "CodeDiff"
end

local function run_command(command, delay_ms)
    local run = function()
        local ok, err = pcall(vim.cmd, command)
        if not ok then
            vim.notify("CodeDiff failed: " .. tostring(err), vim.log.levels.ERROR)
        end
    end

    if delay_ms and delay_ms > 0 then
        vim.defer_fn(run, delay_ms)
    else
        run()
    end
end

function M.is_current_session()
    ensure_autocmds()
    return get_session() ~= nil
end

function M.set_tabline_buffer(tabpage, bufnr)
    ensure_autocmds()
    prune_tabline_buffers()
    tabpage = tabpage or vim.api.nvim_get_current_tabpage()
    return remember_tabline_buffer(tabpage, bufnr)
end

function M.get_tabline_buffer(tabpage)
    ensure_autocmds()
    prune_tabline_buffers()

    tabpage = tabpage or vim.api.nvim_get_current_tabpage()
    local session = get_session(tabpage)
    if not session then
        state.tabline_buffers[tabpage] = nil
        return nil
    end

    local cached_buf = state.tabline_buffers[tabpage]
    if is_tabline_candidate(cached_buf) then
        return cached_buf
    end

    state.tabline_buffers[tabpage] = nil
    return get_live_tabline_buffer(tabpage)
end

function M.close_current()
    ensure_autocmds()

    if M.is_current_session() then
        state.transitioning = true
        local ok, err = pcall(vim.cmd, "CodeDiff")
        if ok then
            return true
        end

        state.transitioning = false
        vim.notify("CodeDiff failed: " .. tostring(err), vim.log.levels.ERROR)
    end

    return false
end

function M.open(args)
    ensure_autocmds()

    local command = build_command(args)
    local delay_ms = 0
    local elapsed_since_close = now_ms() - state.last_close_ms

    if M.is_current_session() and args and args ~= "" then
        M.run_outside_current_session(function()
            local reopen_delay = 0
            local elapsed = now_ms() - state.last_close_ms
            if state.transitioning or elapsed < transition_delay_ms then
                reopen_delay = math.max(reopen_delay, transition_delay_ms - elapsed)
            end
            run_command(command, reopen_delay)
        end)
        return
    end

    if state.transitioning or elapsed_since_close < transition_delay_ms then
        delay_ms = math.max(delay_ms, transition_delay_ms - elapsed_since_close)
    end

    run_command(command, delay_ms)
end

function M.run_outside_current_session(fn)
    ensure_autocmds()

    if type(fn) ~= "function" then
        return false
    end

    if not M.is_current_session() then
        return run_safely(fn, "CodeDiff external action")
    end

    local outside_context = build_outside_context()

    if #vim.api.nvim_list_tabpages() == 1 then
        local current_tab = vim.api.nvim_get_current_tabpage()
        vim.cmd("tabnew")
        apply_outside_context(outside_context)

        local ok = run_safely(function()
            vim.cmd(vim.api.nvim_tabpage_get_number(current_tab) .. "tabclose")
        end, "CodeDiff close")

        if not ok then
            run_safely(function()
                vim.cmd("tabclose")
            end, "CodeDiff rollback")
            return false
        end

        return run_safely(fn, "CodeDiff external action")
    end

    if not M.close_current() then
        return false
    end

    vim.defer_fn(function()
        run_safely(fn, "CodeDiff external action")
    end, transition_delay_ms)
    return true
end

function M.navigate(direction)
    ensure_autocmds()

    if not M.is_current_session() then
        return false
    end

    local target_win = find_navigation_target(direction)
    if not target_win then
        return false
    end

    vim.api.nvim_set_current_win(target_win)
    return true
end

return M
