return {
    "esmuellert/codediff.nvim",
    cmd = "CodeDiff",
    opts = {
        highlights = {
            char_insert = "#1f6a4a",
            char_delete = "#7a314d",
        },
        diff = {
            highlight_priority = 150,
        },
        explorer = {
            view_mode = "tree",
            flatten_dirs = false,
        },
    },
    config = function(_, opts)
        require("codediff.config").setup(opts)
        require("codediff.ui").setup_highlights()

        local codediff = require("lua.codediff")
        local codediff_folds = require("lua.codediff_folds")
        local lifecycle = require("codediff.ui.lifecycle")
        local lifecycle_state = require("codediff.ui.lifecycle.state")
        local layout = require("codediff.ui.layout")
        local explorer_refresh = require("codediff.ui.explorer.refresh")
        local view = require("codediff.ui.view")
        local inline_view = require("codediff.ui.view.inline_view")
        local side_by_side_view = require("codediff.ui.view.side_by_side")
        local welcome = require("codediff.ui.welcome")
        local welcome_window = require("codediff.ui.view.welcome_window")
        local active_diffs = require("codediff.ui.lifecycle.session").get_active_diffs
        local managed_markview_buffers = {}
        local option_names = {
            "number",
            "relativenumber",
            "signcolumn",
            "foldcolumn",
            "statuscolumn",
        }

        local original_apply = welcome_window.apply
        local original_resume_diff = lifecycle_state.resume_diff
        local original_explorer_refresh = explorer_refresh.refresh
        local original_view_update = view.update
        local original_inline_show_single_file = inline_view.show_single_file
        local original_inline_show_welcome = inline_view.show_welcome
        local original_side_show_untracked_file = side_by_side_view.show_untracked_file
        local original_side_show_deleted_file = side_by_side_view.show_deleted_file
        local original_side_show_added_virtual_file = side_by_side_view.show_added_virtual_file
        local original_side_show_deleted_virtual_file = side_by_side_view.show_deleted_virtual_file
        local original_side_show_welcome = side_by_side_view.show_welcome
        local function status_signature(status_result)
            local groups = { "conflicts", "unstaged", "staged" }
            local chunks = {}

            for _, group in ipairs(groups) do
                local items = {}
                for _, item in ipairs((status_result and status_result[group]) or {}) do
                    items[#items + 1] = table.concat({
                        item.path or "",
                        item.old_path or "",
                        item.status or "",
                    }, "\0")
                end
                table.sort(items)
                chunks[#chunks + 1] = group .. ":" .. table.concat(items, "\1")
            end

            return table.concat(chunks, "\2")
        end

        local function enable_wrap(winid)
            if winid and vim.api.nvim_win_is_valid(winid) then
                pcall(function()
                    vim.wo[winid].wrap = true
                end)
            end
        end

        local function safe_set_window_option(winid, name, value)
            return pcall(function()
                vim.wo[winid][name] = value
            end)
        end

        local function safe_get_window_option(winid, name)
            local ok, value = pcall(function()
                return vim.wo[winid][name]
            end)
            if not ok then
                return nil, false
            end
            return value, true
        end

        local function safe_apply_opts(winid, opts)
            if not (winid and vim.api.nvim_win_is_valid(winid)) then
                return false
            end

            local applied = false
            for name, value in pairs(opts or {}) do
                local current_value, ok = safe_get_window_option(winid, name)
                if not ok then
                    return applied
                end
                if current_value ~= value then
                    ok = safe_set_window_option(winid, name, value)
                    if not ok then
                        return applied
                    end
                end
                applied = true
            end

            return applied
        end

        local function apply_session_wrap(session)
            if not session then
                return
            end

            enable_wrap(session.original_win)
            enable_wrap(session.modified_win)
            enable_wrap(session.result_win)
        end

        local function is_listable_session_buffer(bufnr)
            if not (bufnr and vim.api.nvim_buf_is_valid(bufnr)) then
                return false
            end

            if welcome.is_welcome_buffer(bufnr) then
                return false
            end

            local name = vim.api.nvim_buf_get_name(bufnr)
            local buftype = vim.bo[bufnr].buftype

            if name == "" then
                return false
            end

            return buftype == "" or name:match("^codediff://") ~= nil
        end

        local function ensure_session_buflisted(session)
            if not session then
                return
            end

            local function mark_listed(bufnr)
                if is_listable_session_buffer(bufnr) then
                    pcall(function()
                        vim.bo[bufnr].buflisted = true
                    end)
                end
            end

            mark_listed(session.result_bufnr)
            mark_listed(session.modified_bufnr)
            mark_listed(session.original_bufnr)
        end

        local function ensure_current_session_buflisted(tabpage)
            ensure_session_buflisted(lifecycle.get_session(tabpage or vim.api.nvim_get_current_tabpage()))
        end

        local function apply_current_session_wrap(tabpage)
            apply_session_wrap(lifecycle.get_session(tabpage or vim.api.nvim_get_current_tabpage()))
        end

        local function schedule_current_session_wrap(tabpage)
            vim.schedule(function()
                apply_current_session_wrap(tabpage)
            end)
        end

        local function get_markview_modules()
            local ok_commands, commands = pcall(require, "markview.commands")
            local ok_state, state = pcall(require, "markview.state")
            if not (ok_commands and ok_state) then
                return nil, nil
            end

            return commands, state
        end

        local function buffer_in_active_diff(bufnr)
            if not (bufnr and vim.api.nvim_buf_is_valid(bufnr)) then
                return false
            end

            for _, session in pairs(active_diffs()) do
                if session.original_bufnr == bufnr or session.modified_bufnr == bufnr or session.result_bufnr == bufnr then
                    return true
                end
            end

            return false
        end

        local function disable_markview(bufnr)
            local commands, state = get_markview_modules()
            if not (commands and state) then
                return
            end

            if not (bufnr and vim.api.nvim_buf_is_valid(bufnr)) then
                return
            end

            if not state.buf_attached(bufnr) then
                return
            end

            local buffer_state = state.get_buffer_state(bufnr, false)
            if not (buffer_state and buffer_state.enable) then
                return
            end

            commands.disable(bufnr)
            managed_markview_buffers[bufnr] = true
        end

        local function restore_markview(bufnr)
            local commands, state = get_markview_modules()
            if not (commands and state) then
                return
            end

            if not (bufnr and vim.api.nvim_buf_is_valid(bufnr)) then
                if bufnr then
                    managed_markview_buffers[bufnr] = nil
                end
                return
            end

            if buffer_in_active_diff(bufnr) then
                return
            end

            if not state.buf_attached(bufnr) then
                managed_markview_buffers[bufnr] = nil
                return
            end

            local buffer_state = state.get_buffer_state(bufnr, false)
            if buffer_state and not buffer_state.enable then
                commands.enable(bufnr)
            end

            managed_markview_buffers[bufnr] = nil
        end

        local function sync_markview(tabpage)
            local session = tabpage and lifecycle.get_session(tabpage) or nil
            if session then
                disable_markview(session.original_bufnr)
                disable_markview(session.modified_bufnr)
                disable_markview(session.result_bufnr)
            end

            for bufnr, _ in pairs(managed_markview_buffers) do
                restore_markview(bufnr)
            end
        end

        local function schedule_markview_sync(tabpage, delay_ms)
            local function sync()
                sync_markview(tabpage)
            end

            if delay_ms and delay_ms > 0 then
                vim.defer_fn(sync, delay_ms)
            else
                vim.schedule(sync)
            end
        end

        local function schedule_markview_restore(delay_ms, attempts_left)
            vim.defer_fn(function()
                sync_markview(nil)

                if attempts_left > 1 and next(managed_markview_buffers) ~= nil then
                    schedule_markview_restore(80, attempts_left - 1)
                end
            end, delay_ms)
        end

        local function apply_explorer_window_opts(winid)
            if not (winid and vim.api.nvim_win_is_valid(winid)) then
                return
            end

            pcall(function()
                vim.wo[winid].foldenable = false
                vim.wo[winid].foldmethod = "manual"
                vim.wo[winid].foldlevel = 99
            end)
        end

        local function apply_current_explorer_window_opts(tabpage)
            local explorer = lifecycle.get_explorer(tabpage or vim.api.nvim_get_current_tabpage())
            if not explorer then
                return
            end

            apply_explorer_window_opts(explorer.winid or (explorer.split and explorer.split.winid))
        end

        local function schedule_current_explorer_window_opts(tabpage, delay_ms)
            local function sync()
                apply_current_explorer_window_opts(tabpage)
            end

            if delay_ms and delay_ms > 0 then
                vim.defer_fn(sync, delay_ms)
            else
                vim.schedule(sync)
            end
        end

        local function arrange_session(tabpage)
            tabpage = tabpage or vim.api.nvim_get_current_tabpage()
            if not lifecycle.get_session(tabpage) then
                return
            end

            layout.arrange(tabpage)
            apply_current_session_wrap(tabpage)
            apply_current_explorer_window_opts(tabpage)
        end

        local function schedule_layout_sync(tabpage, delay_ms)
            local function sync()
                arrange_session(tabpage)
            end

            if delay_ms and delay_ms > 0 then
                vim.defer_fn(sync, delay_ms)
            else
                vim.schedule(sync)
            end
        end

        local function expand_explorer_root_groups(explorer)
            if not (explorer and explorer.tree) then
                return
            end

            local changed = false
            for _, node in ipairs(explorer.tree:get_nodes() or {}) do
                if node.data and node.data.type == "group" and not node:is_expanded() then
                    node:expand()
                    changed = true
                end
            end

            if changed then
                pcall(function()
                    explorer.tree:render()
                end)
            end
        end

        local function schedule_explorer_root_groups(tabpage, delay_ms)
            local function sync()
                expand_explorer_root_groups(lifecycle.get_explorer(tabpage or vim.api.nvim_get_current_tabpage()))
            end

            if delay_ms and delay_ms > 0 then
                vim.defer_fn(sync, delay_ms)
            else
                vim.schedule(sync)
            end
        end

        local function schedule_explorer_sync(tabpage, opts_delay, groups_delay)
            schedule_current_explorer_window_opts(tabpage, opts_delay or 20)
            schedule_explorer_root_groups(tabpage, groups_delay or 60)
            schedule_markview_sync(tabpage, opts_delay or 20)
        end

        local function wrap_with_explorer_sync(fn, opts_delay, groups_delay)
            return function(tabpage, ...)
                local result = fn(tabpage, ...)
                schedule_explorer_sync(tabpage, opts_delay, groups_delay)
                codediff_folds.schedule_reapply(tabpage, math.max(opts_delay or 20, groups_delay or 40))
                return result
            end
        end

        local function get_session_for_window(winid)
            for _, sess in pairs(active_diffs()) do
                if sess.original_win == winid then
                    return sess, "original"
                end
                if sess.modified_win == winid then
                    return sess, "modified"
                end
            end

            return nil, nil
        end

        local function matches_profile(winid, profile)
            if not profile then
                return false
            end

            for _, name in ipairs(option_names) do
                local current_value, ok = safe_get_window_option(winid, name)
                if not ok or current_value ~= profile[name] then
                    return false
                end
            end

            return true
        end

        welcome_window.apply = function(winid)
            if not (winid and vim.api.nvim_win_is_valid(winid)) then
                return
            end

            pcall(original_apply, winid)
            enable_wrap(winid)
        end

        welcome_window.apply_normal = function(winid)
            if not (winid and vim.api.nvim_win_is_valid(winid)) then
                return
            end

            local sess, side = get_session_for_window(winid)
            if not sess or not side then
                return
            end

            welcome_window.capture_session_profiles(sess)
            local normal_opts = sess.window_profiles and sess.window_profiles[side]
            if not normal_opts then
                return
            end

            safe_apply_opts(winid, normal_opts)
            enable_wrap(winid)
        end

        welcome_window.sync = function(winid)
            if not (winid and vim.api.nvim_win_is_valid(winid)) then
                return
            end

            local bufnr = vim.api.nvim_win_get_buf(winid)
            if welcome.is_welcome_buffer(bufnr) then
                welcome_window.apply(winid)
                return
            end

            local sess, side = get_session_for_window(winid)
            if not sess or not side then
                return
            end

            welcome_window.capture_session_profiles(sess)
            local normal_opts = sess.window_profiles and sess.window_profiles[side]
            if matches_profile(winid, normal_opts) then
                enable_wrap(winid)
                return
            end

            welcome_window.apply_normal(winid)
        end

        welcome_window.sync_later = function(winid)
            vim.schedule(function()
                welcome_window.sync(winid)
            end)
        end

        view.update = wrap_with_explorer_sync(original_view_update)
        inline_view.show_single_file = wrap_with_explorer_sync(original_inline_show_single_file)
        inline_view.show_welcome = wrap_with_explorer_sync(original_inline_show_welcome)
        side_by_side_view.show_untracked_file = wrap_with_explorer_sync(original_side_show_untracked_file)
        side_by_side_view.show_deleted_file = wrap_with_explorer_sync(original_side_show_deleted_file)
        side_by_side_view.show_added_virtual_file = wrap_with_explorer_sync(original_side_show_added_virtual_file)
        side_by_side_view.show_deleted_virtual_file = wrap_with_explorer_sync(original_side_show_deleted_virtual_file)
        side_by_side_view.show_welcome = wrap_with_explorer_sync(original_side_show_welcome)

        lifecycle_state.resume_diff = function(tabpage)
            original_resume_diff(tabpage)
            schedule_layout_sync(tabpage, 20)
            apply_current_session_wrap(tabpage)
            ensure_current_session_buflisted(tabpage)
            schedule_explorer_sync(tabpage, 20, 40)
            codediff_folds.schedule_reapply(tabpage, 60)
        end

        explorer_refresh.refresh = function(explorer)
            if not explorer or not explorer.git_root or explorer.base_revision or explorer.target_revision then
                return original_explorer_refresh(explorer)
            end

            local git = require("codediff.core.git")
            git.get_status(explorer.git_root, function(err, status_result)
                vim.schedule(function()
                    if err then
                        vim.notify("Failed to refresh: " .. err, vim.log.levels.ERROR)
                        return
                    end

                    local previous = status_signature(explorer.status_result)
                    local current = status_signature(status_result)
                    if previous == current then
                        return
                    end

                    original_explorer_refresh(explorer)
                    schedule_explorer_sync(explorer.tabpage, 20, 20)
                end)
            end)
        end

        local group = vim.api.nvim_create_augroup("MyCodeDiffDefaultWrap", { clear = true })

        vim.api.nvim_create_autocmd("User", {
            group = group,
            pattern = "CodeDiffOpen",
            callback = function(ev)
                local tabpage = ev.data and ev.data.tabpage or nil
                schedule_layout_sync(tabpage, 20)
                schedule_current_session_wrap(tabpage)
                ensure_current_session_buflisted(tabpage)
                schedule_explorer_sync(tabpage, 20, 40)
                codediff_folds.schedule_reapply(tabpage, 60)
            end,
        })

        vim.api.nvim_create_autocmd("VimResized", {
            group = group,
            callback = function()
                schedule_layout_sync(nil, 20)
            end,
        })

        vim.api.nvim_create_autocmd("User", {
            group = group,
            pattern = "CodeDiffFileSelect",
            callback = function(ev)
                local tabpage = ev.data and ev.data.tabpage or nil
                schedule_explorer_sync(tabpage)
                codediff_folds.schedule_reapply(tabpage, 60)
            end,
        })

        vim.api.nvim_create_autocmd("User", {
            group = group,
            pattern = "CodeDiffClose",
            callback = function(ev)
                schedule_markview_restore(20, 6)
                codediff_folds.clear_closed(ev.data and ev.data.tabpage or nil)
            end,
        })

        vim.api.nvim_create_autocmd("User", {
            group = group,
            pattern = { "MarkviewAttach", "MarkviewEnable" },
            callback = function(ev)
                local bufnr = ev.data and ev.data.buffer or ev.buf
                if not (buffer_in_active_diff(bufnr) or managed_markview_buffers[bufnr]) then
                    return
                end

                disable_markview(bufnr)
            end,
        })

        vim.api.nvim_create_autocmd("BufWinEnter", {
            group = group,
            callback = function(ev)
                local tabpage = vim.api.nvim_get_current_tabpage()
                if not lifecycle.get_session(tabpage) then
                    return
                end

                if is_listable_session_buffer(ev.buf) then
                    disable_markview(ev.buf)
                    codediff.set_tabline_buffer(tabpage, ev.buf)
                    pcall(function()
                        vim.bo[ev.buf].buflisted = true
                    end)
                    vim.schedule(function()
                        pcall(vim.cmd, "redrawtabline")
                    end)
                    schedule_markview_sync(tabpage, 20)
                end

                if vim.bo[ev.buf].filetype == "codediff-explorer" then
                    apply_explorer_window_opts(vim.api.nvim_get_current_win())
                end
            end,
        })
    end,
}
