local kind_icons = {
    -- LLM Provider icons
    claude = '󰋦',
    openai = '󱢆',
    codestral = '󱎥',
    gemini = '',
    Groq = '',
    Openrouter = '󱂇',
    Ollama = '󰳆',
    ['Llama.cpp'] = '󰳆',
    Deepseek = ''
}

local source_icons = {
    minuet = '󱗻',
    orgmode = '',
    otter = '󰼁',
    nvim_lsp = '',
    lsp = '',
    buffer = '',
    luasnip = '',
    snippets = '',
    path = '',
    git = '',
    tags = '',
    cmdline = '󰘳',
    latex_symbols = '',
    cmp_nvim_r = '󰟔',
    codeium = '󰩂',
    -- FALLBACK
    fallback = '󰜚',
}

return {
    'saghen/blink.cmp',
    -- optional: provides snippets for the snippet source
    dependencies = {
        'rafamadriz/friendly-snippets',
    },

    -- use a release tag to download pre-built binaries
    version = '1.*',
    -- AND/OR build from source, requires nightly: https://rust-lang.github.io/rustup/concepts/channels.html#working-with-nightly-rust
    -- build = 'cargo build --release',
    -- If you use nix, you can build from source using latest nightly rust with:
    -- build = 'nix run .#build-plugin',

    ---@module 'blink.cmp'
    ---@type blink.cmp.Config
    opts = {
        -- 'default' (recommended) for mappings similar to built-in completions (C-y to accept)
        -- 'super-tab' for mappings similar to vscode (tab to accept)
        -- 'enter' for enter to accept
        -- 'none' for no mappings
        --
        -- All presets have the following mappings:
        -- C-space: Open menu or open docs if already open
        -- C-n/C-p or Up/Down: Select next/previous item
        -- C-e: Hide menu
        -- C-k: Toggle signature help (if signature.enabled = true)
        --
        -- See :h blink-cmp-config-keymap for defining your own keymap
        keymap = {
            preset = 'default',

            ['<CR>'] = { "accept", "fallback" }, -- <Enter> to accept

            -- Ctrl+c to enable minuet completion
            ['<C-c>'] = vim.g.minuet_ai_enabled and require("minuet").make_blink_map() or nil,
        },

        appearance = {
            -- 'mono' (default) for 'Nerd Font Mono' or 'normal' for 'Nerd Font'
            -- Adjusts spacing to ensure icons are aligned
            -- nerd_font_variant = 'mono',

            use_nvim_cmp_as_default = true,
            nerd_font_variant = 'normal',
            kind_icons = kind_icons
        },

        completion = {
            -- documentation = { auto_show = false },

            -- Display a previewof the selected item on the current line
            ghost_text = {
                enabled = true,
            },

            trigger = {
                -- Suggested by the `minuet.nvim`
                -- When true, will prefetch the completion items when entering insert mode
                -- prefetch_on_insert = false,

                -- When true, will show completion window after backspacing
                -- show_on_backspace = true,

                -- When true, will show the completion window after entering insert mode
                -- show_on_insert = true,
            },

            menu = {
                draw = {
                    columns = {
                        { 'label',      'label_description', gap = 1 },
                        { 'kind_icon',  'kind' },
                        { 'source_icon' },
                    },
                    components = {
                        source_icon = {
                            -- don't truncate source_icon
                            ellipsis = false,
                            text = function(ctx)
                                return source_icons[ctx.source_name:lower()] or source_icons.fallback
                            end,
                            highlight = 'BlinkCmpSource',
                        },
                    },
                },
            },
        },

        -- Default list of enabled providers defined so that you can extend it
        -- elsewhere in your config, without redefining it, due to `opts_extend`
        sources = {
            -- default = { 'lsp', 'path', 'snippets', 'buffer' },
            default = { 'lsp', 'path', 'snippets', 'buffer', vim.g.minuet_ai_enabled and 'minuet' or nil },
            providers = {
                minuet = {
                    name = 'minuet',
                    module = 'minuet.blink',
                    async = true,
                    -- Should match minuet.config.request_timeout * 1000,
                    -- since minuet.config.request_timeout is in seconds
                    timeout_ms = 2000,
                    score_offset = 50, -- Gives minuet higher priority among suggestions
                },
            },
        },

        -- (Default) Rust fuzzy matcher for typo resistance and significantly better performance
        -- You may use a lua implementation instead by using `implementation = "lua"` or fallback to the lua implementation,
        -- when the Rust fuzzy matcher is not available, by using `implementation = "prefer_rust"`
        --
        -- See the fuzzy documentation for more information
        fuzzy = { implementation = "prefer_rust_with_warning" }
    },
    opts_extend = { "sources.default" }
}

