local wezterm = require("wezterm")
local mux = wezterm.mux
local config = wezterm.config_builder()

-- GUI Startup Event: Handles splitting the main window
wezterm.on("gui-startup", function(cmd)
  local tab, pane, window = mux.spawn_window(cmd or {})
  local pane_id = pane:pane_id()
  
  -- Split vertical pane to the left (15% width) to run Yazi file explorer
  local yazi_pane = pane:split {
    direction = "Left",
    size = 0.15,
    args = { "yazi" },
    set_environment_variables = {
      YAZI_ID = "vide_yazi_" .. tostring(pane_id)
    }
  }
  
  -- Ensure editing pane (Neovim) holds key focus
  pane:activate()
end)


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

-- State variables to track theme and layout checks
local last_theme = nil
local last_layout = nil

wezterm.on("update-status", function(window, pane)
  local overrides = window:get_config_overrides() or {}
  local changed = false

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
      overrides.color_scheme = wez_theme
      changed = true
    end
  end

  -- Read layout state written by Neovim
  local layout_path = wezterm.home_dir .. "/.local/share/vide/layout.state"
  local layout_file = io.open(layout_path, "r")
  if layout_file then
    local layout = layout_file:read("*l")
    layout_file:close()
    if layout and layout ~= last_layout then
      last_layout = layout
      if layout == "zen" then
        overrides.enable_tab_bar = false
      else
        overrides.enable_tab_bar = true
      end
      changed = true
    end
  end

  if changed then
    window:set_config_overrides(overrides)
  end
end)


-- Return the configuration
return config

