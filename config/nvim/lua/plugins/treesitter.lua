-- nvim-treesitter's `main` branch only ships queries and parser metadata:
-- parser installation is delegated to ts-install.nvim and highlighting is
-- started manually via vim.treesitter.start().
local ENSURE_INSTALL = {
    'c', 'cpp', 'lua', 'python', 'rust', 'scala', 'markdown', 'markdown_inline', 'diff', 'systemverilog',
}

-- ts-install keeps parsers outside the default runtimepath. Prepending that
-- directory at startup stops Neovim's bundled grammars from winning the first
-- registration: they are older than the nvim-treesitter `main` queries expect
-- (bundled lua 0.4.0 has no `operator` field), and language.add() keeps the
-- first parser loaded for the rest of the session.
local PARSER_DIR = vim.fs.joinpath(vim.fn.stdpath('data'), 'ts-install')

local function start_highlight(buf)
    if not vim.api.nvim_buf_is_valid(buf) then
        return
    end
    if require('lua.codediff_shared').is_codediff_buffer(buf) then
        return
    end
    -- Fails when no parser is installed for the filetype; nothing to do then.
    pcall(vim.treesitter.start, buf)
end

return {
    {
        'nvim-treesitter/nvim-treesitter',
        branch = 'main',
        lazy = true,
        init = function()
            -- Skip nvim-treesitter's own :TS* commands; ts-install owns installation.
            vim.g.loaded_nvim_treesitter = 1
            vim.opt.runtimepath:prepend(PARSER_DIR)
        end,
    },

    {
        'lewis6991/ts-install.nvim',
        event = { 'BufReadPost', 'BufNewFile' },
        dependencies = { 'nvim-treesitter/nvim-treesitter' },
        config = function()
            -- During bootstrap, scripts/nvim_setup.lua is the single authority for
            -- parser installation, so background install/update must stay off to
            -- avoid racing with it.
            local bootstrap = vim.env.NVIM_BOOTSTRAP == '1'
            require('ts-install').setup {
                ensure_install = bootstrap and {} or ENSURE_INSTALL,
                auto_update = not bootstrap,
            }

            vim.api.nvim_create_autocmd('FileType', {
                callback = function(args)
                    start_highlight(args.buf)
                end,
            })

            -- FileType may already have fired for buffers opened before this loaded.
            for _, buf in ipairs(vim.api.nvim_list_bufs()) do
                if vim.bo[buf].filetype ~= '' then
                    start_highlight(buf)
                end
            end
        end,
    },
}
