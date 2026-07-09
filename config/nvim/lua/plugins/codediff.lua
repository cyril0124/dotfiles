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
        local codediff_shared = require("lua.codediff_shared")
        local lifecycle = require("codediff.ui.lifecycle")
        local lifecycle_state = require("codediff.ui.lifecycle.state")
        local layout = require("codediff.ui.layout")
        local explorer_actions = require("codediff.ui.explorer.actions")
        local explorer_refresh = require("codediff.ui.explorer.refresh")
        local view = require("codediff.ui.view")
        local inline_view = require("codediff.ui.view.inline_view")
        local side_by_side_view = require("codediff.ui.view.side_by_side")
        local welcome = require("codediff.ui.welcome")
        local welcome_window = require("codediff.ui.view.welcome_window")
        local active_diffs = require("codediff.ui.lifecycle.session").get_active_diffs
        local diff_result = require("lua.codediff_diff_result")
        local swap_guard = require("lua.codediff_swap_guard")
        local managed_markview_buffers = {}
        local managed_diagnostic_buffers = {}
        local managed_inlay_hint_buffers = {}
        local managed_lsp_clients = {}
        local managed_treesitter_buffers = {}
        local option_names = {
            "number",
            "relativenumber",
            "signcolumn",
            "foldcolumn",
            "statuscolumn",
        }

        local function assert_api(fn, name)
            assert(type(fn) == "function", "codediff internal API changed: " .. tostring(name))
            return fn
        end

        local original_apply = assert_api(welcome_window.apply, "welcome_window.apply")
        local original_resume_diff = assert_api(lifecycle_state.resume_diff, "lifecycle_state.resume_diff")
        local original_update_diff_result = assert_api(lifecycle.update_diff_result, "lifecycle.update_diff_result")
        local original_toggle_view_mode = assert_api(explorer_actions.toggle_view_mode, "explorer_actions.toggle_view_mode")
        local original_toggle_group = assert_api(explorer_actions.toggle_group, "explorer_actions.toggle_group")
        local original_explorer_refresh = assert_api(explorer_refresh.refresh, "explorer_refresh.refresh")
        local original_view_update = assert_api(view.update, "view.update")
        local original_inline_show_single_file = assert_api(inline_view.show_single_file, "inline_view.show_single_file")
        local original_inline_show_welcome = assert_api(inline_view.show_welcome, "inline_view.show_welcome")
        local original_side_show_untracked_file = assert_api(side_by_side_view.show_untracked_file, "side_by_side_view.show_untracked_file")
        local original_side_show_deleted_file = assert_api(side_by_side_view.show_deleted_file, "side_by_side_view.show_deleted_file")
        local original_side_show_added_virtual_file = assert_api(side_by_side_view.show_added_virtual_file, "side_by_side_view.show_added_virtual_file")
        local original_side_show_deleted_virtual_file = assert_api(side_by_side_view.show_deleted_virtual_file, "side_by_side_view.show_deleted_virtual_file")
        local original_side_show_welcome = assert_api(side_by_side_view.show_welcome, "side_by_side_view.show_welcome")
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

        local function with_codediff_swap_guard(fn)
            return swap_guard.run(fn)
        end

        local function notify_codediff_failure(context, err)
            vim.schedule(function()
                vim.notify("CodeDiff " .. context .. " failed: " .. tostring(err), vim.log.levels.ERROR)
            end)
        end

        local function mark_force_explorer_refresh(explorer)
            if explorer then
                explorer._my_force_refresh = true
            end
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

            for name, value in pairs(opts or {}) do
                local current_value, ok = safe_get_window_option(winid, name)
                if not ok then
                    return false
                end
                if current_value ~= value then
                    ok = safe_set_window_option(winid, name, value)
                    if not ok then
                        return false
                    end
                end
            end

            return true
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

            return codediff_shared.is_listable_buffer(bufnr)
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

        local cached_markview_commands = nil
        local cached_markview_state = nil

        local function get_markview_modules()
            if cached_markview_commands ~= nil then
                return cached_markview_commands, cached_markview_state
            end

            local ok_commands, commands = pcall(require, "markview.commands")
            if not ok_commands then
                return nil, nil
            end

            local ok_state, state = pcall(require, "markview.state")
            if not ok_state then
                return nil, nil
            end

            cached_markview_commands = commands
            cached_markview_state = state
            return commands, state
        end

        local function build_active_diff_buf_set()
            local set = {}
            for _, session in pairs(active_diffs()) do
                if session.original_bufnr then
                    set[session.original_bufnr] = true
                end
                if session.modified_bufnr then
                    set[session.modified_bufnr] = true
                end
                if session.result_bufnr then
                    set[session.result_bufnr] = true
                end
            end
            return set
        end

        local function buffer_in_active_diff(bufnr)
            if not (bufnr and vim.api.nvim_buf_is_valid(bufnr)) then
                return false
            end

            return build_active_diff_buf_set()[bufnr] == true
        end

        local function has_treesitter_highlighter(bufnr)
            return vim.treesitter.highlighter
                and vim.treesitter.highlighter.active
                and vim.treesitter.highlighter.active[bufnr] ~= nil
        end

        local function apply_virtual_file_syntax(bufnr)
            local name = vim.api.nvim_buf_get_name(bufnr)
            if not codediff_shared.is_virtual_buffer_name(name) then
                return
            end

            local _, _, filepath = require("codediff.core.virtual_file").parse_url(name)
            if not filepath then
                return
            end

            local filetype = vim.filetype.match({ filename = filepath, buf = bufnr })
            if filetype and filetype ~= "" then
                vim.bo[bufnr].syntax = filetype
            end
        end

        local function disable_treesitter(bufnr)
            if not (bufnr and vim.api.nvim_buf_is_valid(bufnr)) then
                return
            end

            if not has_treesitter_highlighter(bufnr) then
                return
            end

            vim.treesitter.stop(bufnr)
            apply_virtual_file_syntax(bufnr)
            managed_treesitter_buffers[bufnr] = true
        end

        local function restore_treesitter(bufnr, diff_set)
            if not (bufnr and vim.api.nvim_buf_is_valid(bufnr)) then
                if bufnr then
                    managed_treesitter_buffers[bufnr] = nil
                end
                return
            end

            if diff_set and diff_set[bufnr] then
                return
            end

            if codediff_shared.is_virtual_buffer_name(vim.api.nvim_buf_get_name(bufnr)) then
                managed_treesitter_buffers[bufnr] = nil
                return
            end

            require("nvim-treesitter.configs").reattach_module("highlight", bufnr)
            managed_treesitter_buffers[bufnr] = nil
        end

        local function sync_treesitter(tabpage)
            local diff_set = build_active_diff_buf_set()
            local session = tabpage and lifecycle.get_session(tabpage) or nil
            if session then
                disable_treesitter(session.original_bufnr)
                disable_treesitter(session.modified_bufnr)
                disable_treesitter(session.result_bufnr)
            end

            for bufnr, _ in pairs(managed_treesitter_buffers) do
                restore_treesitter(bufnr, diff_set)
            end
        end

        local function schedule_treesitter_sync(tabpage, delay_ms)
            local function sync()
                sync_treesitter(tabpage)
            end

            if delay_ms and delay_ms > 0 then
                vim.defer_fn(sync, delay_ms)
            else
                vim.schedule(sync)
            end
        end

        local function schedule_treesitter_restore(delay_ms, attempts_left)
            local function attempt(i)
                if i > attempts_left then
                    return
                end
                sync_treesitter(nil)
                if i < attempts_left and next(managed_treesitter_buffers) ~= nil then
                    vim.defer_fn(function()
                        attempt(i + 1)
                    end, 80)
                end
            end

            vim.defer_fn(function()
                attempt(1)
            end, delay_ms)
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

        local function restore_markview(bufnr, diff_set)
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

            if diff_set and diff_set[bufnr] then
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
            local diff_set = build_active_diff_buf_set()
            local session = tabpage and lifecycle.get_session(tabpage) or nil
            if session then
                disable_markview(session.original_bufnr)
                disable_markview(session.modified_bufnr)
                disable_markview(session.result_bufnr)
            end

            for bufnr, _ in pairs(managed_markview_buffers) do
                restore_markview(bufnr, diff_set)
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
            local function attempt(i)
                if i > attempts_left then
                    return
                end
                sync_markview(nil)
                if i < attempts_left and next(managed_markview_buffers) ~= nil then
                    vim.defer_fn(function()
                        attempt(i + 1)
                    end, 80)
                end
            end

            vim.defer_fn(function()
                attempt(1)
            end, delay_ms)
        end

        local function clear_tiny_inline_diagnostics(bufnr)
            local ok_extmarks, extmarks = pcall(require, "tiny-inline-diagnostic.extmarks")
            if ok_extmarks and extmarks and extmarks.clear then
                extmarks.clear(bufnr)
            end
        end

        local function disable_diagnostics(bufnr)
            if not (bufnr and vim.api.nvim_buf_is_valid(bufnr)) then
                return
            end

            if not vim.diagnostic.is_enabled({ bufnr = bufnr }) then
                return
            end

            vim.diagnostic.enable(false, { bufnr = bufnr })
            clear_tiny_inline_diagnostics(bufnr)
            managed_diagnostic_buffers[bufnr] = true
        end

        local function restore_diagnostics(bufnr, diff_set)
            if not (bufnr and vim.api.nvim_buf_is_valid(bufnr)) then
                if bufnr then
                    managed_diagnostic_buffers[bufnr] = nil
                end
                return
            end

            if diff_set and diff_set[bufnr] then
                return
            end

            vim.diagnostic.enable(true, { bufnr = bufnr })
            managed_diagnostic_buffers[bufnr] = nil
        end

        local function disable_inlay_hints(bufnr)
            if not (vim.lsp.inlay_hint and bufnr and vim.api.nvim_buf_is_valid(bufnr)) then
                return
            end

            if not vim.lsp.inlay_hint.is_enabled({ bufnr = bufnr }) then
                return
            end

            vim.lsp.inlay_hint.enable(false, { bufnr = bufnr })
            managed_inlay_hint_buffers[bufnr] = true
        end

        local function restore_inlay_hints(bufnr, diff_set)
            if not (vim.lsp.inlay_hint and bufnr and vim.api.nvim_buf_is_valid(bufnr)) then
                if bufnr then
                    managed_inlay_hint_buffers[bufnr] = nil
                end
                return
            end

            if diff_set and diff_set[bufnr] then
                return
            end

            vim.lsp.inlay_hint.enable(true, { bufnr = bufnr })
            managed_inlay_hint_buffers[bufnr] = nil
        end

        local function sync_inlay_hints(tabpage)
            local diff_set = build_active_diff_buf_set()
            local session = tabpage and lifecycle.get_session(tabpage) or nil
            if session then
                disable_inlay_hints(session.original_bufnr)
                disable_inlay_hints(session.modified_bufnr)
                disable_inlay_hints(session.result_bufnr)
            end

            for bufnr, _ in pairs(managed_inlay_hint_buffers) do
                restore_inlay_hints(bufnr, diff_set)
            end
        end

        local function schedule_inlay_hint_sync(tabpage, delay_ms)
            local function sync()
                sync_inlay_hints(tabpage)
            end

            if delay_ms and delay_ms > 0 then
                vim.defer_fn(sync, delay_ms)
            else
                vim.schedule(sync)
            end
        end

        local function schedule_inlay_hint_restore(delay_ms, attempts_left)
            local function attempt(i)
                if i > attempts_left then
                    return
                end
                sync_inlay_hints(nil)
                if i < attempts_left and next(managed_inlay_hint_buffers) ~= nil then
                    vim.defer_fn(function()
                        attempt(i + 1)
                    end, 80)
                end
            end

            vim.defer_fn(function()
                attempt(1)
            end, delay_ms)
        end

        local function detach_lsp_clients(bufnr)
            if not (bufnr and vim.api.nvim_buf_is_valid(bufnr)) then
                return
            end

            local clients = vim.lsp.get_clients({ bufnr = bufnr })
            if not clients or #clients == 0 then
                return
            end

            local detached_client_ids = managed_lsp_clients[bufnr] or {}
            local detached_any = false

            for _, client in ipairs(clients) do
                if not detached_client_ids[client.id] then
                    local ok = pcall(vim.lsp.buf_detach_client, bufnr, client.id)
                    if ok then
                        detached_client_ids[client.id] = true
                        detached_any = true
                    end
                end
            end

            if detached_any then
                managed_lsp_clients[bufnr] = detached_client_ids
            end
        end

        local function restore_lsp_clients(bufnr, diff_set)
            if not bufnr then
                return
            end

            local detached_client_ids = managed_lsp_clients[bufnr]
            if not detached_client_ids then
                return
            end

            if not vim.api.nvim_buf_is_valid(bufnr) then
                managed_lsp_clients[bufnr] = nil
                return
            end

            if diff_set and diff_set[bufnr] then
                return
            end

            local all_attached = true
            for client_id, _ in pairs(detached_client_ids) do
                local ok, attached = pcall(vim.lsp.buf_attach_client, bufnr, client_id)
                if not (ok and attached) then
                    all_attached = false
                end
            end

            if all_attached then
                managed_lsp_clients[bufnr] = nil
            end
        end

        local function sync_lsp_clients(tabpage)
            local diff_set = build_active_diff_buf_set()
            local session = tabpage and lifecycle.get_session(tabpage) or nil
            if session then
                detach_lsp_clients(session.original_bufnr)
                detach_lsp_clients(session.modified_bufnr)
                detach_lsp_clients(session.result_bufnr)
            end

            for bufnr, _ in pairs(managed_lsp_clients) do
                restore_lsp_clients(bufnr, diff_set)
            end
        end

        local function schedule_lsp_sync(tabpage, delay_ms)
            local function sync()
                sync_lsp_clients(tabpage)
            end

            if delay_ms and delay_ms > 0 then
                vim.defer_fn(sync, delay_ms)
            else
                vim.schedule(sync)
            end
        end

        local function schedule_lsp_restore(delay_ms, attempts_left)
            local function attempt(i)
                if i > attempts_left then
                    return
                end
                sync_lsp_clients(nil)
                if i < attempts_left and next(managed_lsp_clients) ~= nil then
                    vim.defer_fn(function()
                        attempt(i + 1)
                    end, 80)
                end
            end

            vim.defer_fn(function()
                attempt(1)
            end, delay_ms)
        end

        local function sync_diagnostics(tabpage)
            local diff_set = build_active_diff_buf_set()
            local session = tabpage and lifecycle.get_session(tabpage) or nil
            if session then
                disable_diagnostics(session.original_bufnr)
                disable_diagnostics(session.modified_bufnr)
                disable_diagnostics(session.result_bufnr)
            end

            for bufnr, _ in pairs(managed_diagnostic_buffers) do
                restore_diagnostics(bufnr, diff_set)
            end
        end

        local function schedule_diagnostic_sync(tabpage, delay_ms)
            local function sync()
                sync_diagnostics(tabpage)
            end

            if delay_ms and delay_ms > 0 then
                vim.defer_fn(sync, delay_ms)
            else
                vim.schedule(sync)
            end
        end

        local function schedule_diagnostic_restore(delay_ms, attempts_left)
            local function attempt(i)
                if i > attempts_left then
                    return
                end
                sync_diagnostics(nil)
                if i < attempts_left and next(managed_diagnostic_buffers) ~= nil then
                    vim.defer_fn(function()
                        attempt(i + 1)
                    end, 80)
                end
            end

            vim.defer_fn(function()
                attempt(1)
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

        local function schedule_explorer_sync(tabpage, opts_delay, groups_delay)
            local o_delay = opts_delay or 20
            local g_delay = groups_delay or 60

            local function sync_opts()
                apply_current_explorer_window_opts(tabpage)
                sync_markview(tabpage)
                sync_diagnostics(tabpage)
                sync_inlay_hints(tabpage)
                sync_lsp_clients(tabpage)
            end

            local function sync_groups()
                expand_explorer_root_groups(lifecycle.get_explorer(tabpage or vim.api.nvim_get_current_tabpage()))
            end

            if o_delay > 0 then
                vim.defer_fn(sync_opts, o_delay)
            else
                vim.schedule(sync_opts)
            end

            if g_delay > 0 then
                vim.defer_fn(sync_groups, g_delay)
            else
                vim.schedule(sync_groups)
            end
        end

        local function wrap_with_explorer_sync(fn, opts_delay, groups_delay)
            return function(tabpage, ...)
                local args = { ... }
                local ok, result = with_codediff_swap_guard(function()
                    return fn(tabpage, unpack(args))
                end)
                if not ok then
                    notify_codediff_failure("view update", result)
                    return nil
                end
                schedule_explorer_sync(tabpage, opts_delay, groups_delay)
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
                if sess.result_win == winid then
                    return sess, "result"
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

        lifecycle.update_diff_result = function(tabpage, lines_diff)
            return original_update_diff_result(tabpage, diff_result.normalize(lines_diff))
        end

        lifecycle_state.resume_diff = function(tabpage)
            local session = lifecycle.get_session(tabpage)
            if session and diff_result.is_malformed(session.stored_diff_result) then
                session.stored_diff_result = nil
            end

            local ok, err = with_codediff_swap_guard(function()
                original_resume_diff(tabpage)
            end)
            if not ok then
                notify_codediff_failure("resume", err)
                return
            end
            schedule_layout_sync(tabpage, 20)
            apply_current_session_wrap(tabpage)
            ensure_current_session_buflisted(tabpage)
            schedule_explorer_sync(tabpage, 20, 40)
        end

        explorer_actions.toggle_view_mode = function(explorer, ...)
            mark_force_explorer_refresh(explorer)
            return original_toggle_view_mode(explorer, ...)
        end

        explorer_actions.toggle_group = function(explorer, group_name, ...)
            mark_force_explorer_refresh(explorer)
            return original_toggle_group(explorer, group_name, ...)
        end

        explorer_refresh.refresh = function(explorer)
            if not explorer or not explorer.git_root or explorer.base_revision or explorer.target_revision then
                return original_explorer_refresh(explorer)
            end

            local force_refresh = explorer._my_force_refresh == true
            explorer._my_force_refresh = nil

            if force_refresh then
                local ok, refresh_err = with_codediff_swap_guard(function()
                    original_explorer_refresh(explorer)
                end)
                if not ok then
                    notify_codediff_failure("explorer refresh", refresh_err)
                    return
                end
                schedule_explorer_sync(explorer.tabpage, 20, 20)
                return
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

                    local ok, refresh_err = with_codediff_swap_guard(function()
                        original_explorer_refresh(explorer)
                    end)
                    if not ok then
                        notify_codediff_failure("explorer refresh", refresh_err)
                        return
                    end
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
                sync_treesitter(tabpage)
                sync_diagnostics(tabpage)
                sync_inlay_hints(tabpage)
                sync_lsp_clients(tabpage)
            end,
        })

        vim.api.nvim_create_autocmd("SwapExists", {
            group = group,
            callback = function()
                if not swap_guard.is_active() then
                    return
                end

                local afile = vim.fn.expand("<afile>")
                local in_session = false
                for _, sess in pairs(active_diffs()) do
                    if sess.original_path == afile or sess.modified_path == afile or sess.result_path == afile then
                        in_session = true
                        break
                    end
                end

                if in_session or afile:match("^codediff://") then
                    vim.v.swapchoice = "e"
                    vim.schedule(function()
                        vim.notify("Swap file detected for " .. afile .. ", forcing edit (CodeDiff session)", vim.log.levels.WARN)
                    end)
                end
            end,
        })

        local resize_timer = nil
        vim.api.nvim_create_autocmd("VimResized", {
            group = group,
            callback = function()
                if resize_timer then
                    vim.fn.timer_stop(resize_timer)
                    resize_timer = nil
                end
                resize_timer = vim.fn.timer_start(80, function()
                    resize_timer = nil
                    schedule_layout_sync(nil, 20)
                end)
            end,
        })

        vim.api.nvim_create_autocmd("User", {
            group = group,
            pattern = "CodeDiffFileSelect",
            callback = function(ev)
                local tabpage = ev.data and ev.data.tabpage or nil
                schedule_treesitter_sync(tabpage, 20)
                schedule_explorer_sync(tabpage)
            end,
        })

        vim.api.nvim_create_autocmd("User", {
            group = group,
            pattern = "CodeDiffClose",
            callback = function(ev)
                schedule_treesitter_restore(20, 6)
                schedule_markview_restore(20, 6)
                schedule_diagnostic_restore(20, 6)
                schedule_inlay_hint_restore(20, 6)
                schedule_lsp_restore(20, 6)
            end,
        })

        vim.api.nvim_create_autocmd("User", {
            group = group,
            pattern = "CodeDiffVirtualFileLoaded",
            callback = function(ev)
                local bufnr = ev.data and ev.data.buf or nil
                disable_treesitter(bufnr)
            end,
        })

        vim.api.nvim_create_autocmd("LspAttach", {
            group = group,
            callback = function(ev)
                if not buffer_in_active_diff(ev.buf) then
                    return
                end

                vim.schedule(function()
                    detach_lsp_clients(ev.buf)
                    disable_diagnostics(ev.buf)
                    disable_inlay_hints(ev.buf)
                end)
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
                    disable_treesitter(ev.buf)
                    disable_markview(ev.buf)
                    detach_lsp_clients(ev.buf)
                    disable_diagnostics(ev.buf)
                    disable_inlay_hints(ev.buf)
                    codediff.set_tabline_buffer(tabpage, ev.buf)
                    pcall(function()
                        vim.bo[ev.buf].buflisted = true
                    end)
                    vim.schedule(function()
                        pcall(vim.cmd, "redrawtabline")
                    end)
                    schedule_treesitter_sync(tabpage, 20)
                    schedule_markview_sync(tabpage, 20)
                    schedule_diagnostic_sync(tabpage, 20)
                    schedule_inlay_hint_sync(tabpage, 20)
                    schedule_lsp_sync(tabpage, 20)
                end

                if vim.bo[ev.buf].filetype == "codediff-explorer" then
                    apply_explorer_window_opts(vim.api.nvim_get_current_win())
                end
            end,
        })
    end,
}
