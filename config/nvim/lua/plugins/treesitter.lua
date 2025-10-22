return {
    'nvim-treesitter/nvim-treesitter',
    build = ':TSUpdate',
    config = function()
        require('nvim-treesitter.configs').setup {
            ensure_installed = { 'c', 'cpp', 'lua', 'python', 'rust' },
            -- highlight = { enable = true },
            highlight = { enable = false },
            fold = {
                enable = true,
            },
        }

        vim.wo.foldmethod  = 'expr'
        vim.wo.foldexpr    = 'v:lua.vim.treesitter.foldexpr()'
        vim.o.foldlevel    = 99
        vim.o.foldminlines = 1
    end
}
