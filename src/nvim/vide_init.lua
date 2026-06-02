local lazypath = vim.fn.stdpath("data") .. "/vide/lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable",
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

vim.g.mapleader = " "
vim.opt.hidden = true
vim.opt.shortmess:append("A")

require("lazy").setup({
    {
        "goolord/alpha-nvim",
        lazy = false,
        priority = 1000,
        config = function()
            local dashboard = require("alpha.themes.dashboard")
            local logo = {
                "██╗   ██╗██╗██████╗ ███████╗",
                "██║   ██║██║██╔══██╗██╔════╝",
                "██║   ██║██║██║  ██║█████╗  ",
                "╚██╗ ██╔╝██║██║  ██║██╔══╝  ",
                " ╚████╔╝ ██║██████╔╝███████╗",
                "  ╚═══╝  ╚═╝╚═════╝ ╚══════╝",
            }
            dashboard.section.header.val = logo
            dashboard.section.header.opts.hl = "Statement"
            dashboard.section.buttons.val = {
                dashboard.button("n", "󰝒  New File", ":enew<CR>"),
                dashboard.button("f", "  Find File", "<cmd>Telescope find_files<CR>"),
                dashboard.button("q", "󰈆  Quit", ":qa<CR>"),
            }
            dashboard.opts.opts = {
                noautocmd = true,
            }
            require("alpha").setup(dashboard.config)
            local group = vim.api.nvim_create_augroup("VideDashboard", { clear = true })
            vim.api.nvim_create_autocmd({ "FileType", "BufEnter" }, {
                group = group,
                pattern = "alpha",
                callback = function()
                    vim.cmd("setlocal nonumber norelativenumber laststatus=0")
                end,
            })
        end
    },
    { "nvim-lua/plenary.nvim", lazy = true },
    {
        "nvim-telescope/telescope.nvim",
        cmd = "Telescope",
        keys = {
            { "<leader>ff", "<cmd>Telescope find_files<cr>" },
            { "<leader>fg", "<cmd>Telescope live_grep<cr>" },
            { "<leader>fb", "<cmd>Telescope buffers<cr>" },
            { "<leader>fh", "<cmd>Telescope help_tags<cr>" },
        }
    },
    {
        "nvim-treesitter/nvim-treesitter",
        build = function()
            local ts = require("nvim-treesitter")
            local site = vim.fn.stdpath("data") .. "/vide/site"
            ts.setup({ install_dir = site })
            ts.install({ "c", "lua", "vim", "vimdoc", "query", "zig", "markdown", "markdown_inline" }):wait()
        end,
        event = { "BufReadPost", "BufNewFile" },
        config = function()
            local ts = require("nvim-treesitter")
            local site = vim.fn.stdpath("data") .. "/vide/site"
            ts.setup({
                install_dir = site
            })
            vim.opt.rtp:prepend(site)
        end
    },
    {
        "williamboman/mason.nvim",
        cmd = "Mason",
        keys = { { "<leader>cm", "<cmd>Mason<cr>", desc = "Mason" } },
        config = true,
    },
    {
        "ThePrimeagen/harpoon",
        keys = {
            { "<leader>a", function() require("harpoon.mark").add_file() end },
            { "<C-e>", function() require("harpoon.ui").toggle_quick_menu() end },
            { "<C-h>", function() require("harpoon.ui").nav_file(1) end },
            { "<C-j>", function() require("harpoon.ui").nav_file(2) end },
            { "<C-k>", function() require("harpoon.ui").nav_file(3) end },
            { "<C-l>", function() require("harpoon.ui").nav_file(4) end },
        }
    },
    { "Mofiqul/vscode.nvim", lazy = false, priority = 1000 },
    { "folke/tokyonight.nvim", lazy = true },
    { "catppuccin/nvim", name = "catppuccin", lazy = true },
    { "ellisonleao/gruvbox.nvim", lazy = true },
    { "shaunsingh/nord.nvim", lazy = true },
    { "scottmckendry/cyberdream.nvim", lazy = true },
    { "rose-pine/neovim", name = "rose-pine", lazy = true },
    { "rebelot/kanagawa.nvim", lazy = true },
    { "EdenEast/nightfox.nvim", lazy = true },
}, {
    root = vim.fn.stdpath("data") .. "/vide/lazy",
    lockfile = vim.fn.stdpath("data") .. "/vide/lazy-lock.json",
    performance = {
        rtp = {
            reset = false, -- Prevent lazy.nvim from adding user's ~/.config/nvim back to RTP
        }
    }
})

_G.vide_enable_ide_mode = function()
    vim.g.vide_ide_mode = true
    vim.cmd("startinsert")
    pcall(vim.keymap.set, 'i', '<Esc>', '<nop>', { desc = "Disable Esc in IDE mode" })
    pcall(vim.keymap.set, 'n', '<Esc>', 'i', { desc = "Disable Esc in IDE mode" })
    pcall(vim.keymap.set, 'v', '<Esc>', '<C-c>i', { desc = "Disable Esc in IDE mode" })
    pcall(vim.keymap.set, {'i', 'n', 'v', 's'}, '<C-s>', function() vim.cmd("write") vim.cmd("startinsert") end, { desc = "Save File" })
    pcall(vim.keymap.set, {'i', 'n', 'v', 's'}, '<C-z>', function() pcall(vim.cmd, "undo") vim.cmd("startinsert") end, { desc = "Undo" })
    pcall(vim.keymap.set, {'i', 'n', 'v', 's'}, '<C-y>', function() pcall(vim.cmd, "redo") vim.cmd("startinsert") end, { desc = "Redo" })
    pcall(vim.keymap.set, 'v', '<BS>', '"_c', { desc = "Delete selection" })
    pcall(vim.keymap.set, 'v', '<Del>', '"_c', { desc = "Delete selection" })
    vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter" }, {
        group = vim.api.nvim_create_augroup("VideIdeMode", { clear = true }),
        callback = function()
            if vim.g.vide_ide_mode and vim.bo.modifiable and (vim.bo.buftype == "" or vim.bo.buftype == "acwrite") then
                vim.schedule(function() pcall(vim.cmd, "startinsert") end)
            end
        end,
    })
end

_G.vide_disable_ide_mode = function()
    vim.g.vide_ide_mode = false
    vim.cmd("stopinsert")
    pcall(vim.keymap.del, 'i', '<Esc>')
    pcall(vim.keymap.del, 'n', '<Esc>')
    pcall(vim.keymap.del, 'v', '<Esc>')
    pcall(vim.keymap.del, {'i', 'n', 'v', 's'}, '<C-s>')
    pcall(vim.keymap.del, {'i', 'n', 'v', 's'}, '<C-z>')
    pcall(vim.keymap.del, {'i', 'n', 'v', 's'}, '<C-y>')
    pcall(vim.keymap.del, 'v', '<BS>')
    pcall(vim.keymap.del, 'v', '<Del>')
    pcall(vim.api.nvim_del_augroup_by_name, "VideIdeMode")
end

_G.vide_save_settings = function()
    local state = {
        zen = vim.g.vide_zen_mode or false,
        ide = vim.g.vide_ide_mode or false,
        clip = vim.o.clipboard:match("unnamedplus") ~= nil,
        theme = vim.g.colors_name or "vscode"
    }
    local f = io.open(vim.fn.expand("~/.local/share/vide/settings.json"), "w")
    if f then f:write(vim.fn.json_encode(state)); f:close() end
end

_G.vide_load_settings = function()
    local f = io.open(vim.fn.expand("~/.local/share/vide/settings.json"), "r")
    if f then
        local content = f:read("*a")
        f:close()
        local ok, state = pcall(vim.fn.json_decode, content)
        if ok and type(state) == "table" then
            if state.zen then
                vim.g.vide_zen_mode = true
                vim.schedule(function() vim.rpcnotify(1, "vide_toggle_zen") end)
            end
            if state.ide then
                vim.schedule(_G.vide_enable_ide_mode)
            end
            if state.clip ~= nil then
                vim.o.clipboard = state.clip and "unnamedplus" or ""
            end
            if state.theme then
                vim.schedule(function() vim.cmd("colorscheme " .. state.theme) end)
            end
        end
    end
end

local M = {}
local themes = { "vscode", "tokyonight", "tokyonight-storm", "catppuccin", "gruvbox", "nord", "cyberdream", "rose-pine", "kanagawa", "nightfox" }
function M.open()
    if vim.g.vide_zen_mode == nil then vim.g.vide_zen_mode = false end
    if vim.g.vide_ide_mode == nil then vim.g.vide_ide_mode = false end
    local function get_toggle(is_on) return is_on and " " or " " end
    local current_theme = vim.g.colors_name or "vscode"
    
    local width = 45
    local lines = { 
        string.rep(" ", width - 4) .. "󰅖 ",
        "  General Settings",
        "  " .. get_toggle(vim.g.vide_zen_mode) .. " Zen Mode                      [z]", 
        "  " .. get_toggle(vim.g.vide_ide_mode) .. " IDE Mode                      [i]", 
        "  " .. get_toggle(vim.o.clipboard:match("unnamedplus")) .. " System Clipboard              [c]",
        "", 
        "  Themes",
    }
    for _, t in ipairs(themes) do 
        table.insert(lines, "  " .. get_toggle(t == current_theme) .. " " .. t .. string.rep(" ", 30 - #t) .. "[t]") 
    end

    local height = #lines + 2
    local buf = vim.api.nvim_create_buf(false, true)
    local win = vim.api.nvim_open_win(buf, true, {
        relative = 'editor', width = width, height = height,
        row = math.floor((vim.o.lines - height) / 2), col = math.floor((vim.o.columns - width) / 2),
        style = 'minimal', border = 'rounded', title = ' Vide Settings ', title_pos = 'center',
    })
    
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
    vim.cmd("stopinsert")
    
    local function toggle_zen()
        vim.g.vide_zen_mode = not vim.g.vide_zen_mode
        vim.rpcnotify(1, "vide_toggle_zen")
        if _G.vide_save_settings then _G.vide_save_settings() end
        pcall(vim.api.nvim_win_close, win, true)
        require('vide_settings').open()
    end
    
    local function toggle_ide()
        if vim.g.vide_ide_mode then
            _G.vide_disable_ide_mode()
            print("Beginner Mode: OFF (Normal Vim)")
        else
            _G.vide_enable_ide_mode()
            print("Beginner Mode: ON (VSCode Style)")
        end
        if _G.vide_save_settings then _G.vide_save_settings() end
        pcall(vim.api.nvim_win_close, win, true)
        require('vide_settings').open()
    end
    
    local function toggle_clipboard()
        if vim.o.clipboard:match("unnamedplus") then
            vim.o.clipboard = ""
            print("System Clipboard: OFF")
        else
            vim.o.clipboard = "unnamedplus"
            print("System Clipboard: ON")
        end
        if _G.vide_save_settings then _G.vide_save_settings() end
        pcall(vim.api.nvim_win_close, win, true)
        require('vide_settings').open()
    end
    
    local function set_theme()
        local theme = vim.api.nvim_get_current_line():match("([%w%-]+)%s+%[t%]")
        if theme then 
            vim.cmd("colorscheme " .. theme) 
            if _G.vide_save_settings then _G.vide_save_settings() end
            pcall(vim.api.nvim_win_close, win, true)
            require('vide_settings').open()
        end
    end

    local function handle_click()
        local line = vim.api.nvim_get_current_line()
        if line:match("󰅖") or line:match("%[x%]") then pcall(vim.api.nvim_win_close, win, true)
        elseif line:match("Zen Mode") then toggle_zen()
        elseif line:match("IDE Mode") then toggle_ide()
        elseif line:match("System Clipboard") then toggle_clipboard()
        else set_theme() end
    end

    vim.keymap.set('n', 'z', toggle_zen, { buffer = buf, silent = true })
    vim.keymap.set('n', 'i', toggle_ide, { buffer = buf, silent = true })
    vim.keymap.set('n', 'c', toggle_clipboard, { buffer = buf, silent = true })
    vim.keymap.set('n', 't', set_theme, { buffer = buf, silent = true })
    
    vim.keymap.set('n', '<LeftRelease>', handle_click, { buffer = buf, silent = true })
    vim.keymap.set('n', '<2-LeftMouse>', handle_click, { buffer = buf, silent = true })
    vim.keymap.set('n', '<CR>', handle_click, { buffer = buf, silent = true })
    vim.keymap.set('n', 'q', function() vim.api.nvim_win_close(win, true) end, { buffer = buf, silent = true })
    vim.keymap.set('n', '<Esc>', function() vim.api.nvim_win_close(win, true) end, { buffer = buf, silent = true })
end

function M.sync_theme()
    local function get_color(group, attr)
        local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = group, link = false })
        if ok and hl[attr] then return string.format("#%06x", hl[attr]) end
        return nil
    end
    local function adjust_color(hex, amount)
        if type(hex) ~= "string" or #hex ~= 7 then return hex end
        local r = tonumber(hex:sub(2, 3), 16) or 0
        local g = tonumber(hex:sub(4, 5), 16) or 0
        local b = tonumber(hex:sub(6, 7), 16) or 0
        r = math.max(0, math.min(255, r + amount))
        g = math.max(0, math.min(255, g + amount))
        b = math.max(0, math.min(255, b + amount))
        return string.format("#%02x%02x%02x", r, g, b)
    end
    local function get_contrast(hex, level)
        if type(hex) ~= "string" or #hex ~= 7 then return hex end
        local r = tonumber(hex:sub(2, 3), 16) or 0
        local g = tonumber(hex:sub(4, 5), 16) or 0
        local b = tonumber(hex:sub(6, 7), 16) or 0
        local brightness = (r * 299 + g * 587 + b * 114) / 1000
        return adjust_color(hex, brightness > 128 and -level or level)
    end

    local bg_editor = get_color("Normal", "bg") or "#1e1e1e"
    local fg_primary = get_color("Normal", "fg") or "#d4d4d4"
    local fg_secondary = get_color("Comment", "fg") or "#858585"
    local border_color = get_color("WinSeparator", "fg") or get_color("VertSplit", "fg") or "#3c3c3c"
    
    local bg_sidebar = get_color("NeoTreeNormal", "bg") or get_color("NvimTreeNormal", "bg") or get_color("NormalNC", "bg")
    if not bg_sidebar or bg_sidebar == bg_editor then
        bg_sidebar = get_contrast(bg_editor, 8)
    end
    
    local bg_tab_inactive = get_color("TabLine", "bg") or border_color
    if not bg_tab_inactive or bg_tab_inactive == bg_editor or bg_tab_inactive == border_color then
        bg_tab_inactive = get_contrast(bg_editor, 15)
    end
    
    local bg_accent = get_color("Function", "fg") or get_color("Statement", "fg") or "#007acc"
    
    local fg_statusbar = "#ffffff"
    do
        local r = tonumber(bg_accent:sub(2, 3), 16) or 0
        local g = tonumber(bg_accent:sub(4, 5), 16) or 0
        local b = tonumber(bg_accent:sub(6, 7), 16) or 0
        local brightness = (r * 299 + g * 587 + b * 114) / 1000
        if brightness > 128 then
            fg_statusbar = "#1e1e1e"
        end
    end

    -- Set terminal colors for the terminal panel so bash prompt ~ > is legible
    local bg_terminal = get_contrast(bg_editor, 12) -- Lighten background slightly for contrast
    if not bg_terminal then bg_terminal = bg_editor end
    
    vim.g.terminal_color_0  = get_color("Normal", "bg") or "#1e1e1e"
    vim.g.terminal_color_1  = get_color("Error", "fg") or "#f2495a"
    vim.g.terminal_color_2  = get_color("String", "fg") or "#42be65"
    vim.g.terminal_color_3  = get_color("WarningMsg", "fg") or "#ffcc00"
    vim.g.terminal_color_4  = get_color("Function", "fg") or "#007acc"
    vim.g.terminal_color_5  = get_color("Statement", "fg") or "#c678dd"
    vim.g.terminal_color_6  = get_color("Special", "fg") or "#56b6c2"
    vim.g.terminal_color_7  = get_color("Normal", "fg") or "#d4d4d4"
    vim.g.terminal_color_8  = get_color("Comment", "fg") or "#858585"
    vim.g.terminal_color_9  = get_color("Error", "fg") or "#f2495a"
    vim.g.terminal_color_10 = get_color("String", "fg") or "#42be65"
    vim.g.terminal_color_11 = get_color("WarningMsg", "fg") or "#ffcc00"
    vim.g.terminal_color_12 = get_color("Function", "fg") or "#007acc"
    vim.g.terminal_color_13 = get_color("Statement", "fg") or "#c678dd"
    vim.g.terminal_color_14 = get_color("Special", "fg") or "#56b6c2"
    vim.g.terminal_color_15 = "#ffffff"

    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.bo[buf].buftype == "terminal" then
            for i = 0, 15 do
                vim.api.nvim_buf_set_var(buf, "terminal_color_" .. i, vim.g["terminal_color_" .. i])
            end
            -- Force redraw in terminal buffer by briefly switching to it (optional but ensures update)
        end
    end

    local f = io.open("/home/blanglai/vide/vide_error.log", "a")
    if f then
        f:write("sync_theme bg_editor=" .. bg_editor .. " default_bg=" .. (get_color("Normal", "bg") or "nil") .. "\n")
        f:close()
    end
    vim.rpcnotify(1, "vide_theme_changed", {
        bg_editor = bg_editor, bg_sidebar = bg_sidebar, bg_tab_active = bg_editor,
        bg_tab_inactive = bg_tab_inactive, bg_statusbar = bg_accent, fg_statusbar = fg_statusbar, bg_accent = bg_accent,
        fg_primary = fg_primary, fg_secondary = fg_secondary, fg_accent = fg_primary, border_color = border_color,
        bg_terminal = bg_terminal,
    })
end

package.loaded["vide_settings"] = M

vim.api.nvim_create_autocmd("ColorScheme", {
    callback = function() require("vide_settings").sync_theme() end,
})
vim.schedule(function() pcall(function() require("vide_settings").sync_theme() end) end)

if _G.vide_load_settings then _G.vide_load_settings() end

-- Global function to restart dashboard when tabs close
_G.vide_alpha_start = function()
    vim.cmd("Alpha")
end

-- Force dashboard on initial empty load
if vim.fn.argc() == 0 then
    vim.schedule(function()
        _G.vide_alpha_start()
    end)
end

-- Nmux42 Bindings
vim.keymap.set("n", "<leader>e", "<cmd>Neotree toggle<cr>")
vim.keymap.set("v", "J", ":m '>+1<CR>gv=gv")
vim.keymap.set("v", "K", ":m '<-2<CR>gv=gv")
vim.keymap.set("n", "J", "mzJ`z")
vim.keymap.set("n", "<C-d>", "<C-d>zz")
vim.keymap.set("n", "<C-u>", "<C-u>zz")
vim.keymap.set("n", "n", "nzzzv")
vim.keymap.set("n", "N", "Nzzzv")
vim.keymap.set("x", "<leader>p", [["_dP]])
vim.keymap.set({ "n", "v" }, "<leader>d", [["_d]])
vim.keymap.set("n", "<leader>th", "<cmd>lua require('vide_settings').open()<cr>")

local telescope_timer = nil

local function notify_telescope()
    local mt_top, mt_left, mt_bottom, mt_right = 9999, 9999, -1, -1
    local pr_top, pr_left, pr_bottom, pr_right = 9999, 9999, -1, -1
    local found_mt = false
    local found_pr = false

    for _, w in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_is_valid(w) then
            local cfg = vim.api.nvim_win_get_config(w)
            if cfg.relative ~= "" then
                local buf = vim.api.nvim_win_get_buf(w)
                local ft = vim.bo[buf].filetype
                local r = math.floor(cfg.row or 0)
                local c = math.floor(cfg.col or 0)
                local h = math.floor(cfg.height or 0)
                local w_w = math.floor(cfg.width or 0)
                
                if r < 0 then r = 0 end
                if c < 0 then c = 0 end

                if ft == "TelescopePrompt" or ft == "TelescopeResults" then
                    found_mt = true
                    if r < mt_top then mt_top = r end
                    if c < mt_left then mt_left = c end
                    if r + h > mt_bottom then mt_bottom = r + h end
                    if c + w_w > mt_right then mt_right = c + w_w end
                elseif ft ~= "neo-tree" and ft ~= "mason" and ft ~= "lazy" then
                    found_pr = true
                    if r < pr_top then pr_top = r end
                    if c < pr_left then pr_left = c end
                    if r + h > pr_bottom then pr_bottom = r + h end
                    if c + w_w > pr_right then pr_right = c + w_w end
                end
            end
        end
    end

    local mt_rect = found_mt and { mt_top, mt_left, mt_right - mt_left, mt_bottom - mt_top } or vim.NIL
    local pr_rect = found_pr and { pr_top, pr_left, pr_right - pr_left, pr_bottom - pr_top } or vim.NIL

    if found_mt or found_pr then
        if not telescope_timer then
            telescope_timer = vim.uv.new_timer()
            telescope_timer:start(50, 50, vim.schedule_wrap(notify_telescope))
        end
        vim.rpcnotify(1, "vide_telescope_rect", mt_rect, pr_rect)
    else
        if telescope_timer then
            telescope_timer:stop()
            telescope_timer:close()
            telescope_timer = nil
        end
        vim.rpcnotify(1, "vide_telescope_rect", vim.NIL, vim.NIL)
    end
end

vim.api.nvim_create_autocmd({"WinNew", "WinClosed", "WinEnter", "WinLeave"}, {
    callback = function() vim.schedule(notify_telescope) end
})

-- Configure Telescope to use no borders so Vide can draw its own widget frame
pcall(function()
    require('telescope').setup({
        defaults = {
            border = false,
        }
    })
end)
