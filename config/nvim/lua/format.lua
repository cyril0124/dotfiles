local M = {}

local function uses_json_range_format(bufnr)
    local filetype = vim.bo[bufnr].filetype
    return filetype == "json" or filetype == "jsonc"
end

local function full_buffer_range(bufnr)
    return {
        start = { 1, 0 },
        ["end"] = { vim.api.nvim_buf_line_count(bufnr), 0 },
    }
end

function M.format(opts)
    local bufnr = (opts and opts.bufnr) or vim.api.nvim_get_current_buf()
    local format_opts = vim.tbl_extend("force", {
        bufnr = bufnr,
        lsp_format = "fallback",
    }, opts or {})

    if format_opts.range == nil and uses_json_range_format(bufnr) then
        format_opts.range = full_buffer_range(bufnr)
    end

    local ok, conform = pcall(require, "conform")
    if ok then
        return conform.format(format_opts)
    end

    local lsp_opts = vim.deepcopy(format_opts)
    lsp_opts.lsp_format = nil
    return vim.lsp.buf.format(lsp_opts)
end

return M
