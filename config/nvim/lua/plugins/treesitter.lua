return {
    'nvim-treesitter/nvim-treesitter',
    build = ':TSUpdate',
    config = function()
        require('nvim-treesitter.configs').setup {
            ensure_installed = { 'c', 'cpp', 'lua', 'python', 'rust', 'scala', 'markdown', 'markdown_inline', 'diff', 'verilog' },
            highlight = { enable = true },
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
