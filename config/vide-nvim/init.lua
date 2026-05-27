-- Set leader key to space
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- Basic Options
local opt = vim.opt
opt.number = true             -- Show line numbers
opt.relativenumber = true     -- Show relative line numbers
opt.mouse = "a"               -- Enable mouse support in all modes
opt.clipboard = "unnamedplus"   -- Sync with system clipboard
opt.tabstop = 4               -- Number of spaces that a Tab in the file counts for
opt.shiftwidth = 4            -- Number of spaces to use for each step of (auto)indent
opt.expandtab = true          -- Use spaces instead of tabs
opt.smartindent = true        -- Smart autoindenting
opt.termguicolors = true      -- True color support

-- Bootstrap lazy.nvim
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable", -- latest stable release
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

-- Setup lazy.nvim with theme plugins
require("lazy").setup({
  { "catppuccin/nvim", name = "catppuccin", priority = 1000 },
  { "folke/tokyonight.nvim", priority = 1000 },
  { "rose-pine/neovim", name = "rose-pine", priority = 1000 },
  { "rebelot/kanagawa.nvim", priority = 1000 },
}, {})

-- Hook to write active colorscheme to file
vim.api.nvim_create_autocmd("ColorScheme", {
  callback = function()
    local theme = vim.g.colors_name
    if theme then
      local state_path = vim.fn.expand("~/.local/share/vide/theme.state")
      local f = io.open(state_path, "w")
      if f then
        f:write(theme)
        f:close()
      end
    end
  end
})

-- Load default colorscheme
vim.cmd("colorscheme catppuccin-mocha")

-- Start RPC Server based on WezTerm Pane ID
local nvim_pane_id = vim.env.WEZTERM_PANE
if nvim_pane_id then
  local pipe_path = "/tmp/vide_nvim_" .. nvim_pane_id .. ".pipe"
  pcall(vim.fn.serverstart, pipe_path)
end

-- Sync Neovim directory changes to Yazi file explorer
local function sync_to_yazi()
  if not nvim_pane_id then return end
  local file_path = vim.api.nvim_buf_get_name(0)
  local dir
  if file_path ~= "" and vim.bo.buftype == "" then
    dir = vim.fn.fnamemodify(file_path, ":p:h")
  elseif vim.bo.buftype == "" then
    dir = vim.fn.getcwd()
  end
  if dir and vim.fn.isdirectory(dir) == 1 then
    local target_yazi = "vide_yazi_" .. nvim_pane_id
    vim.fn.jobstart({ "ya", "emit-to", target_yazi, "cd", dir }, { detach = true })
  end
end

vim.api.nvim_create_autocmd({ "BufEnter", "DirChanged" }, {
  callback = sync_to_yazi
})

-- Initialize layout state to IDE mode on boot
local layout_state_path = vim.fn.expand("~/.local/share/vide/layout.state")
local f = io.open(layout_state_path, "w")
if f then
  f:write("ide")
  f:close()
end

-- Toggle layout mode function
local function toggle_mode()
  -- Read current layout mode
  local current_mode = "ide"
  local rf = io.open(layout_state_path, "r")
  if rf then
    current_mode = rf:read("*l") or "ide"
    rf:close()
  end
  
  local next_mode = (current_mode == "ide") and "zen" or "ide"
  
  -- Write next layout mode
  local wf = io.open(layout_state_path, "w")
  if wf then
    wf:write(next_mode)
    wf:close()
  end
  
  -- Adjust splits based on the mode
  if nvim_pane_id then
    if next_mode == "zen" then
      -- Find left pane (Yazi)
      local handle = io.popen("wezterm cli get-pane-direction Left 2>/dev/null")
      if handle then
        local left_pane_id = handle:read("*l")
        handle:close()
        if left_pane_id and left_pane_id ~= "" then
          vim.fn.jobstart({ "wezterm", "cli", "kill-pane", "--pane-id", left_pane_id })
        end
      end
    else
      -- Re-spawn left pane split running Yazi
      vim.fn.jobstart({
        "bash", "-c",
        "wezterm cli split-pane --left --percent 15 -- bash -c 'YAZI_ID=vide_yazi_" .. nvim_pane_id .. " yazi' && wezterm cli activate-pane --pane-id " .. nvim_pane_id
      }, {
        on_exit = function()
          -- Automatically synchronize tree to current directory after split opens
          sync_to_yazi()
        end
      })
    end
  end
end

vim.keymap.set("n", "<leader>mt", toggle_mode, { desc = "Toggle IDE/Zen Mode" })

-- Smart focus navigation between Neovim splits and WezTerm panes
local function navigate(direction, wez_dir)
  local current_win = vim.api.nvim_get_current_win()
  vim.cmd("wincmd " .. direction)
  if vim.api.nvim_get_current_win() == current_win then
    -- We hit the edge of Neovim splits, switch WezTerm pane
    vim.fn.jobstart({ "wezterm", "cli", "activate-pane-direction", wez_dir })
  end
end

vim.keymap.set({ "n", "t" }, "<A-h>", function() navigate("h", "Left") end, { desc = "Focus Left split/pane" })
vim.keymap.set({ "n", "t" }, "<A-j>", function() navigate("j", "Down") end, { desc = "Focus Down split/pane" })
vim.keymap.set({ "n", "t" }, "<A-k>", function() navigate("k", "Up") end, { desc = "Focus Up split/pane" })
vim.keymap.set({ "n", "t" }, "<A-l>", function() navigate("l", "Right") end, { desc = "Focus Right split/pane" })




