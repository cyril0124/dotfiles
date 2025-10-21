-- https://github.com/folke/snacks.nvim

return {
    "folke/snacks.nvim",
    opts = {
        bigfile = {
            enabled = true,
            notify = true,           -- show notification when big file detected
            size = 15 * 1024 * 1024, -- 15MB
            line_length = 1000,      -- average line length (useful for minified files)

            -- Enable or disable features when big file detected
            setup = function(ctx)
                if vim.fn.exists(":NoMatchParen") ~= 0 then
                    vim.cmd([[NoMatchParen]])
                end

                Snacks.util.wo(0, { foldmethod = "manual", statuscolumn = "", conceallevel = 0 })

                vim.schedule(function()
                    if vim.api.nvim_buf_is_valid(ctx.buf) then
                        vim.bo[ctx.buf].syntax = ctx.ft
                    end
                end)

                require("smear_cursor").enabled = false

                -- Disable some mini.nvim plugins for big files
                vim.b.minianimate_disable = true
                vim.b.minihipatterns_disable = true
                vim.b.minicursorword_disable = true
                vim.b.minitrailspace_disable = true
                vim.b.minijump_disable = true
            end
        }
    }
}
