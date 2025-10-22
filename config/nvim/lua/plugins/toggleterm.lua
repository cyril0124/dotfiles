return {
    "akinsho/toggleterm.nvim",
    version = "*",
    opts = {
        shell = "/bin/zsh",
        on_open = function(term)
            vim.keymap.set("t", "<Esc>", [[<C-\><C-n>]], {
                buffer = term.bufnr,
                desc = "Exit terminal insert mode",
            })
        end
    },
}
