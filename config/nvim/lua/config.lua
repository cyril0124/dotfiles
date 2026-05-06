local M = {}

-- Colorscheme
M.colorscheme = "catppuccin"

-- Available themes (for menu switcher)
M.themes = { "tokyonight", "catppuccin", "kanagawa", "rose-pine" }

-- AI provider: "codestral" or "deepseek"
M.ai_provider = os.getenv("DS_AI") and "deepseek" or "codestral"

-- Proxy (auto-detect from env)
local http_proxy = os.getenv("http_proxy") or os.getenv("HTTP_PROXY")
    or os.getenv("https_proxy") or os.getenv("HTTPS_PROXY")
if http_proxy then
    local url = http_proxy:gsub("^https?://", ""):gsub("^[^@]+@", "")
    M.proxy_ip = url:match("^([^:/]+)")
    local port_str = url:match(":([^:/]*)")
    M.proxy_port = port_str and tonumber(port_str) or nil
end

return M
