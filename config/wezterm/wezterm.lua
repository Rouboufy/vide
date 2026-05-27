local wezterm = require("wezterm")
local mux = wezterm.mux
local config = wezterm.config_builder()

-- Disable native Wayland to resolve startup hangs on certain graphics drivers (forces XWayland)
config.enable_wayland = false


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
  ["vscode"] = "Visual Studio Code",
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
      
      -- If theme is VSCode, apply exact color overrides to match VSCode's editor look perfectly
      if theme == "vscode" then
        overrides.colors = {
          background = "#1e1e1e",
          foreground = "#d4d4d4",
          cursor_bg = "#aeafad",
          cursor_fg = "#1e1e1e",
          cursor_border = "#aeafad",
          selection_bg = "#264f78",
          selection_fg = "#ffffff",
          ansi = {
            "#1e1e1e", "#f44747", "#6a9955", "#d7ba7d",
            "#569cd6", "#c586c0", "#4fc1ff", "#d4d4d4"
          },
          brights = {
            "#808080", "#f44747", "#6a9955", "#d7ba7d",
            "#569cd6", "#c586c0", "#4fc1ff", "#ffffff"
          }
        }
      else
        overrides.colors = nil
      end
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


-- Helper function to check if active pane runs Vim/Neovim
local function is_vim(pane)
  local process_name = pane:get_foreground_process_name()
  if not process_name then
    return false
  end
  local basename = string.gsub(process_name, "(.*[/\\])(.*)", "%2")
  return string.find(basename, "n?vim") ~= nil
end

-- Smart pane movement direction action callback
local function move_pane(direction, key)
  return wezterm.action_callback(function(window, pane)
    if is_vim(pane) then
      -- Pass the Alt key to Neovim
      window:perform_action(wezterm.action.SendKey{ key = key, mods = "ALT" }, pane)
    else
      -- Directly move focus in WezTerm
      window:perform_action(wezterm.action.ActivatePaneDirection(direction), pane)
    end
  end)
end

config.keys = {
  { key = "h", mods = "ALT", action = move_pane("Left", "h") },
  { key = "l", mods = "ALT", action = move_pane("Right", "l") },
  { key = "k", mods = "ALT", action = move_pane("Up", "k") },
  { key = "j", mods = "ALT", action = move_pane("Down", "j") },
}

-- Return the configuration
return config


