local wezterm = require("wezterm")
local config = wezterm.config_builder()

-- Window styling
config.window_decorations = "NONE" -- Hides window controls and borders
config.window_padding = {
  left = 0,
  right = 0,
  top = 0,
  bottom = 0,
}

-- Return the configuration
return config
