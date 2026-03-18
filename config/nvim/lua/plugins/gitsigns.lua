-- https://github.com/lewis6991/gitsigns.nvim
return {
    'lewis6991/gitsigns.nvim',
    event = { 'BufReadPost', 'BufNewFile' },
    config = function()
        require('gitsigns').setup({
            signs = {
                add          = { text = '▎' },
                change       = { text = '▎' },
                delete       = { text = '▁' },
                topdelete    = { text = '▔' },
                changedelete = { text = '▎' },
                untracked    = { text = '┆' },
            },
            -- Color line numbers for changed lines
            numhl = true,
            current_line_blame = false,
            current_line_blame_opts = {
                delay = 100,
            },
        })
    end,
}
