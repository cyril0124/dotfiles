-- Render Mermaid code fences with the local grok-build-compatible Python renderer.
-- Commands: :MermaidRender, :MermaidInline, and :MermaidInlineAll.
-- Inside a Mermaid fence, press K for the scrollable split preview.
return {
    name = "local-mermaid-preview",
    dir = vim.fn.stdpath("config"),
    ft = "markdown",
    config = function()
        local config = {
            python = "python3",
            renderer = vim.fn.stdpath("config") .. "/scripts/mermaid_ascii.py",
        }

        local namespace = vim.api.nvim_create_namespace("local-mermaid-preview")
        local preview_window
        local preview_buffer
        local render_generation = 0

        local function close_preview()
            render_generation = render_generation + 1
            if preview_window and vim.api.nvim_win_is_valid(preview_window) then
                vim.api.nvim_win_close(preview_window, true)
            end
            for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
                if vim.api.nvim_buf_is_valid(bufnr) then
                    vim.api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)
                end
            end
            preview_window = nil
            preview_buffer = nil
        end

        local function find_mermaid_block(bufnr, cursor_line)
            local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
            local start_line
            local fence

            for line = cursor_line, 1, -1 do
                local marker = lines[line]:match("^%s*(```+)%s*mermaid%s*$")
                    or lines[line]:match("^%s*(~~~+)%s*mermaid%s*$")
                if marker then
                    start_line = line
                    fence = marker:sub(1, 1)
                    break
                end

                if lines[line]:match("^%s*```+") or lines[line]:match("^%s*~~~+") then
                    return nil
                end
            end

            if not start_line then
                return nil
            end

            local end_line
            for line = start_line + 1, #lines do
                if lines[line]:match("^%s*" .. fence .. "+%s*$") then
                    end_line = line
                    break
                end
            end

            if not end_line or cursor_line > end_line then
                return nil
            end

            return {
                start_line = start_line,
                end_line = end_line,
                source = table.concat(vim.list_slice(lines, start_line + 1, end_line - 1), "\n"),
            }
        end

        local function find_mermaid_blocks(bufnr)
            local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
            local blocks = {}
            local line = 1

            while line <= #lines do
                local marker = lines[line]:match("^%s*(```+)%s*mermaid%s*$")
                    or lines[line]:match("^%s*(~~~+)%s*mermaid%s*$")
                if marker then
                    local end_line
                    local fence = marker:sub(1, 1)

                    for candidate = line + 1, #lines do
                        if lines[candidate]:match("^%s*" .. fence .. "+%s*$") then
                            end_line = candidate
                            break
                        end
                    end

                    if end_line then
                        blocks[#blocks + 1] = {
                            start_line = line,
                            end_line = end_line,
                            source = table.concat(
                                vim.list_slice(lines, line + 1, end_line - 1),
                                "\n"
                            ),
                        }
                        line = end_line
                    end
                end
                line = line + 1
            end

            return blocks
        end

        local function build_preview_lines(block, rendered_lines, index)
            local lines = {
                string.format("── Mermaid #%d (source, line %d) ──", index or 1, block.start_line),
                "```mermaid",
            }
            vim.list_extend(lines, vim.split(block.source, "\n", { plain = true }))
            lines[#lines + 1] = "```"
            lines[#lines + 1] = ""
            lines[#lines + 1] = "──────────────────────────────────────── rendered ────────────────────────────────────────"
            vim.list_extend(lines, rendered_lines)
            return lines
        end

        local render_block

        local function show_inline(bufnr, block, lines, index)
            local virtual_lines = {}
            for _, line in ipairs(lines) do
                virtual_lines[#virtual_lines + 1] = {
                    { line, "Normal" },
                }
            end

            vim.api.nvim_buf_set_extmark(bufnr, namespace, block.end_line - 1, 0, {
                virt_lines = virtual_lines,
                virt_lines_above = false,
                virt_lines_leftcol = false,
            })
        end

        local function render_current_inline()
            local bufnr = vim.api.nvim_get_current_buf()
            local block = find_mermaid_block(bufnr, vim.api.nvim_win_get_cursor(0)[1])
            if not block then
                vim.notify("Cursor is not inside a Mermaid code block", vim.log.levels.INFO)
                return
            end

            vim.api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)
            render_generation = render_generation + 1
            local generation = render_generation
            render_block(bufnr, block, math.max(20, vim.api.nvim_win_get_width(0) - 6), generation, 1, function(lines)
                if lines then
                    show_inline(bufnr, block, lines, 1)
                end
            end)
        end

        local function render_all_inline()
            local bufnr = vim.api.nvim_get_current_buf()
            local blocks = find_mermaid_blocks(bufnr)
            if #blocks == 0 then
                vim.notify("No Mermaid code blocks found", vim.log.levels.INFO)
                return
            end

            vim.api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)
            render_generation = render_generation + 1
            local generation = render_generation
            local width = math.max(20, vim.api.nvim_win_get_width(0) - 6)
            for index, block in ipairs(blocks) do
                render_block(bufnr, block, width, generation, index, function(lines)
                    if lines then
                        show_inline(bufnr, block, lines, index)
                    end
                end)
            end
        end

        local function show_lines(lines, title)
            if not preview_buffer or not vim.api.nvim_buf_is_valid(preview_buffer) then
                preview_buffer = vim.api.nvim_create_buf(false, true)
                vim.bo[preview_buffer].buftype = "nofile"
                vim.bo[preview_buffer].bufhidden = "wipe"
                vim.bo[preview_buffer].swapfile = false
                vim.bo[preview_buffer].filetype = "mermaid"
            end

            if not preview_window or not vim.api.nvim_win_is_valid(preview_window) then
                vim.cmd("botright split")
                preview_window = vim.api.nvim_get_current_win()
                vim.api.nvim_win_set_buf(preview_window, preview_buffer)
                vim.api.nvim_win_set_height(preview_window, math.max(8, math.floor(vim.o.lines * 0.4)))
                vim.wo[preview_window].number = false
                vim.wo[preview_window].relativenumber = false
                vim.wo[preview_window].wrap = false
                vim.wo[preview_window].cursorline = false
                vim.keymap.set("n", "q", close_preview, { buffer = preview_buffer, silent = true })
                vim.keymap.set("n", "<Esc>", close_preview, { buffer = preview_buffer, silent = true })
            end

            vim.api.nvim_buf_set_lines(preview_buffer, 0, -1, false, lines)
            vim.api.nvim_buf_set_name(preview_buffer, title)
            vim.api.nvim_set_current_win(preview_window)
        end

        render_block = function(bufnr, block, width, generation, block_number, on_rendered)
            local ok, process = pcall(vim.system, {
                config.python,
                config.renderer,
                "--width",
                tostring(width),
            }, {
                stdin = block.source,
                text = true,
            }, function(result)
                vim.schedule(function()
                    if generation ~= render_generation or not vim.api.nvim_buf_is_valid(bufnr) then
                        return
                    end
                    if result.code ~= 0 then
                        local detail = vim.trim(result.stderr)
                        if detail == "" then
                            detail = "renderer exited with code " .. result.code
                        end
                        vim.notify(
                            string.format("Mermaid #%d at line %d failed: %s", block_number or 1, block.start_line, detail),
                            vim.log.levels.ERROR
                        )
                        if on_rendered then
                            on_rendered(nil, block_number)
                        end
                        return
                    end

                    local lines = vim.split(result.stdout, "\n", {
                        plain = true,
                        trimempty = true,
                    })
                    if #lines == 0 then
                        vim.notify(
                            string.format("Mermaid #%d at line %d returned no output", block_number or 1, block.start_line),
                            vim.log.levels.WARN
                        )
                        if on_rendered then
                            on_rendered(nil, block_number)
                        end
                        return
                    end
                    if result.stdout:find("This diagram is too wide", 1, true) then
                        vim.notify(
                            string.format("Mermaid #%d at line %d is too wide for the current window", block_number or 1, block.start_line),
                            vim.log.levels.WARN
                        )
                    end
                    if on_rendered then
                        on_rendered(lines, block_number)
                    end
                end)
            end)
            if not ok then
                vim.notify(
                    string.format("Mermaid #%d: failed to start renderer: %s", block_number or 1, process),
                    vim.log.levels.ERROR
                )
                if on_rendered then
                    on_rendered(nil, block_number)
                end
            end
        end

        local function render_current_block()
            local bufnr = vim.api.nvim_get_current_buf()
            local block = find_mermaid_block(bufnr, vim.api.nvim_win_get_cursor(0)[1])
            if not block then
                vim.notify("Cursor is not inside a Mermaid code block", vim.log.levels.INFO)
                return
            end

            render_generation = render_generation + 1
            local generation = render_generation
            render_block(bufnr, block, math.max(20, vim.api.nvim_win_get_width(0) - 6), generation, 1, function(lines)
                if lines then
                    show_lines(build_preview_lines(block, lines, 1), "Mermaid")
                end
            end)
        end

        vim.api.nvim_create_user_command("MermaidRender", render_current_block, {})
        vim.api.nvim_create_user_command("MermaidInline", render_current_inline, {})
        vim.api.nvim_create_user_command("MermaidInlineAll", render_all_inline, {})
        vim.api.nvim_create_user_command("MermaidClose", close_preview, {})
        vim.api.nvim_create_user_command("MermaidInlineClose", function()
            render_generation = render_generation + 1
            for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
                if vim.api.nvim_buf_is_valid(bufnr) then
                    vim.api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)
                end
            end
        end, {})

        vim.keymap.set("n", "K", render_current_block, {
            buffer = 0,
            silent = true,
            desc = "Render Mermaid block",
        })
    end,
}
