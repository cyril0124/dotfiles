return {
    -- https://github.com/nvzone/menu
    {
        {
            "nvzone/volt",
            lazy = true
        },
        {
            "nvzone/menu",
            lazy = true,
        },
    },

    -- https://github.com/akinsho/bufferline.nvim
    {
        'akinsho/bufferline.nvim',
        version = "*",
        dependencies = 'nvim-tree/nvim-web-devicons',
        config = function()
            vim.opt.termguicolors = true

            -- Tab to switch buffer
            vim.keymap.set("n", "<tab>", "<cmd>BufferLineCycleNext<cr>")

            require("bufferline").setup({
                options = {
                    offsets = {
                        {
                            -- filetype = "NvimTree",
                            filetype = "neo-tree",
                            text = "Neo-tree",
                            highlight = "Directory",
                            text_align = "left",
                            separator = true -- use a "true" to enable the default, or set your own character
                        },
                    },
                },
            })
        end
    },

    -- https://github.com/nvim-lualine/lualine.nvim
    {
        'nvim-lualine/lualine.nvim',
        event = "VeryLazy",
        dependencies = {
            'nvim-tree/nvim-web-devicons'
        },
        config = function()
            require("lualine").setup({
                options = {
                    icons_enabled = true,
                    theme = "auto",

                    -- Do not show lualine on neo-tree
                    disabled_filetypes = {
                        "neo-tree",
                        sections = {},
                        winbar = {},
                    }
                },
                sections = {
                    lualine_a = { 'mode' },
                    lualine_b = { 'branch', 'diff', 'diagnostics' },
                    lualine_c = { 'filename', 'lsp_status', vim.g.minuet_ai_enabled and { require("minuet.lualine") } or nil },
                    lualine_x = { 'encoding', 'fileformat', 'filetype' },
                    lualine_y = { 'progress' },
                    lualine_z = { 'location' }
                },
                winbar = {
                    lualine_a = {
                        {
                            function()
                                return require("nvim-navic").get_location()
                            end,
                            cond = function()
                                return require("nvim-navic").is_available()
                            end,
                        }
                    },
                    lualine_b = {},
                    lualine_c = {},
                    lualine_x = {},
                    lualine_y = {},
                    lualine_z = { 'hostname' },
                },
            })
        end
    },

    -- https://github.com/nvim-neo-tree/neo-tree.nvim
    {
        {
            "nvim-neo-tree/neo-tree.nvim",
            branch = "v3.x",
            dependencies = {
                "nvim-lua/plenary.nvim",
                "MunifTanjim/nui.nvim",
                "nvim-tree/nvim-web-devicons", -- optional, but recommended
            },
            lazy = false,                      -- neo-tree will lazily load itself
            config = function()
                require("neo-tree").setup({
                    source_selector = {
                        winbar = true,
                        statusline = true
                    },
                    filesystem = {
                        filtered_items = {
                            hide_dotfiles = false,
                            hide_gitignored = false,
                            hide_ignored = false,
                        },
                        follow_current_file = {
                            enabled = true,
                            leave_dirs_open = true,
                        },
                        use_libuv_file_watcher = true,
                    },
                    buffers = {
                        follow_current_file = {
                            enabled = true,
                        },
                    },
                    event_handlers = {
                        {
                            event = "vim_buffer_enter",
                            handler = function()
                                vim.opt_local.number = true
                            end,
                        },
                    },
                })
            end
        }
    },

    -- https://github.com/rachartier/tiny-inline-diagnostic.nvim
    {
        "rachartier/tiny-inline-diagnostic.nvim",
        event = "VeryLazy",
        priority = 1000,
        config = function()
            require('tiny-inline-diagnostic').setup({
                preset = "powerline",
                options = {
                    show_source = {
                        enable = true,
                        if_many = false,
                    },
                    multilines = {
                        -- Enable multiline diagnostic messages
                        enabled = true,
                        -- Always show messages on all lines for multiline diagnostics
                        always_show = true,
                    }
                }
            })
            vim.diagnostic.config({ virtual_text = false }) -- Disable default virtual text
        end
    },

    -- https://github.com/folke/which-key.nvim
    {
        "folke/which-key.nvim",
        event = "VeryLazy",
        opts = {
            -- your configuration comes here
            -- or leave it empty to use the default settings
            -- refer to the configuration section below
        },
        keys = {
            {
                "<leader>?",
                function()
                    require("which-key").show({ global = false })
                end,
                desc = "Buffer Local Keymaps (which-key)",
            },
            {
                "<localleader>?",
                function()
                    require("which-key").show({ global = false })
                end,
                desc = "Buffer Local Keymaps (which-key)",
            },
        },
    },

    -- https://github.com/sphamba/smear-cursor.nvim
    {
        "sphamba/smear-cursor.nvim",
        opts = {},
    },

    {
        "SmiteshP/nvim-navic",
        opts = {
            lsp = {
                auto_attach = true,
            }
        }
    },

    {
        "lukas-reineke/indent-blankline.nvim",
        main = "ibl",
        opts = {},
    },

    {
        "hedyhli/outline.nvim",
        lazy = true,
        cmd = { "Outline", "OutlineOpen" },
        keys = { -- Example mapping to toggle outline
            { "<leader>o", "<cmd>Outline<CR>", desc = "Toggle outline" },
        },
        opts = {
            -- Your setup opts here
        },
    },


    -- {
    --     'VonHeikemen/fine-cmdline.nvim',
    --     dependencies = {
    --         'MunifTanjim/nui.nvim'
    --     }
    -- }
}
