local config = require("lua.config")

local specs = {
    { "folke/tokyonight.nvim" },
    { "catppuccin/nvim", name = "catppuccin" },
    { "rebelot/kanagawa.nvim" },
    { "rose-pine/neovim", name = "rose-pine" },
}

for _, spec in ipairs(specs) do
    local name = spec.name or spec[1]:match("[^/]+$"):gsub("%.nvim$", "")
    if name == config.colorscheme then
        spec.lazy = false
        spec.priority = 1000
    else
        spec.lazy = true
    end
end

return specs
