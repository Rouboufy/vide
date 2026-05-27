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

-- Setup lazy.nvim with placeholder empty list for initial load test
require("lazy").setup({}, {})
