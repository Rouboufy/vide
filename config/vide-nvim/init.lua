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

-- Setup lazy.nvim with theme and utility plugins
require("lazy").setup({
  { "catppuccin/nvim", name = "catppuccin", priority = 1000 },
  { "folke/tokyonight.nvim", priority = 1000 },
  { "rose-pine/neovim", name = "rose-pine", priority = 1000 },
  { "rebelot/kanagawa.nvim", priority = 1000 },
  { "Mofiqul/vscode.nvim", priority = 1000 },
  -- Fallback file explorer for SSH/remote sessions
  {
    "nvim-neo-tree/neo-tree.nvim",
    branch = "v3.x",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-tree/nvim-web-devicons",
      "MunifTanjim/nui.nvim",
    },
    config = function()
      require("neo-tree").setup({
        close_if_last_window = true,
        window = {
          width = 25,
        }
      })
    end
  },

  -- Rich Tabline / Bufferline
  {
    "akinsho/bufferline.nvim",
    version = "*",
    dependencies = "nvim-tree/nvim-web-devicons",
    config = function()
      require("bufferline").setup({
        options = {
          diagnostics = "nvim_lsp",
          separator_style = "thin",
          show_buffer_close_icons = true,
          show_close_icon = false,
          always_show_bufferline = true,
          offsets = {
            {
              filetype = "neo-tree",
              text = "File Explorer",
              text_align = "left",
              separator = true
            }
          }
        }
      })
    end
  },
  -- Git integration decorations
  {
    "lewis6991/gitsigns.nvim",
    config = function()
      require("gitsigns").setup()
    end
  },
  -- Keybindings visual aid helper
  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    config = function()
      require("which-key").setup()
    end
  },
  -- Telescope search engine
  {
    "nvim-telescope/telescope.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    config = function()
      require("telescope").setup()
    end
  },
  -- Indentation Guides
  {
    "lukas-reineke/indent-blankline.nvim",
    main = "ibl",
    config = function()
      require("ibl").setup({
        indent = { char = "│" },
        scope = { enabled = false },
      })
    end
  },
  -- Winbar breadcrumbs
  {
    "utilyre/barbecue.nvim",
    name = "barbecue",
    version = "*",
    dependencies = {
      "SmiteshP/nvim-navic",
      "nvim-tree/nvim-web-devicons",
    },
    config = function()
      require("barbecue").setup()
    end
  },
  -- Dashboard / Welcome Screen
  {
    "goolord/alpha-nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    config = function()
      local alpha = require("alpha")
      local dashboard = require("alpha.themes.dashboard")
      dashboard.section.header.val = {
        "                    ██╗   ██╗██╗██████╗ ███████╗",
        "                    ██║   ██║██║██╔══██╗██╔════╝",
        "                    ██║   ██║██║██║  ██║█████╗  ",
        "                    ╚██╗ ██╔╝██║██║  ██║██╔══╝  ",
        "                     ╚████╔╝ ██║██████╔╝███████╗",
        "                      ╚═══╝  ╚═╝╚═════╝ ╚══════╝",
      }
      dashboard.section.buttons.val = {
        dashboard.button("Space Space", "󰍉  Show All Commands", "<cmd>Telescope builtin<CR>"),
        dashboard.button("Space f f", "󰱼  Find Files", "<cmd>Telescope find_files<CR>"),
        dashboard.button("Space f r", "󰒲  Open Recent", "<cmd>Telescope oldfiles<CR>"),
        dashboard.button("Space ,", "󰘵  Open Settings", "<cmd>edit ~/.config/vide/vide-nvim/init.lua<CR>"),
        dashboard.button("Ctrl + N", "󰈔  New File", "<cmd>enew<CR>"),
      }
      alpha.setup(dashboard.opts)
      local group = vim.api.nvim_create_augroup("VideDashboard", { clear = true })
      vim.api.nvim_create_autocmd({ "FileType", "BufEnter" }, {
        group = group,
        pattern = "alpha",
        callback = function()
          vim.cmd("setlocal nonumber norelativenumber")
        end,
      })
      end
  }
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
vim.cmd("colorscheme vscode")

-- Enable standard selection and input behavior (VSCode/Windows style)
vim.opt.selectmode = "mouse,key"
vim.opt.keymodel = "startsel,stopsel"

-- Clipboard Actions (Ctrl+C: Copy, Ctrl+V: Paste, Ctrl+X: Cut)
vim.keymap.set({"v", "s"}, "<C-c>", '"+y', { noremap = true, desc = "Copy Selection" })
vim.keymap.set({"v", "s"}, "<C-x>", '"+x', { noremap = true, desc = "Cut Selection" })

-- Paste in Insert mode and Command line / Visual / Select modes
vim.keymap.set("i", "<C-v>", '<C-r>+', { noremap = true, desc = "Paste Clipboard" })
vim.keymap.set({"v", "s"}, "<C-v>", '"+p', { noremap = true, desc = "Paste Clipboard" })
vim.keymap.set("c", "<C-v>", '<C-r>+', { noremap = true, desc = "Paste Clipboard" })

-- Undo / Redo (Ctrl+Z: Undo, Ctrl+Y: Redo)
vim.keymap.set({"i", "n", "v", "s"}, "<C-z>", function()
  vim.cmd("undo")
  vim.cmd("startinsert")
end, { silent = true, desc = "Undo" })

vim.keymap.set({"i", "n", "v", "s"}, "<C-y>", function()
  vim.cmd("redo")
  vim.cmd("startinsert")
end, { silent = true, desc = "Redo" })

-- Select All (Ctrl+A)
vim.keymap.set({"i", "n", "v", "s"}, "<C-a>", function()
  vim.cmd("normal! ggVG")
end, { silent = true, desc = "Select All" })

-- Auto-enter Insert Mode on all text buffers
vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter", "VimEnter" }, {
  callback = function()
    -- Only enter insert mode for regular files/editable buffers
    if vim.bo.buftype == "" and vim.bo.filetype ~= "neo-tree" and vim.bo.filetype ~= "markdown" then
      vim.cmd("startinsert")
    end
  end
})

-- Block escaping to Normal Mode inside Insert Mode to avoid mode confusion
vim.keymap.set("i", "<Esc>", "<Nop>")
vim.keymap.set("i", "<C-[>", "<Nop>")

-- Visual/Select mode: Esc clears selection and returns to Insert Mode
vim.keymap.set("v", "<Esc>", "<Esc>i", { silent = true })
vim.keymap.set("s", "<Esc>", "<Esc>i", { silent = true })

-- Standard Editor Hotkeys (Global/Insert/Visual/Select modes)
vim.keymap.set({ "n", "i", "v", "s" }, "<C-s>", function()
  vim.cmd("write")
  vim.cmd("startinsert")
end, { silent = true, desc = "Save File" })

vim.keymap.set({ "n", "i", "v", "s" }, "<C-q>", function()
  vim.cmd("qa!")
end, { silent = true, desc = "Force Quit Vide" })

vim.keymap.set({ "n", "i", "v", "s" }, "<C-w>", function()
  local bufs = vim.fn.getbufinfo({ buflisted = 1 })
  if #bufs > 1 then
    vim.cmd("bdelete")
  else
    vim.cmd("qa!")
  end
end, { silent = true, desc = "Close Tab/Buffer" })

-- Tab Navigation: Ctrl+Tab (Next Tab), Ctrl+Shift+Tab (Prev Tab)
vim.keymap.set({ "n", "i", "v", "s" }, "<C-Tab>", function()
  vim.cmd("BufferLineCycleNext")
end, { silent = true, desc = "Next Tab" })

vim.keymap.set({ "n", "i", "v", "s" }, "<C-S-Tab>", function()
  vim.cmd("BufferLineCyclePrev")
end, { silent = true, desc = "Previous Tab" })

-- Search Hotkey: Ctrl+F opens search
vim.keymap.set({ "i", "n", "v", "s" }, "<C-f>", "<Esc>/", { desc = "Search / Find" })

-- Tab Creation Hotkeys: Ctrl+T or Ctrl+N opens a new Neovim buffer
vim.keymap.set({ "n", "i", "v", "s" }, "<C-t>", function()
  vim.cmd("enew")
  vim.cmd("startinsert")
end, { silent = true, desc = "New Tab/Buffer" })

vim.keymap.set({ "n", "i", "v", "s" }, "<C-n>", function()
  vim.cmd("enew")
  vim.cmd("startinsert")
end, { silent = true, desc = "New Tab/Buffer" })

-- Telescope Search Shortcuts
vim.keymap.set("n", "<leader><leader>", "<cmd>Telescope builtin<CR>", { desc = "Show All Commands" })
vim.keymap.set("n", "<leader>ff", "<cmd>Telescope find_files<CR>", { desc = "Find Files" })
vim.keymap.set("n", "<leader>fr", "<cmd>Telescope oldfiles<CR>", { desc = "Open Recent" })
vim.keymap.set("n", "<leader>,", "<cmd>edit ~/.config/vide/vide-nvim/init.lua<CR>", { desc = "Open Settings" })

-- Toggle Bottom Terminal Panel (VSCode style, height 180px / 10 lines)
local function toggle_bottom_panel()
  local found = false
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].buftype == "terminal" or vim.bo[buf].filetype == "toggleterm" then
      vim.api.nvim_win_close(win, true)
      found = true
      break
    end
  end
  if not found then
    vim.cmd("botright split | resize 10 | terminal")
    vim.cmd("startinsert")
  end
end

vim.keymap.set({ "n", "v", "s" }, "<leader>j", toggle_bottom_panel, { desc = "Toggle Bottom Panel" })



-- Initialize layout state to IDE mode on boot
local layout_state_path = vim.fn.expand("~/.local/share/vide/layout.state")
local f = io.open(layout_state_path, "w")
if f then
  f:write("ide")
  f:close()
end

-- Toggle layout mode function (legacy, kept for potential Neovim-only usage)
local function toggle_mode()
  local current_mode = "ide"
  local rf = io.open(layout_state_path, "r")
  if rf then
    current_mode = rf:read("*l") or "ide"
    rf:close()
  end
  local next_mode = (current_mode == "ide") and "zen" or "ide"
  local wf = io.open(layout_state_path, "w")
  if wf then
    wf:write(next_mode)
    wf:close()
  end
end

vim.keymap.set("n", "<leader>mt", toggle_mode, { desc = "Toggle IDE/Zen Mode" })
vim.keymap.set("n", "<leader>e", function() vim.cmd("Neotree toggle") end, { desc = "Toggle File Tree" })

-- Onboarding Quickstart Interactive Guide
local function open_tutorial()
  -- Create a new buffer
  local buf = vim.api.nvim_create_buf(false, true)
  
  -- Tutorial content (beautiful markdown with ASCII art)
  local content = {
    "  __      __ ___  ___   ___  ___  __  __ ",
    "  \\ \\    / /|_ _||   \\ | __||_ _| \\ \\/ / ",
    "   \\ \\/\\/ /  | | | |) || _|  | |   >  <  ",
    "    \\_/\\_/  |___||___/ |___||___| /_/\\_\\ ",
    "                                         ",
    "  Welcome to Vide - The Terminal-Native IDE",
    "  =========================================",
    "",
    "  Vide is a terminal-native IDE built in Zig, using Neovim as its",
    "  core editing engine. Here is a quick reference to get started:",
    "",
    "  Core Mappings:",
    "  --------------",
    "   * <Space> e   : Toggle Left File Explorer",
    "   * Ctrl+Z      : Toggle IDE / Zen Mode",
    "   * Ctrl+T      : Toggle Terminal Panel",
    "   * <Space> ?   : Open this guide again",
    "",
    "  Navigation:",
    "  -----------",
    "   * Ctrl+E      : Focus / toggle the File Explorer",
    "   * <Esc>       : Return focus to the editor",
    "   * Alt+Arrows  : Resize panels",
    "",
    "  Files & Search:",
    "  ---------------",
    "   * Ctrl+F      : Find File (Telescope)",
    "   * Ctrl+N      : New File",
    "   * <Space>ff   : Telescope Find Files",
    "   * <Space>fg   : Telescope Live Grep",
    "",
    "  Change colorscheme with :colorscheme <name>",
    "  The editor theme updates dynamically.",
    "",
    "  [ Press 'q' or '<Esc>' to close this guide ]"
  }
  
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, content)
  vim.api.nvim_buf_set_option(buf, "filetype", "markdown")
  vim.api.nvim_buf_set_option(buf, "modifiable", false)
  vim.api.nvim_buf_set_option(buf, "buftype", "nofile")

  -- Calculate centered position
  local width = 64
  local height = 24
  local screen_width = vim.o.columns
  local screen_height = vim.o.lines
  local row = math.max(0, math.ceil((screen_height - height) / 2) - 1)
  local col = math.max(0, math.ceil((screen_width - width) / 2))

  local opts = {
    style = "minimal",
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    border = "rounded",
    title = " Vide Quickstart ",
    title_pos = "center"
  }

  local win = vim.api.nvim_open_win(buf, true, opts)
  
  -- Keymaps to close the window
  vim.api.nvim_buf_set_keymap(buf, "n", "q", ":close<CR>", { silent = true, noremap = true })
  vim.api.nvim_buf_set_keymap(buf, "n", "<Esc>", ":close<CR>", { silent = true, noremap = true })
end

vim.keymap.set("n", "<leader>?", open_tutorial, { desc = "Show Vide Quickstart Guide" })

-- First-boot check to show Quickstart automatically
vim.api.nvim_create_autocmd("VimEnter", {
  callback = function()
    vim.schedule(function()
      local onboarded_path = vim.fn.expand("~/.local/share/vide/onboarded")
      local f_onboard = io.open(onboarded_path, "r")
      if not f_onboard then
        open_tutorial()
        -- Mark as onboarded
        local f_write = io.open(onboarded_path, "w")
        if f_write then
          f_write:write("true")
          f_write:close()
        end
      else
        f_onboard:close()
      end
    end)
  end
})

-- ==============================================================================
-- Nmux42 Ported Keybinds & Custom Help Widget
-- ==============================================================================

-- Move lines up/down in Visual mode (Alt Up/Down in VSCode)
vim.keymap.set("v", "J", ":m '>+1<CR>gv=gv", { desc = "Move line down" })
vim.keymap.set("v", "K", ":m '<-2<CR>gv=gv", { desc = "Move line up" })

-- Join lines without moving cursor
vim.keymap.set("n", "J", "mzJ`z", { desc = "Join lines" })

-- Page Up/Down and keep cursor centered
vim.keymap.set("n", "<C-d>", "<C-d>zz", { desc = "Page down and center" })
vim.keymap.set("n", "<C-u>", "<C-u>zz", { desc = "Page up and center" })

-- Next/Prev search result and keep centered
vim.keymap.set("n", "n", "nzzzv", { desc = "Next search result" })
vim.keymap.set("n", "N", "Nzzzv", { desc = "Prev search result" })

-- Paste without overwriting clipboard
vim.keymap.set("x", "<leader>p", [["_dP]], { desc = "Paste without overwriting" })

-- Delete to black hole
vim.keymap.set({ "n", "v" }, "<leader>d", [["_d]], { desc = "Delete without copying" })

-- Disable Ex mode
vim.keymap.set("n", "Q", "<nop>", { desc = "Disable Ex mode" })

-- Substitute word under cursor
vim.keymap.set("n", "<leader>s", [[:s/\<<C-r><C-w>\>//gI<Left><Left><Left>]], { desc = "Substitute word under cursor" })

-- Make file executable
vim.keymap.set("n", "<leader>x", "<cmd>!chmod +x %<CR>", { silent = true, desc = "Make file executable" })

require("vide_help").setup()
