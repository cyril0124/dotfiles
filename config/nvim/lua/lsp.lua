vim.api.nvim_create_autocmd("LspAttach", {
    callback = function(args)
        local bufnr = args.buf
        local client = vim.lsp.get_client_by_id(args.data.client_id)
        local keymap = vim.keymap
        local lsp = vim.lsp

        keymap.set("n", "gr", lsp.buf.references,
            { buffer = bufnr, noremap = true, silent = true, desc = "LSP get references" })
        keymap.set("n", "gd", lsp.buf.definition,
            { buffer = bufnr, noremap = true, silent = true, desc = "LSP goto definition" })
        keymap.set("n", "<space>rn", lsp.buf.rename,
            { buffer = bufnr, noremap = true, silent = true, desc = "LSP rename" })

        if client and client:supports_method("textDocument/inlayHint") then
            vim.lsp.inlay_hint.enable(true, { bufnr = bufnr })
        end

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

vim.keymap.set('n', '<leader>k', function()
    require('hover').open()
end, { desc = 'hover.nvim (open)', noremap = true, silent = true })

vim.keymap.set('n', 'gK', function()
    require('hover').enter()
end, { desc = 'hover.nvim (enter)', noremap = true, silent = true })

-- Enable inlay hints for supported languages
-- Auto enabled by mason-lspconfig
vim.lsp.config("emmylua_ls", {
    cmd = { "emmylua_ls" },
    filetypes = { "lua" },
    root_markers = {
        ".luarc.json",
        ".emmyrc.json",
        ".emmyrc.lua",
        ".luacheckrc",
    },
    workspace_required = false,
})

vim.lsp.enable("emmylua_ls")

vim.lsp.config("slang-server", {
    cmd = { "slang-server" },
    root_markers = { ".git", ".slang" },
    filetypes = {
        "systemverilog",
        "verilog",
    },
})

vim.lsp.enable("slang-server")
