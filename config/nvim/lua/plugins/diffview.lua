-- https://github.com/sindrets/diffview.nvim
return {
    "sindrets/diffview.nvim",
    cmd = {
        "DiffviewOpen",
        "DiffviewClose",
        "DiffviewToggleFiles",
        "DiffviewFocusFiles",
        "DiffviewRefresh",
        "DiffviewFileHistory",
        "DiffviewLog",
    },
    config = function()
        if vim.g._diffview_treesitter_start_wrapped then
            return
        end

        local original_start = vim.treesitter.start

        vim.treesitter.start = function(bufnr, lang)
            local target_buf = bufnr
            if target_buf == nil or target_buf == 0 then
                target_buf = vim.api.nvim_get_current_buf()
            end

            local ok, result = pcall(original_start, bufnr, lang)
            if ok then
                return result
            end

            local name = vim.api.nvim_buf_get_name(target_buf)
            if vim.startswith(name, "diffview://") and tostring(result):match("Parser could not be created") then
                return
            end

            error(result)
        end

        vim.g._diffview_treesitter_start_wrapped = true
    end,
}
