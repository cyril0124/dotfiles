return {
    'nvim-telescope/telescope.nvim',
    tag = '0.1.8',
    dependencies = {
        'nvim-lua/plenary.nvim',
        {
            -- To enable fzf style searching
            'nvim-telescope/telescope-fzf-native.nvim',
            build = 'make'
        },
        'jonarrien/telescope-cmdline.nvim',
    },
    keys = {
        { '<leader><leader>', '<cmd>Telescope cmdline<cr>', desc = 'Cmdline' }
    },
    config = function()
        local telescope = require("telescope")
        telescope.setup({
            pickers = {
                find_files = {
                    -- find_command = { "rg", "--files", "--hidden", "--no-ignore", "--glob", "!**/.git/*" }
                }
            }
        })
        telescope.load_extension('fzf')
        telescope.load_extension('cmdline')
    end
}
