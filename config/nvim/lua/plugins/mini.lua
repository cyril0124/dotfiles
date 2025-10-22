return {
    "echasnovski/mini.nvim",
    version = "*",
    config = function()
        -- Autopairs
        require("mini.pairs").setup({
            modes = { insert = true, command = true, terminal = false },
        })

        -- Git support
        require("mini.git").setup()

        -- Trailspace (highlight and remove)
        require("mini.trailspace").setup()

        -- Show notifications
        require('mini.notify').setup()
        do
            local notify = require "mini.notify"
            notify.setup()
            vim.notify = notify.make_notify({
                -- ERROR = { duration = 50000 },
                -- WARN = { duration = 40000 },
                -- INFO = { duration = 30000 },
            })
        end

        -- Highlight patterns in text
        local hipatterns = require("mini.hipatterns")
        hipatterns.setup({
            highlighters = {
                -- Highlight standalone 'FIXME', 'HACK', 'TODO', 'NOTE'
                fixme     = { pattern = '%f[%w]()FIXME()%f[%W]', group = 'MiniHipatternsFixme' },
                hack      = { pattern = '%f[%w]()HACK()%f[%W]', group = 'MiniHipatternsHack' },
                todo      = { pattern = '%f[%w]()TODO()%f[%W]', group = 'MiniHipatternsTodo' },
                note      = { pattern = '%f[%w]()NOTE()%f[%W]', group = 'MiniHipatternsNote' },

                -- Highlight hex color strings (`#rrggbb`) using that color
                hex_color = hipatterns.gen_highlighter.hex_color(),
            },
        })

        -- Start screen
        -- require('mini.starter').setup()

        -- Jump to next/previous single character
        require('mini.jump').setup({
            mappings = {
                forward = 'f',
                backward = 'F',
                forward_till = 't',
                backward_till = 'T',
                repeat_jump = ';',
            },
        })

        -- Automatic highlighting of word under cursor
        require('mini.cursorword').setup()

        -- Animate common Neovim actions
        local animate = require('mini.animate')
        animate.setup({
            cursor = {
                enable = false,
            },
            open = {
                enable = false,
            },
            close = {
                enable = false,
            },
            scroll = {
                enable = true,
                timing = animate.gen_timing.linear({ duration = 100, unit = 'total' }),
                subscroll = animate.gen_subscroll.equal({
                    predicate = function(total_scroll)
                        -- Only animate if scroll distance is larger than 3 lines(Used by mouse scrolling)
                        return total_scroll > 3
                    end
                })
            }
        })
    end,
}
