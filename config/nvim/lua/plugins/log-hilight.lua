-- https://github.com/fei6409/log-highlight.nvim
return {
    {
        'fei6409/log-highlight.nvim',
        opts = {},
    },

    -- https://github.com/0xferrous/ansi.nvim
    {
        '0xferrous/ansi.nvim',
        cmd = { "AnsiEnable", "AnsiDisable", "AnsiToggle" },
        config = function()
            require('ansi').setup({
                auto_enable = false,
                filetypes = { 'log', 'ansi' },
            })
        end,
    },
}
