local wezterm = require 'wezterm'
local config = {}

-- config.color_scheme = 'Batman'
config.color_scheme = 'Tokyo Night'
config.font_size = 14.0
config.window_background_opacity = 0.8
config.macos_window_background_blur = 30

config.font = wezterm.font_with_fallback({
    'JetBrainsMono NF',
    -- 'PingFang SC', -- 中文字体, 需要另外安装
    'Heiti SC',
})

return config
