return {
    'nvim-treesitter/nvim-treesitter',
    event = { "BufReadPost", "BufNewFile" },
    build = ':TSUpdate',
    config = function()
        require('nvim-treesitter.configs').setup {
            ensure_installed = vim.env.DOTFILES_CI == '1'
                and {}  -- bootstrap handles TSInstallSync explicitly
                or  { 'c', 'cpp', 'lua', 'python', 'rust', 'scala', 'markdown', 'markdown_inline', 'diff', 'verilog' },
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
