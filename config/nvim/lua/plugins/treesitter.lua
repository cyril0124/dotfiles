return {
    'nvim-treesitter/nvim-treesitter',
    event = { "BufReadPost", "BufNewFile" },
    build = ':TSUpdate',
    config = function()
        -- During bootstrap, scripts/nvim_setup.lua is the single authority for
        -- parser installation (it installs missing parsers deterministically).
        -- Leaving ensure_installed populated there would race with that script,
        -- so it is emptied only while bootstrap runs. Interactive sessions keep
        -- the full list for automatic parser installation.
        local ensure_installed = { 'c', 'cpp', 'lua', 'python', 'rust', 'scala', 'markdown', 'markdown_inline', 'diff', 'verilog' }
        if vim.env.NVIM_BOOTSTRAP == '1' then
            ensure_installed = {}
        end

        require('nvim-treesitter.configs').setup {
            ensure_installed = ensure_installed,
            highlight = {
                enable = true,
                disable = function(_, bufnr)
                    return require("lua.codediff_shared").is_codediff_buffer(bufnr)
                end,
            },
            fold = {
                enable = true,
            },
        }

        -- vim.wo.foldmethod  = 'expr'
        -- vim.wo.foldexpr    = 'v:lua.vim.treesitter.foldexpr()'
        -- vim.o.foldlevel    = 99
        -- vim.o.foldminlines = 1
    end
}
