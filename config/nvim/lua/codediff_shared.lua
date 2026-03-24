local M = {}

local auxiliary_filetypes = {
    ["codediff-explorer"] = true,
    ["codediff-history"] = true,
    ["codediff-help"] = true,
}

function M.is_auxiliary_filetype(filetype)
    return filetype ~= nil and auxiliary_filetypes[filetype] == true
end

function M.is_virtual_buffer_name(name)
    return type(name) == "string" and name:match("^codediff://") ~= nil
end

function M.is_listable_buffer(bufnr)
    if not (bufnr and vim.api.nvim_buf_is_valid(bufnr)) then
        return false
    end

    local name = vim.api.nvim_buf_get_name(bufnr)
    if name == "" then
        return false
    end

    if M.is_auxiliary_filetype(vim.bo[bufnr].filetype) then
        return false
    end

    return vim.bo[bufnr].buftype == "" or M.is_virtual_buffer_name(name)
end

function M.is_real_file_buffer(bufnr)
    if not (bufnr and vim.api.nvim_buf_is_valid(bufnr)) then
        return false
    end

    if vim.bo[bufnr].buftype ~= "" then
        return false
    end

    local name = vim.api.nvim_buf_get_name(bufnr)
    return name ~= "" and not M.is_virtual_buffer_name(name)
end

function M.get_lifecycle()
    local ok, lifecycle = pcall(require, "codediff.ui.lifecycle")
    if not ok then
        return nil
    end

    return lifecycle
end

function M.get_session(tabpage)
    local lifecycle = M.get_lifecycle()
    if not lifecycle then
        return nil
    end

    return lifecycle.get_session(tabpage or vim.api.nvim_get_current_tabpage())
end

function M.get_explorer_window(tabpage)
    local lifecycle = M.get_lifecycle()
    if not lifecycle then
        return nil
    end

    local explorer = lifecycle.get_explorer(tabpage or vim.api.nvim_get_current_tabpage())
    if not explorer then
        return nil
    end

    return explorer.winid or (explorer.split and explorer.split.winid) or nil
end

function M.is_session_window(winid, session)
    if not (session and winid and vim.api.nvim_win_is_valid(winid)) then
        return false
    end

    return session.original_win == winid or session.modified_win == winid or session.result_win == winid
end

return M
