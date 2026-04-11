return {
	"dmtrKovalenko/fff.nvim",
	lazy = false,
	build = function()
		require("fff.download").download_or_build_binary()
	end,
	opts = {
		lazy_sync = true,
	},
	config = function(_, opts)
		require("fff").setup(opts)

		local ok_picker, picker_ui = pcall(require, "fff.picker_ui")
		if not ok_picker or picker_ui._my_codediff_select_patched then
			return
		end

		local function resolve_location(state, item)
			local location = state.location
			local query = state.query
			local mode = state.mode
			local suggestion_source = state.suggestion_source

			local is_grep_item = mode == "grep" or suggestion_source == "grep"
			if is_grep_item and item.line_number and item.line_number > 0 then
				location = { line = item.line_number }
				if item.col and item.col > 0 then
					location.col = item.col + 1
				end
			end

			if not location and query and query ~= "" then
				local line_str = query:match(':(%d+)$')
				if line_str then
					local line_num = tonumber(line_str)
					if line_num and line_num > 0 then
						local l, c = query:match(':(%d+):(%d+)$')
						if l and c then
							location = { line = tonumber(l), col = tonumber(c) }
						else
							location = { line = line_num }
						end
					end
				end
			end

			return location, query, mode
		end

		local function open_selected_path(action, path)
			local escaped = vim.fn.fnameescape(path)
			if action == "split" then
				vim.cmd("split " .. escaped)
			elseif action == "vsplit" then
				vim.cmd("vsplit " .. escaped)
			elseif action == "tab" then
				vim.cmd("tabedit " .. escaped)
			else
				vim.cmd("edit " .. escaped)
			end
		end

		local original_select = picker_ui.select
		picker_ui.select = function(action)
			local codediff = require("lua.codediff")
			if not codediff.is_current_session() then
				return original_select(action)
			end

			local state = picker_ui.state
			if not (state and state.active) then
				return original_select(action)
			end

			local items = state.filtered_items or {}
			local item = items[state.cursor or 1]
			if not (item and item.path) then
				return original_select(action)
			end

			action = action or "edit"
			local path = item.path
			if vim.startswith(path, '\\\\?\\') then
				path = path:sub(5)
			end

			local location, query, mode = resolve_location(state, item)

			vim.cmd("stopinsert")
			picker_ui.close()

			return codediff.run_outside_current_session(function()
				open_selected_path(action, path)

				vim.schedule(function()
					if location then
						require("fff.location_utils").jump_to_location(location)
					end

					if query and query ~= "" then
						local config = require("fff.conf").get()
						if config.history and config.history.enabled then
							local fff_core = require("fff.core").ensure_initialized()
							if mode == "grep" then
								pcall(fff_core.track_grep_query, query)
							else
								pcall(fff_core.track_query_completion, query, path)
							end
						end
					end
				end)
			end)
		end

		picker_ui._my_codediff_select_patched = true
	end,
}
