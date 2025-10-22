-- https://github.com/lewis6991/gitsigns.nvim
return {
    'lewis6991/gitsigns.nvim',
    event = { 'BufReadPre', 'BufNewFile' },
    config = function()
        require('gitsigns').setup({
            current_line_blame_opts = {
                delay = 100,
            }
        })
    end,
}
