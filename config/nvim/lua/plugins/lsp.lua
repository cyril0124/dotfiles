local function get_markview_diff_line_hl(line)
    if line:match("^diff%s") or line:match("^index%s") or line:match("^new file mode%s")
        or line:match("^deleted file mode%s") or line:match("^similarity index%s")
        or line:match("^rename from%s") or line:match("^rename to%s")
        or line:match("^%-%-%-") or line:match("^%+%+%+") then
        return "MarkviewMarkdownDiffMeta"
    elseif vim.startswith(line, "+") then
        return "MarkviewMarkdownDiffAdd"
    elseif vim.startswith(line, "-") then
        return "MarkviewMarkdownDiffDelete"
    else
        return "MarkviewMarkdownDiffContext"
    end
end

local function apply_markview_diff_highlights()
    local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false, create = false })
    local markview_code = vim.api.nvim_get_hl(0, { name = "MarkviewCode", link = false, create = false })
    local diff_add = vim.api.nvim_get_hl(0, { name = "DiffAdd", link = false, create = false })
    local diff_delete = vim.api.nvim_get_hl(0, { name = "DiffDelete", link = false, create = false })
    local git_add = vim.api.nvim_get_hl(0, { name = "GitSignsAdd", link = false, create = false })
    local git_delete = vim.api.nvim_get_hl(0, { name = "GitSignsDelete", link = false, create = false })
    local git_change = vim.api.nvim_get_hl(0, { name = "GitSignsChange", link = false, create = false })
    local diff_plus = vim.api.nvim_get_hl(0, { name = "@diff.plus", link = false, create = false })
    local diff_minus = vim.api.nvim_get_hl(0, { name = "@diff.minus", link = false, create = false })
    local diff_delta = vim.api.nvim_get_hl(0, { name = "@diff.delta", link = false, create = false })

    local code_bg = markview_code.bg or normal.bg
    local normal_fg = normal.fg
    local add_fg = diff_plus.fg or git_add.fg or normal_fg
    local delete_fg = diff_minus.fg or git_delete.fg or normal_fg
    local meta_fg = git_add.fg or diff_plus.fg or diff_delta.fg or git_change.fg or normal_fg

    vim.api.nvim_set_hl(0, "MarkviewMarkdownDiffAdd", {
        fg = add_fg,
        bg = diff_add.bg or code_bg,
        bold = diff_add.bold,
        italic = diff_add.italic,
    })
    vim.api.nvim_set_hl(0, "MarkviewMarkdownDiffDelete", {
        fg = delete_fg,
        bg = diff_delete.bg or code_bg,
        bold = diff_delete.bold,
        italic = diff_delete.italic,
    })
    vim.api.nvim_set_hl(0, "MarkviewMarkdownDiffMeta", {
        fg = meta_fg,
        bg = code_bg,
        bold = git_add.bold or diff_plus.bold,
        italic = git_add.italic or diff_plus.italic,
    })
    vim.api.nvim_set_hl(0, "MarkviewMarkdownDiffContext", {
        fg = normal_fg,
        bg = code_bg,
    })
end

return {
    {
        'numToStr/Comment.nvim',
    },

    -- https://github.com/stevearc/conform.nvim
    {
        'stevearc/conform.nvim',
    },

    -- {
    --     "mason-org/mason.nvim",
    --     config = function()
    --         require("mason").setup({})
    --     end
    -- },

    {
        "mason-org/mason-lspconfig.nvim",
        event = { "BufReadPre", "BufNewFile" },
        cmd = {
            "Mason",
            "MasonInstall",
            "MasonUpdate",
            "MasonUninstall",
            "MasonUninstallAll",
            "MasonLog",
        },
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
                    "jsonls",
                    "rust_analyzer",
                    "ty",
                },
                automatic_enable = true,
            })
        end
    },

    {
        "scalameta/nvim-metals",
        ft = { "scala", "sbt", "java" },
        opts = function()
            local config = require("lua.config")

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

            if config.proxy_ip then
                metals_config.settings.serverProperties = {
                    "-Dhttp.proxyHost=" .. config.proxy_ip,
                    "-Dhttp.proxyPort=" .. config.proxy_port,
                    "-Dhttps.proxyHost=" .. config.proxy_ip,
                    "-Dhttps.proxyPort=" .. config.proxy_port,
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
        "OXY2DEV/markview.nvim",
        ft = "markdown",
        opts = {
            preview = { enable = false },
            markdown = {
                code_blocks = {
                    min_width = 72,
                    pad_amount = 1,
                    ["diff"] = {
                        block_hl = function(_, line)
                            return get_markview_diff_line_hl(line)
                        end,
                        pad_hl = function(_, line)
                            return get_markview_diff_line_hl(line)
                        end,
                    },
                },
            },
        },
        config = function(_, opts)
            require("markview").setup(opts)
            apply_markview_diff_highlights()

            local markview_diff_group = vim.api.nvim_create_augroup("markview-diff-highlights", { clear = true })
            vim.api.nvim_create_autocmd("ColorScheme", {
                group = markview_diff_group,
                callback = apply_markview_diff_highlights,
            })

            local ok_state, state = pcall(require, "markview.state")
            local ok_actions, actions = pcall(require, "markview.actions")
            if not (ok_state and ok_actions) then
                return
            end

            for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
                if vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].filetype == "markdown" and state.buf_attached(bufnr) then
                    actions.disable(bufnr)
                end
            end
        end,
    },

    -- https://github.com/ray-x/lsp_signature.nvim
    {
        "ray-x/lsp_signature.nvim",
        event = "LspAttach",
        opts = {
            hint_enable = true,
            handler_opts = {
                border = "rounded",
            },
        },
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
