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

-- Theme Mapping Table: Neovim colorscheme -> WezTerm colorscheme
local theme_map = {
  ["catppuccin-latte"] = "Catppuccin Latte",
  ["catppuccin-frappe"] = "Catppuccin Frappe",
  ["catppuccin-macchiato"] = "Catppuccin Macchiato",
  ["catppuccin-mocha"] = "Catppuccin Mocha",
  ["tokyonight-night"] = "Tokyo Night",
  ["tokyonight-storm"] = "Tokyo Night Storm",
  ["tokyonight-day"] = "Tokyo Night Day",
  ["gruvbox"] = "Gruvbox Dark (base16)",
  ["rose-pine"] = "Rosé Pine",
  ["rose-pine-moon"] = "Rosé Pine Moon",
  ["rose-pine-dawn"] = "Rosé Pine Dawn",
  ["kanagawa"] = "Kanagawa Dragon",
  ["nord"] = "Nord",
  ["cyberdream"] = "Cyberdream",
}

-- State variables to track theme checks
local last_theme = nil

wezterm.on("update-status", function(window, pane)
  -- Read colorscheme state written by Neovim
  local state_path = wezterm.home_dir .. "/.local/share/vide/theme.state"
  local file = io.open(state_path, "r")
  if file then
    local theme = file:read("*l")
    file:close()
    if theme and theme ~= last_theme then
      last_theme = theme
      -- Resolve WezTerm equivalent theme name
      local wez_theme = theme_map[theme] or "Catppuccin Mocha"
      local overrides = window:get_config_overrides() or {}
      overrides.color_scheme = wez_theme
      window:set_config_overrides(overrides)
    end
  end
end)

-- Return the configuration
return config

