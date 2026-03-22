local M = {}

local function get_codediff_git_root()
    local ok, lifecycle = pcall(require, "codediff.ui.lifecycle")
    if not ok then
        return nil
    end

    local git_context = lifecycle.get_git_context(vim.api.nvim_get_current_tabpage())
    if git_context then
        return git_context.git_root
    end

    return nil
end

local function get_target_dir()
    local codediff_git_root = get_codediff_git_root()
    if codediff_git_root then
        return codediff_git_root
    end

    local bufnr = vim.api.nvim_get_current_buf()
    local bufname = vim.api.nvim_buf_get_name(bufnr)
    if vim.bo[bufnr].buftype == "" and bufname ~= "" then
        return vim.fs.dirname(bufname)
    end

    return vim.uv.cwd()
end

local function run_git(args)
    return vim.system(vim.list_extend({ "git" }, args), { text = true }):wait()
end

local function get_git_root()
    local result = run_git({ "-C", get_target_dir(), "rev-parse", "--show-toplevel" })
    if result.code ~= 0 then
        return nil
    end

    return vim.trim(result.stdout)
end

local function rev_exists(git_root, rev)
    return run_git({ "-C", git_root, "rev-parse", "--verify", rev }).code == 0
end

function M.open_last_commit_diff()
    local git_root = get_git_root()
    if not git_root then
        vim.notify("Current buffer is not inside a git repository", vim.log.levels.WARN)
        return
    end

    local next_depth = (vim.g._last_commit_depth or 0) + 1
    local base_rev = "HEAD~" .. next_depth

    if not rev_exists(git_root, base_rev) then
        vim.notify("No older commit available beyond depth " .. (next_depth - 1), vim.log.levels.INFO)
        return
    end

    vim.g._last_commit_depth = next_depth

    require("lua.codediff").open("history " .. base_rev .. "..HEAD")
end

function M.reset_last_commit_depth()
    vim.g._last_commit_depth = 0
    require("lua.codediff").close_current()
end

return M
