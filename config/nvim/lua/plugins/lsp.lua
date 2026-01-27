return {
    {
        'numToStr/Comment.nvim',
    },

    -- https://github.com/stevearc/conform.nvim
    {
        'stevearc/conform.nvim',
    },

    {
        "lewis6991/hover.nvim",
        config = function()
            require("hover").setup({
                providers = {
                    'hover.providers.diagnostic',
                    'hover.providers.lsp',
                    'hover.providers.dap',
                    'hover.providers.man',
                    -- 'hover.providers.dictionary',
                },
                preview_opts = {
                    border = 'single'
                },
                mouse_providers = {
                    'hover.providers.lsp',
                },
            })
        end
    },

    -- {
    --     "mason-org/mason.nvim",
    --     config = function()
    --         require("mason").setup({})
    --     end
    -- },

    {
        "mason-org/mason-lspconfig.nvim",
        -- opts = {},
        version = "2.*",
        dependencies = {
            { "mason-org/mason.nvim", opts = {}, version = "2.*" },
            "neovim/nvim-lspconfig",
        },
        config = function()
            require("mason").setup({})
            require("mason-lspconfig").setup({
                ensure_installed = {
                    "emmylua_ls",
                    "clangd",
                    "rust_analyzer",
                },
                automatic_enable = true,
            })
        end
    },

    {
        "scalameta/nvim-metals",
        ft = { "scala", "sbt", "java" },
        opts = function()
            local proxy_ip
            local proxy_port
            local http_proxy = os.getenv("http_proxy") or os.getenv("HTTP_PROXY")
            if not http_proxy then
                vim.notify("[nvim-metals] `http_proxy` or `HTTP_PROXY` env var not set!", vim.log.levels.INFO)
            else
                proxy_ip = string.match(http_proxy, "http://([^:]+):")
                proxy_port = string.match(http_proxy, "http://[^:]+:(%d+)")
                vim.notify("[nvim-metals] " .. "proxy_ip: " .. proxy_ip .. ", proxy_port: " .. proxy_port,
                    vim.log.levels.INFO)
            end

            local metals_config = require("metals").bare_config()
            metals_config.settings = {
                inlayHints = {
                    byNameParameters = { enable = true },
                    hintsInPatternMatch = { enable = true },
                    implicitArguments = { enable = true },
                    implicitConversions = { enable = true },
                    inferredTypes = { enable = true },
                    typeParameters = { enable = true },
                },
            }

            if http_proxy then
                metals_config.settings.serverProperties = {
                    "-Dhttp.proxyHost=" .. proxy_ip,
                    "-Dhttp.proxyPort=" .. proxy_port,
                    "-Dhttps.proxyHost=" .. proxy_ip,
                    "-Dhttps.proxyPort=" .. proxy_port,
                }
            end

            metals_config.on_attach = function(client, bufnr)
                -- your on_attach function
            end

            return metals_config
        end,
        config = function(self, metals_config)
            local nvim_metals_group = vim.api.nvim_create_augroup("nvim-metals", { clear = true })
            vim.api.nvim_create_autocmd("FileType", {
                pattern = self.ft,
                callback = function()
                    require("metals").initialize_or_attach(metals_config)
                end,
                group = nvim_metals_group,
            })
        end
    },

    {
        'MeanderingProgrammer/render-markdown.nvim',
        opts = {
            enabled = false,
        },
        ft = 'markdown',
    },

    {
        {
            "hudson-trading/slang-server.nvim",
            dependencies = {
                "MunifTanjim/nui.nvim",
            },
            opts = {},
        },
    }
}
