vim.api.nvim_create_autocmd("LspAttach", {
    callback = function(args)
        local keymap = vim.keymap
        local lsp = vim.lsp

        keymap.set("n", "gr", lsp.buf.references, { noremap = true, silent = true, desc = "LSP get references" })
        keymap.set("n", "gd", lsp.buf.definition, { noremap = true, silent = true, desc = "LSP goto definition" })
        keymap.set("n", "<space>rn", lsp.buf.rename, { noremap = true, silent = true, desc = "LSP rename" })

        -- keymap.set("n", "K", lsp.buf.hover, { noremap = true, silent = true, desc = "LSP hover" })
        -- keymap.set('n', 'K', function()
        --     require('hover').open()
        -- end, { desc = 'hover.nvim (open)', noremap = true, silent = true })
        -- keymap.set('n', 'gK', function()
        --     require('hover').enter()
        -- end, { desc = 'hover.nvim (enter)', noremap = true, silent = true })
    end
})

vim.keymap.set('n', 'K', function()
    require('hover').open()
end, { desc = 'hover.nvim (open)', noremap = true, silent = true })

vim.keymap.set('n', 'gK', function()
    require('hover').enter()
end, { desc = 'hover.nvim (enter)', noremap = true, silent = true })

vim.keymap.set('n', '<leader>k', function()
    require('hover').open()
end, { desc = 'hover.nvim (open)', noremap = true, silent = true })

vim.keymap.set('n', '<leader>gk', function()
    require('hover').enter()
end, { desc = 'hover.nvim (open)', noremap = true, silent = true })

-- Enable inlay hints for supported languages
vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
    -- pattern = { "*.scala", "*.lua", "*.cc", "*.cpp", "*.h", "*.py", "*.rs" },
    pattern = { "*.lua", "*.cc", "*.cpp", "*.h", "*.py", "*.rs" },
    callback = function()
        vim.lsp.inlay_hint.enable(true)
    end,
})


-- Auto enabled by mason-lspconfig
-- vim.lsp.enable({"emmylua_ls"})

vim.lsp.config("slang-server", {
    cmd = { "slang-server" },
    root_markers = { ".git", ".slang" },
    filetypes = {
        "systemverilog",
        "verilog",
    },
})

vim.lsp.enable("slang-server")
