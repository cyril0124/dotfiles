local M = {}

-- Colorscheme
M.colorscheme = "catppuccin"

-- Available themes (for menu switcher)
M.themes = { "tokyonight", "catppuccin", "kanagawa", "rose-pine" }

-- AI provider: "codestral" or "deepseek"
M.ai_provider = os.getenv("DS_AI") and "deepseek" or "codestral"

-- Proxy (auto-detect from env)
local http_proxy = os.getenv("http_proxy") or os.getenv("HTTP_PROXY")
if http_proxy then
    M.proxy_ip = string.match(http_proxy, "http://([^:]+):")
    M.proxy_port = string.match(http_proxy, "http://[^:]+:(%d+)")
end

return M
