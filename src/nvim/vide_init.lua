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
vim.opt.completeopt = { "menu", "menuone", "noselect" }

local set = vim.opt
set.relativenumber = true
set.number = true
set.tabstop = 4
set.shiftwidth = 4
set.autoindent = true
set.expandtab = true
set.ignorecase = true
set.smartcase = true
set.termguicolors = true
set.background = "dark"
set.signcolumn = "yes"
set.cursorline = true
set.colorcolumn = "80"
set.clipboard:append("unnamedplus")
set.backspace = "indent,eol,start"
set.splitbelow = true
set.splitright = true
set.iskeyword:append("-")
set.scrolloff = 8
set.swapfile = false
set.backup = false
local undodir = vim.fn.stdpath("data") .. "/undo"
vim.fn.mkdir(undodir, "p")
set.undodir = undodir
set.undofile = true
set.incsearch = true
set.updatetime = 50

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
            local colors = {
                "DiagnosticError",
                "DiagnosticWarning",
                "DiagnosticInfo",
                "DiagnosticHint",
                "Type",
                "String",
            }
            local header_elements = {}
            for i, line in ipairs(logo) do
                table.insert(header_elements, {
                    type = "text",
                    val = line,
                    opts = {
                        position = "center",
                        hl = colors[i],
                    }
                })
            end
            dashboard.config.layout[2] = header_elements[1]
            table.insert(dashboard.config.layout, 3, header_elements[2])
            table.insert(dashboard.config.layout, 4, header_elements[3])
            table.insert(dashboard.config.layout, 5, header_elements[4])
            table.insert(dashboard.config.layout, 6, header_elements[5])
            table.insert(dashboard.config.layout, 7, header_elements[6])

            local function format_key(key)
                if not key or key == "" then return "None" end
                if key:sub(1, 1) == "<" and key:sub(-1) == ">" then
                    local content = key:sub(2, -2)
                    local parts = {}
                    while true do
                        if content:sub(1, 2) == "C-" then
                            table.insert(parts, "Ctrl")
                            content = content:sub(3)
                        elseif content:sub(1, 2) == "M-" then
                            table.insert(parts, "Alt")
                            content = content:sub(3)
                        elseif content:sub(1, 2) == "S-" then
                            table.insert(parts, "Shift")
                            content = content:sub(3)
                        else
                            break
                        end
                    end
                    if #content == 1 then
                        content = content:upper()
                    elseif content:lower() == "esc" then
                        content = "Esc"
                    elseif content:lower() == "cr" or content:lower() == "enter" then
                        content = "Enter"
                    elseif content:lower() == "space" then
                        content = "Space"
                    end
                    table.insert(parts, content)
                    return table.concat(parts, "+")
                end
                return key
            end

            _G.vide_update_dashboard_keys = function()
                local path = vim.fn.expand("~/.local/share/vide/settings.json")
                local f = io.open(path, "r")
                local state = {}
                if f then
                    local content = f:read("*a")
                    f:close()
                    local ok, s = pcall(vim.fn.json_decode, content)
                    if ok and type(s) == "table" then
                        state = s
                    end
                end
                
                local kb = state.keybindings or {}
                local raw_new = kb.new_file or "<C-n>"
                local raw_find = kb.find_file or "<C-f>"
                local raw_quit = kb.quit or "<C-q>"
                local raw_recent = "<C-r>"
                local raw_explorer = "<C-e>"
                local raw_help = "<C-v>"

                local new_file_key = format_key(raw_new)
                local find_file_key = format_key(raw_find)
                local quit_key = format_key(raw_quit)
                local recent_key = format_key(raw_recent)
                local explorer_key = format_key(raw_explorer)
                local help_key = format_key(raw_help)
                
                local term = os.getenv("TERM") or ""
                local nerd_fonts = true
                if state.nerd_fonts ~= nil then
                    nerd_fonts = state.nerd_fonts
                end
                if term == "linux" then
                    nerd_fonts = false
                end
                vim.g.vide_nerd_fonts = nerd_fonts

                local new_file_icon = nerd_fonts and "󰝒 " or "+ "
                local find_file_icon = nerd_fonts and " " or "/ "
                local quit_icon = nerd_fonts and "󰈆 " or "x "

                local recent_icon = nerd_fonts and "󰄉 " or "r "
                local explorer_icon = nerd_fonts and "󰙅 " or "e "

                local function custom_button(key, display_text, cmd)
                    local btn = dashboard.button(key, "", cmd)
                    btn.val = display_text
                    btn.opts.position = "center"
                    btn.opts.hl = "Function"
                    btn.opts.shortcut = ""
                    return btn
                end

                local buttons = {
                    custom_button(raw_new, string.format("%s New File       %-6s", new_file_icon, new_file_key), "<cmd>enew<cr>"),
                    { type = "padding", val = 1 },
                    custom_button(raw_find, string.format("%s Find File      %-6s", find_file_icon, find_file_key), "<cmd>Telescope find_files<cr>"),
                    { type = "padding", val = 1 },
                    custom_button(raw_recent, string.format("%s Recent Files   %-6s", recent_icon, recent_key), "<cmd>Telescope oldfiles<cr>"),
                    { type = "padding", val = 1 },
                }

                local is_zen_mode = vim.g.vide_zen_mode
                if is_zen_mode == nil then
                    is_zen_mode = state.zen
                end

                if is_zen_mode then
                    table.insert(buttons, custom_button(raw_explorer, string.format("%s File Explorer  %-6s", explorer_icon, explorer_key), "<cmd>Ex<cr>"))
                    table.insert(buttons, { type = "padding", val = 1 })
                end

                table.insert(buttons, custom_button(raw_help, string.format("󰌌  Help Bindings  %-6s", help_key), "<cmd>HelpMenu<cr>"))
                table.insert(buttons, { type = "padding", val = 1 })
                table.insert(buttons, custom_button(raw_quit, string.format("%s Quit           %-6s", quit_icon, quit_key), "<cmd>qa<cr>"))

                dashboard.section.buttons.val = buttons
            end

            _G.vide_update_dashboard_keys()

            dashboard.opts.opts = {
                noautocmd = true,
            }
            require("alpha").setup(dashboard.config)
            local group = vim.api.nvim_create_augroup("VideDashboard", { clear = true })
            vim.api.nvim_create_autocmd({ "FileType" }, {
                group = group,
                pattern = "alpha",
                callback = function()
                    vim.cmd("setlocal nonumber norelativenumber") ;
                    vim.keymap.set("n", "<LeftRelease>", "<LeftRelease><cmd>lua pcall(function() require('alpha').press() end)<CR>", { buffer = true, silent = true })
                    if _G.vide_update_dashboard_keys then
                        _G.vide_update_dashboard_keys()
                        pcall(function() require("alpha").redraw() end)
                    end
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
        "hrsh7th/nvim-cmp",
        lazy = false,
        cond = not vim.g.vide_is_terminal,
        dependencies = {
            "hrsh7th/cmp-nvim-lsp",
            "hrsh7th/cmp-buffer",
            "hrsh7th/cmp-path",
            "L3MON4D3/LuaSnip",
            "saadparwaiz1/cmp_luasnip",
        },
        config = function()
            local cmp = require("cmp")
            local luasnip = require("luasnip")

            cmp.setup({
                enabled = function()
                    return vim.g.vide_autocomplete_enabled ~= false
                end,
                window = {
                    completion = cmp.config.window.bordered(),
                    documentation = false,
                },

                performance = {
                    max_view_entries = 12,
                },

                snippet = {
                    expand = function(args)
                        luasnip.lsp_expand(args.body)
                    end,
                },
                mapping = cmp.mapping.preset.insert({
                    ["<C-b>"] = cmp.mapping.scroll_docs(-4),
                    ["<C-f>"] = cmp.mapping.scroll_docs(4),
                    ["<C-Space>"] = cmp.mapping.complete(),
                    ["<C-e>"] = cmp.mapping.abort(),
                    ["<CR>"] = cmp.mapping.confirm({ select = true }),
                    ["<Tab>"] = cmp.mapping(function(fallback)
                        if cmp.visible() then
                            cmp.select_next_item()
                        elseif luasnip.expand_or_locally_jumpable() then
                            luasnip.expand_or_jump()
                        else
                            fallback()
                        end
                    end, { "i", "s" }),
                    ["<S-Tab>"] = cmp.mapping(function(fallback)
                        if cmp.visible() then
                            cmp.select_prev_item()
                        elseif luasnip.locally_jumpable(-1) then
                            luasnip.jump(-1)
                        else
                            fallback()
                        end
                    end, { "i", "s" }),
                }),
                sources = cmp.config.sources({
                    { name = "nvim_lsp", max_item_count = 15 },
                    { name = "luasnip", max_item_count = 5 },
                    { name = "path", max_item_count = 5 },
                }, {
                    { name = "buffer", max_item_count = 5 },
                }),
            })
        end,
    },
    {
        "neovim/nvim-lspconfig",
        lazy = false,
        cond = not vim.g.vide_is_terminal,
        dependencies = {
            "williamboman/mason.nvim",
            "williamboman/mason-lspconfig.nvim",
            "hrsh7th/cmp-nvim-lsp",
        },
        config = function()
            local mason_lspconfig = require("mason-lspconfig")
            local cmp_nvim_lsp = require("cmp_nvim_lsp")

            local mason_bin = vim.fn.expand("~/.local/share/nvim/mason/bin")
            if vim.fn.isdirectory(mason_bin) == 1 then
                vim.env.PATH = mason_bin .. ":" .. vim.env.PATH
            end

            pcall(function()
                require("mason").setup({
                    install_root_dir = vim.fn.expand("~/.local/share/nvim/mason"),
                })
            end)

            local capabilities = cmp_nvim_lsp.default_capabilities()

            -- Apply completion capabilities + broad root_markers to all servers.
            -- root_markers is how Neovim 0.12 native LSP determines the project root.
            vim.lsp.config('*', {
                capabilities = capabilities,
                root_markers = {
                    '.git',
                    'pyproject.toml', 'setup.py', 'setup.cfg', 'requirements.txt', 'Pipfile',
                    'Cargo.toml', 'Cargo.lock',
                    'package.json', 'yarn.lock', 'package-lock.json',
                    'compile_commands.json', 'compile_flags.txt',
                    '.clangd', '.clang-tidy',
                    'build.zig', 'build.zig.zon',
                    'pyrightconfig.json',
                    'Makefile', 'CMakeLists.txt',
                    'go.mod', 'go.sum',
                    '.hg', '.svn',
                },
            })

            -- Configure lua_ls settings natively
            vim.lsp.config("lua_ls", {
                settings = {
                    Lua = {
                        diagnostics = { globals = { "vim" } },
                    },
                },
            })

            mason_lspconfig.setup({
                ensure_installed = { "lua_ls", "zls" },
                automatic_enable = true,
            })

            -- Enable all installed servers immediately (mason-lspconfig's async refresh
            -- sometimes misses servers on first load)
            local function enable_all()
                local servers = mason_lspconfig.get_installed_servers()
                if #servers > 0 then
                    vim.lsp.enable(servers)
                    pcall(function()
                        for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
                            if vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].buflisted then
                                local ft = vim.bo[bufnr].filetype
                                if ft and ft ~= "" then
                                    vim.api.nvim_exec_autocmds("FileType", { buffer = bufnr })
                                end
                            end
                        end
                    end)
                end
            end

            enable_all()
            vim.defer_fn(enable_all, 500)

            -- Also re-enable on BufReadPost so newly installed servers attach
            vim.api.nvim_create_autocmd("BufReadPost", {
                once = false,
                callback = enable_all,
            })

            -- Trigger cmp-nvim-lsp registration on LspAttach, since Vide stays in insert mode
            vim.api.nvim_create_autocmd("LspAttach", {
                group = vim.api.nvim_create_augroup("VideCmpLspAttach", { clear = true }),
                callback = function()
                    local ok, cmp_nvim_lsp = pcall(require, "cmp_nvim_lsp")
                    if ok and cmp_nvim_lsp._on_insert_enter then
                        cmp_nvim_lsp._on_insert_enter()
                    end
                end,
            })
        end,

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
    local state = {}
    local path = vim.fn.expand("~/.local/share/vide/settings.json")
    local f = io.open(path, "r")
    if f then
        local content = f:read("*a")
        f:close()
        local ok, s = pcall(vim.fn.json_decode, content)
        if ok and type(s) == "table" then
            state = s
        end
    end
    local mode = "normal"
    if vim.g.vide_zen_mode then
        mode = "zen"
    elseif vim.g.vide_ide_mode then
        mode = "ide"
    end
    state.mode = mode
    state.zen = (mode == "zen")
    state.ide = (mode == "ide")
    state.clip = vim.o.clipboard:match("unnamedplus") ~= nil
    state.theme = vim.g.colors_name or "vscode"
    state.autocomplete = vim.g.vide_autocomplete_enabled ~= false
    state.autoindent = vim.o.autoindent
    state.nerd_fonts = vim.g.vide_nerd_fonts ~= false
    state.zen_handoff = vim.g.vide_zen_handoff == true
    local f_w = io.open(path, "w")
    if f_w then f_w:write(vim.fn.json_encode(state)); f_w:close() end
end

_G.vide_load_settings = function()
    local f = io.open(vim.fn.expand("~/.local/share/vide/settings.json"), "r")
    if f then
        local content = f:read("*a")
        f:close()
        local ok, state = pcall(vim.fn.json_decode, content)
        if ok and type(state) == "table" then
            local mode = "normal"
            if state.mode ~= nil then
                mode = state.mode
            elseif state.zen then
                mode = "zen"
            elseif state.ide then
                mode = "ide"
            end
            
            if mode == "zen" then
                vim.g.vide_zen_mode = true
                vim.g.vide_ide_mode = false
                vim.schedule(function() vim.rpcnotify(1, "vide_toggle_zen") end)
            elseif mode == "ide" then
                vim.g.vide_zen_mode = false
                vim.g.vide_ide_mode = true
                vim.schedule(_G.vide_enable_ide_mode)
            else
                vim.g.vide_zen_mode = false
                vim.g.vide_ide_mode = false
                vim.schedule(_G.vide_disable_ide_mode)
            end
            
            if state.clip ~= nil then
                vim.o.clipboard = state.clip and "unnamedplus" or ""
            end
            if state.autocomplete ~= nil then
                vim.g.vide_autocomplete_enabled = state.autocomplete
            else
                vim.g.vide_autocomplete_enabled = true
            end
            local term = os.getenv("TERM") or ""
            if state.nerd_fonts ~= nil then
                vim.g.vide_nerd_fonts = state.nerd_fonts
            else
                vim.g.vide_nerd_fonts = true
            end
            if term == "linux" then
                vim.g.vide_nerd_fonts = false
            end
            if state.autoindent ~= nil then
                vim.o.autoindent = state.autoindent
            else
                vim.o.autoindent = true
            end
            if state.zen_handoff ~= nil then
                vim.g.vide_zen_handoff = state.zen_handoff
            else
                vim.g.vide_zen_handoff = false
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
    if vim.g.vide_autocomplete_enabled == nil then vim.g.vide_autocomplete_enabled = true end
    if vim.g.vide_zen_handoff == nil then vim.g.vide_zen_handoff = false end
    local nerd_fonts = vim.g.vide_nerd_fonts ~= false
    local function get_toggle(is_on)
        if nerd_fonts then
            return is_on and " " or " "
        else
            return is_on and "[x] " or "[ ] "
        end
    end
    local current_theme = vim.g.colors_name or "vscode"
    
    local is_zen = vim.g.vide_zen_mode == true
    local is_ide = vim.g.vide_ide_mode == true
    local is_normal = not is_zen and not is_ide

    local width = 45
    local lines = { 
        string.rep(" ", width - 4) .. (nerd_fonts and "󰅖 " or "x "),
        "  General Settings",
        "  " .. get_toggle(is_zen) .. " Zen Mode                      [z]", 
        "  " .. get_toggle(is_ide) .. " IDE Mode                      [i]", 
        "  " .. get_toggle(is_normal) .. " Normal Mode                   [o]",
        "  " .. get_toggle(vim.g.vide_zen_handoff) .. " Zen Handoff (Native Nvim)     [h]",
        "  " .. get_toggle(vim.o.clipboard:match("unnamedplus")) .. " System Clipboard              [c]",
        "  " .. get_toggle(vim.g.vide_autocomplete_enabled) .. " Autocomplete                 [a]",
        "  " .. get_toggle(vim.o.autoindent) .. " Autoindent                   [n]",
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
    
    local function select_mode(mode)
        if mode == "zen" then
            vim.g.vide_zen_mode = true
            vim.g.vide_ide_mode = false
            _G.vide_disable_ide_mode()
            vim.rpcnotify(1, "vide_toggle_zen")
        elseif mode == "ide" then
            vim.g.vide_zen_mode = false
            vim.g.vide_ide_mode = true
            _G.vide_enable_ide_mode()
            vim.rpcnotify(1, "vide_toggle_ide")
        elseif mode == "normal" then
            vim.g.vide_zen_mode = false
            vim.g.vide_ide_mode = false
            _G.vide_disable_ide_mode()
            vim.rpcnotify(1, "vide_settings_changed")
        end
        if _G.vide_save_settings then _G.vide_save_settings() end
        pcall(vim.api.nvim_win_close, win, true)
        if mode ~= "zen" then
            require('vide_settings').open()
        end
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

    local function toggle_autocomplete()
        vim.g.vide_autocomplete_enabled = not vim.g.vide_autocomplete_enabled
        if _G.vide_save_settings then _G.vide_save_settings() end
        vim.rpcnotify(1, "vide_settings_changed")
        pcall(vim.api.nvim_win_close, win, true)
        require('vide_settings').open()
    end

    local function toggle_autoindent()
        vim.o.autoindent = not vim.o.autoindent
        if _G.vide_save_settings then _G.vide_save_settings() end
        vim.rpcnotify(1, "vide_settings_changed")
        pcall(vim.api.nvim_win_close, win, true)
        require('vide_settings').open()
    end
    
    local function toggle_zen_handoff()
        vim.g.vide_zen_handoff = not vim.g.vide_zen_handoff
        if _G.vide_save_settings then _G.vide_save_settings() end
        vim.rpcnotify(1, "vide_settings_changed")
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
        if line:match("󰅖") or line:match("x ") or line:match("%[x%]") or vim.api.nvim_win_get_cursor(win)[1] == 1 then pcall(vim.api.nvim_win_close, win, true)
        elseif line:match("Zen Mode") then select_mode("zen")
        elseif line:match("IDE Mode") then select_mode("ide")
        elseif line:match("Normal Mode") then select_mode("normal")
        elseif line:match("Zen Handoff") then toggle_zen_handoff()
        elseif line:match("System Clipboard") then toggle_clipboard()
        elseif line:match("Autocomplete") then toggle_autocomplete()
        elseif line:match("Autoindent") then toggle_autoindent()
        else set_theme() end
    end

    local function do_click()
        vim.cmd("stopinsert")
        handle_click()
    end

    vim.keymap.set({'n', 'v', 'i'}, 'z', function() select_mode("zen") end, { buffer = buf, silent = true })
    vim.keymap.set({'n', 'v', 'i'}, 'i', function() select_mode("ide") end, { buffer = buf, silent = true })
    vim.keymap.set({'n', 'v', 'i'}, 'o', function() select_mode("normal") end, { buffer = buf, silent = true })
    vim.keymap.set({'n', 'v', 'i'}, 'h', toggle_zen_handoff, { buffer = buf, silent = true })
    vim.keymap.set({'n', 'v', 'i'}, 'c', toggle_clipboard, { buffer = buf, silent = true })
    vim.keymap.set({'n', 'v', 'i'}, 'a', toggle_autocomplete, { buffer = buf, silent = true })
    vim.keymap.set({'n', 'v', 'i'}, 'n', toggle_autoindent, { buffer = buf, silent = true })
    vim.keymap.set({'n', 'v', 'i'}, 't', set_theme, { buffer = buf, silent = true })
    
    vim.keymap.set({'n', 'v', 'i'}, '<LeftMouse>', function()
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<LeftMouse>", true, false, true), "ntx", false)
        vim.schedule(do_click)
    end, { buffer = buf, silent = true })
    vim.keymap.set({'n', 'v', 'i'}, '<LeftRelease>', function()
        vim.schedule(do_click)
    end, { buffer = buf, silent = true })
    vim.keymap.set({'n', 'v', 'i'}, '<2-LeftMouse>', function()
        vim.schedule(do_click)
    end, { buffer = buf, silent = true })
    vim.keymap.set({'n', 'v', 'i'}, '<CR>', do_click, { buffer = buf, silent = true })
    vim.keymap.set({'n', 'v', 'i'}, 'q', function() pcall(vim.api.nvim_win_close, win, true) end, { buffer = buf, silent = true })
    vim.keymap.set({'n', 'v', 'i'}, '<Esc>', function() pcall(vim.api.nvim_win_close, win, true) end, { buffer = buf, silent = true })
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
    vim.api.nvim_set_hl(0, "NormalFloat", { fg = fg_primary, bg = bg_sidebar })
    vim.api.nvim_set_hl(0, "FloatBorder", { fg = border_color, bg = bg_sidebar })

    pcall(vim.rpcnotify, 1, "vide_theme_changed", {
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
if vim.fn.argc() == 0 and not vim.g.vide_is_terminal then
    vim.schedule(function()
        _G.vide_alpha_start()
    end)
end

-- Nmux42 Bindings
vim.keymap.set("n", "<leader>e", "<cmd>Neotree toggle<cr>", { desc = "Toggle Neo-tree" })
vim.keymap.set("v", "J", ":m '>+1<CR>gv=gv")
vim.keymap.set("v", "K", ":m '<-2<CR>gv=gv")
vim.keymap.set("n", "J", "mzJ`z")
vim.keymap.set("n", "<C-d>", "<C-d>zz")
vim.keymap.set("n", "<C-u>", "<C-u>zz")
vim.keymap.set("n", "n", "nzzzv")
vim.keymap.set("n", "N", "Nzzzv")
vim.keymap.set("x", "<leader>p", [["_dP]])
vim.keymap.set({ "n", "v" }, "<leader>d", [["_d]])
vim.keymap.set("i", "<C-c>", "<Esc>")
vim.keymap.set("n", "<C-j>", "<cmd>cnext<CR>zz")
vim.keymap.set("n", "<C-k>", "<cmd>cprev<CR>zz")
vim.keymap.set("n", "Q", "<nop>")
vim.keymap.set("n", "<leader>k", "<cmd>lnext<CR>zz")
vim.keymap.set("n", "<leader>j", "<cmd>lprev<CR>zz")
vim.keymap.set("n", "<leader>cc", "<cmd>!php-cs-fixer fix % --using-cache=no<cr>")
vim.keymap.set("n", "<leader>s", [[:s/\<<C-r><C-w>\>//gI<Left><Left><Left>]])
vim.keymap.set("n", "<leader>x", "<cmd>!chmod +x %<CR>", { silent = true })
vim.keymap.set('n', '<leader>y', '<Plug>OSCYankOperator')
vim.keymap.set('v', '<leader>y', '<Plug>OSCYankVisual')
vim.keymap.set("n", "<leader>u", vim.cmd.UndotreeToggle)
vim.keymap.set("n", "<leader>cl", ":cclose<CR>", { silent = true })
vim.keymap.set("n", "<leader>co", ":copen<CR>", { silent = true })
vim.keymap.set("n", "<leader>cn", ":cnext<CR>zz")
vim.keymap.set("n", "<leader>cp", ":cprev<CR>zz")
vim.keymap.set("n", "<leader>mm", "<cmd>make<CR>")
vim.keymap.set("n", "<leader><leader>", function() vim.cmd("so") end)

local function toggle_terminal(direction)
    local term_win = nil
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        local buf = vim.api.nvim_win_get_buf(win)
        if vim.bo[buf].buftype == "terminal" then
            term_win = win
            break
        end
    end
    if term_win then
        pcall(vim.api.nvim_win_close, term_win, true)
    else
        local term_buf = nil
        for _, buf in ipairs(vim.api.nvim_list_bufs()) do
            if vim.bo[buf].buftype == "terminal" then
                local job_id = vim.b[buf].terminal_job_id
                if job_id and vim.fn.jobwait({job_id}, 0)[1] == -2 then
                    local visible = false
                    for _, win in ipairs(vim.api.nvim_list_wins()) do
                        if vim.api.nvim_win_get_buf(win) == buf then
                            visible = true
                            break
                        end
                    end
                    if not visible then
                        term_buf = buf
                        break
                    end
                end
            end
        end
        if term_buf and vim.api.nvim_buf_is_valid(term_buf) then
            if direction == "bo" then vim.cmd("botright sbuf " .. term_buf) else vim.cmd("vert sbuf " .. term_buf) end
        else
            if direction == "bo" then vim.cmd("bo term") else vim.cmd("vert term") end
        end
        vim.cmd("startinsert")
    end
end
vim.keymap.set("n", "<leader>ot", function() toggle_terminal("bo") end, { desc = "Toggle bottom terminal" })
vim.keymap.set("n", "<leader>oT", function() toggle_terminal("vert") end, { desc = "Toggle vertical terminal" })
vim.keymap.set("n", "<leader>db", "<cmd>Alpha<CR>", { desc = "Go back to dashboard menu" })

vim.keymap.set("n", "<leader>th", "<cmd>lua require('vide_settings').open()<cr>")

pcall(dofile, vim.fn.expand("~/.config/nmux42/plugin/vim_bindings.lua"))

local telescope_timer = nil
local prev_mt_rect = vim.NIL
local prev_pr_rect = vim.NIL
local prev_widget_title = vim.NIL

local function rects_eq(r1, r2)
    if r1 == vim.NIL and r2 == vim.NIL then return true end
    if r1 == vim.NIL or r2 == vim.NIL then return false end
    if type(r1) ~= "table" or type(r2) ~= "table" then return r1 == r2 end
    return r1[1] == r2[1] and r1[2] == r2[2] and r1[3] == r2[3] and r1[4] == r2[4]
end

local function notify_telescope()
    pcall(function()
        local mt_top, mt_left, mt_bottom, mt_right = 9999, 9999, -1, -1
        local pr_top, pr_left, pr_bottom, pr_right = 9999, 9999, -1, -1
        local found_mt = false
        local found_pr = false
        local widget_title = nil

        local has_telescope, action_state = pcall(require, "telescope.actions.state")
        local picker = nil
        if has_telescope and action_state then
            for _, w in ipairs(vim.api.nvim_list_wins()) do
                if vim.api.nvim_win_is_valid(w) then
                    local buf = vim.api.nvim_win_get_buf(w)
                    if buf and vim.api.nvim_buf_is_valid(buf) then
                        local ok_ft, ft = pcall(function() return vim.bo[buf].filetype end)
                        if ok_ft and ft == "TelescopePrompt" then
                            local ok_picker, p = pcall(action_state.get_current_picker, buf)
                            if ok_picker and p then
                                picker = p
                                break
                            end
                        end
                    end
                end
            end
        end

        if picker then
            local prompt_win = picker.prompt_win
            local results_win = picker.results_win
            local preview_win = picker.preview_win or (picker.previewer and picker.previewer.state and picker.previewer.state.winid)

            for _, w in ipairs({ prompt_win, results_win }) do
                if w and vim.api.nvim_win_is_valid(w) then
                    local cfg = vim.api.nvim_win_get_config(w)
                    if cfg and cfg.relative ~= "" then
                        local r = math.floor(cfg.row or 0)
                        local c = math.floor(cfg.col or 0)
                        local h = math.floor(cfg.height or 0)
                        local w_w = math.floor(cfg.width or 0)
                        
                        if r < 0 then r = 0 end
                        if c < 0 then c = 0 end

                        found_mt = true
                        widget_title = " Telescope "
                        if r < mt_top then mt_top = r end
                        if c < mt_left then mt_left = c end
                        if r + h > mt_bottom then mt_bottom = r + h end
                        if c + w_w > mt_right then mt_right = c + w_w end
                    end
                end
            end

            if preview_win and vim.api.nvim_win_is_valid(preview_win) then
                local cfg = vim.api.nvim_win_get_config(preview_win)
                if cfg and cfg.relative ~= "" then
                    local r = math.floor(cfg.row or 0)
                    local c = math.floor(cfg.col or 0)
                    local h = math.floor(cfg.height or 0)
                    local w_w = math.floor(cfg.width or 0)
                    
                    if r < 0 then r = 0 end
                    if c < 0 then c = 0 end

                    found_pr = true
                    if r < pr_top then pr_top = r end
                    if c < pr_left then pr_left = c end
                    if r + h > pr_bottom then pr_bottom = r + h end
                    if c + w_w > pr_right then pr_right = c + w_w end
                end
            end
        end

        local mt_rect = found_mt and { mt_top, mt_left, mt_right - mt_left, mt_bottom - mt_top } or vim.NIL
        local pr_rect = found_pr and { pr_top, pr_left, pr_right - pr_left, pr_bottom - pr_top } or vim.NIL

        if not found_mt then
            for _, w in ipairs(vim.api.nvim_list_wins()) do
                if vim.api.nvim_win_is_valid(w) then
                    local buf = vim.api.nvim_win_get_buf(w)
                    if buf and vim.api.nvim_buf_is_valid(buf) then
                        local ok_ft, ft = pcall(function() return vim.bo[buf].filetype end)
                        if ok_ft and ft == "vimbindings" and (not vim.g.vide_zen_mode) then
                            local cfg = vim.api.nvim_win_get_config(w)
                            if cfg and cfg.relative ~= "" then
                                local r = math.floor(cfg.row or 0)
                                local c = math.floor(cfg.col or 0)
                                local h = math.floor(cfg.height or 0)
                                local w_w = math.floor(cfg.width or 0)
                                if r < 0 then r = 0 end
                                if c < 0 then c = 0 end
                                found_mt = true
                                widget_title = " Vide Help Reference "
                                mt_rect = { r, c, w_w, h }
                            end
                            break
                        end
                    end
                end
            end
        end

        if found_mt or found_pr then
            if not telescope_timer then
                telescope_timer = vim.uv.new_timer()
                telescope_timer:start(50, 50, vim.schedule_wrap(notify_telescope))
            end
            if not rects_eq(mt_rect, prev_mt_rect) or not rects_eq(pr_rect, prev_pr_rect) or widget_title ~= prev_widget_title then
                vim.rpcnotify(1, "vide_telescope_rect", mt_rect, pr_rect, widget_title)
                prev_mt_rect = mt_rect
                prev_pr_rect = pr_rect
                prev_widget_title = widget_title
            end
        else
            if telescope_timer then
                telescope_timer:stop()
                telescope_timer:close()
                telescope_timer = nil
            end
            if prev_mt_rect ~= vim.NIL or prev_pr_rect ~= vim.NIL then
                vim.rpcnotify(1, "vide_telescope_rect", vim.NIL, vim.NIL, vim.NIL)
                prev_mt_rect = vim.NIL
                prev_pr_rect = vim.NIL
                prev_widget_title = vim.NIL
            end
        end
    end)
end

local function notify_win_positions()
    local win_list = {}
    local cur_win = vim.api.nvim_get_current_win()
    for _, w in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_is_valid(w) then
            local cfg = vim.api.nvim_win_get_config(w)
            if cfg.relative == "" then
                local pos = vim.api.nvim_win_get_position(w) -- [row, col]
                local width = vim.api.nvim_win_get_width(w)
                local height = vim.api.nvim_win_get_height(w)
                table.insert(win_list, {
                    id = w,
                    row = pos[1],
                    col = pos[2],
                    width = width,
                    height = height,
                    active = (w == cur_win)
                })
            end
        end
    end
    vim.rpcnotify(1, "vide_win_positions", win_list)
end

vim.api.nvim_create_autocmd({"WinNew", "WinClosed", "WinEnter", "WinLeave"}, {
    callback = function()
        vim.schedule(notify_telescope)
        vim.schedule(notify_win_positions)
    end
})

-- Configure Telescope to use no borders so Vide can draw its own widget frame
pcall(function()
    require('telescope').setup({
        defaults = {
            border = false,
        }
    })
end)

_G.vide_wincmd = function(dir)
    local current_win = vim.api.nvim_get_current_win()
    vim.cmd("wincmd " .. dir)
    if vim.api.nvim_get_current_win() == current_win then
        vim.rpcnotify(1, "vide_boundary_hit", dir)
    end
end

vim.keymap.set({'i', 'n', 'v', 't'}, '<M-h>', function() _G.vide_wincmd('h') end, { silent = true })
vim.keymap.set({'i', 'n', 'v', 't'}, '<M-j>', function() _G.vide_wincmd('j') end, { silent = true })
vim.keymap.set({'i', 'n', 'v', 't'}, '<M-k>', function() _G.vide_wincmd('k') end, { silent = true })
vim.keymap.set({'i', 'n', 'v', 't'}, '<M-l>', function() _G.vide_wincmd('l') end, { silent = true })

vim.keymap.set({'i', 'n', 'v', 't'}, '<M-v>', function() vim.cmd("vsplit") end, { silent = true })
vim.keymap.set({'i', 'n', 'v', 't'}, '<C-\\>', function() vim.cmd("vsplit") end, { silent = true })
vim.keymap.set({'i', 'n', 'v', 't'}, '<M-s>', function() vim.cmd("split") end, { silent = true })
vim.keymap.set({'i', 'n', 'v', 't'}, '<M-c>', function() vim.cmd("close") end, { silent = true })
vim.keymap.set({'i', 'n', 'v', 't'}, '<M-o>', function() vim.cmd("wincmd w") end, { silent = true })

vim.schedule(function() pcall(notify_win_positions) end)

-- Native auto-pairs implementation
local autopairs = {
    ["("] = ")",
    ["["] = "]",
    ["{"] = "}",
    ['"'] = '"',
    ["'"] = "'",
    ['`'] = '`',
}

for open_char, close_char in pairs(autopairs) do
    vim.keymap.set('i', open_char, function()
        local line = vim.api.nvim_get_current_line()
        local col = vim.api.nvim_win_get_cursor(0)[2]
        local next_char = line:sub(col + 1, col + 1)
        if open_char == close_char and next_char == close_char then
            return "<Right>"
        else
            return open_char .. close_char .. "<Left>"
        end
    end, { expr = true, replace_keycodes = true })
end

local closers = { ')', ']', '}', '"', "'", '`' }
for _, close_char in ipairs(closers) do
    vim.keymap.set('i', close_char, function()
        local line = vim.api.nvim_get_current_line()
        local col = vim.api.nvim_win_get_cursor(0)[2]
        local next_char = line:sub(col + 1, col + 1)
        if next_char == close_char then
            return "<Right>"
        else
            return close_char
        end
    end, { expr = true, replace_keycodes = true })
end

vim.keymap.set('i', '<BS>', function()
    local line = vim.api.nvim_get_current_line()
    local col = vim.api.nvim_win_get_cursor(0)[2]
    local prev_char = line:sub(col, col)
    local next_char = line:sub(col + 1, col + 1)
    if autopairs[prev_char] == next_char then
        return "<BS><Del>"
    else
        return "<BS>"
    end
end, { expr = true, replace_keycodes = true })

-- --- VIDE HELP WIDGET --- --
local VIM_MOTIONS = {
    "  ╭──────────────────────────────────────────────────────────────╮",
    "  │               ⚡  VIM MOTIONS REFERENCE CARD                │",
    "  ╰──────────────────────────────────────────────────────────────╯",
    "",
    "  ── MODES ──────────────────────────────────────────────────────",
    "  i / I      Insert mode (before cursor / at line start)",
    "  a / A      Append mode (after cursor / at line end)",
    "  o / O      Open new line below / above and insert",
    "  v / V      Visual mode / Visual Line mode",
    "  <C-v>      Visual Block mode (column editing)",
    "  Esc        Return to Normal mode",
    "  R          Replace mode (overwrite text)",
    "",
    "  ── NAVIGATION ─────────────────────────────────────────────────",
    "  h j k l    Left / Down / Up / Right",
    "  w / W      Jump to next word start (word / WORD)",
    "  e / E      Jump to next word end   (word / WORD)",
    "  b / B      Jump back word start    (word / WORD)",
    "  0 / ^      Start of line / First non-blank char",
    "  $          End of line",
    "  gg / G     First line / Last line of file",
    "  {N}G       Jump to line N (e.g. 42G)",
    "  <C-d>      Scroll down half a page (cursor stays centered)",
    "  <C-u>      Scroll up half a page   (cursor stays centered)",
    "  <C-f>/<C-b>  Scroll full page down / up",
    "  %          Jump to matching bracket/paren/brace",
    "  *          Search forward for word under cursor",
    "  #          Search backward for word under cursor",
    "  n / N      Next / Previous search match",
    "  ''         Jump back to previous position",
    "  zz         Center screen on cursor",
    "  zt / zb    Scroll so cursor is at Top / Bottom",
    "",
    "  ── TEXT OBJECTS ────────────────────────────────────────────────",
    "  iw / aw    Inner word / A word (incl. surrounding space)",
    "  i\" / a\"    Inside quotes / Including quotes",
    "  i( / a(    Inside parens / Including parens",
    "  i{ / a{    Inside braces / Including braces",
    "  i[ / a[    Inside brackets / Including brackets",
    "  it / at    Inside tag / Including tag (HTML/XML)",
    "  ip / ap    Inner paragraph / A paragraph",
    "  is / as    Inner sentence / A sentence",
    "",
    "  ── OPERATORS (combine with motion or text object) ───────────────",
    "  d{motion}  Delete  (e.g. dw, d$, dip, d3j)",
    "  c{motion}  Change  (delete + insert mode)",
    "  y{motion}  Yank    (copy)",
    "  >{motion}  Indent right",
    "  <{motion}  Indent left",
    "  ={motion}  Auto-indent",
    "  gU{motion} Uppercase",
    "  gu{motion} Lowercase",
    "  g~{motion} Toggle case",
    "",
    "  ── EDITING SHORTCUTS ───────────────────────────────────────────",
    "  x / X      Delete char under cursor / before cursor",
    "  s / S      Substitute char / whole line",
    "  dd / D     Delete line / Delete to end of line",
    "  yy / Y     Yank line / Yank to end of line",
    "  p / P      Paste after cursor / before cursor",
    "  u          Undo",
    "  <C-r>      Redo",
    "  .          Repeat last change",
    "  J          Join line below to current line",
    "  r{char}    Replace single character with {char}",
    "  ~          Toggle case of character under cursor",
    "  >>  /  <<  Indent / Unindent current line",
    "  =G         Auto-indent from cursor to end of file",
    "",
    "  ── SEARCH & REPLACE ────────────────────────────────────────────",
    "  /pattern   Search forward  (n=next, N=prev)",
    "  ?pattern   Search backward",
    "  :%s/old/new/g      Replace all in file",
    "  :%s/old/new/gc     Replace all with confirmation",
    "  :s/old/new/g       Replace all in current line",
    "",
    "  ── MARKS & JUMPS ───────────────────────────────────────────────",
    "  m{a-z}     Set local mark  (m{A-Z} for global mark)",
    "  `{mark}    Jump to exact mark position",
    "  '{mark}    Jump to mark's line start",
    "  <C-o>      Jump to previous location in jump list",
    "  <C-i>      Jump to next location in jump list",
    "",
    "  ── MACROS ──────────────────────────────────────────────────────",
    "  q{a-z}     Start recording macro into register {a-z}",
    "  q          Stop recording macro",
    "  @{a-z}     Replay macro from register {a-z}",
    "  @@         Repeat last macro",
    "  {N}@{a-z}  Replay macro N times",
    "",
    "  ── WINDOWS & SPLITS ────────────────────────────────────────────",
    "  <C-w>s     Horizontal split",
    "  <C-w>v     Vertical split",
    "  <C-w>h/j/k/l   Move between splits",
    "  <C-w>q     Close current split",
    "  <C-w>=     Equalize all split sizes",
    "  <C-w>|     Maximize current split width",
    "  <C-w>_     Maximize current split height",
    "",
    "  ── COMMAND MODE ────────────────────────────────────────────────",
    "  :w         Save file",
    "  :q         Quit",
    "  :wq / :x   Save and quit",
    "  :q!        Quit without saving",
    "  :e {file}  Open file",
    "  :bn / :bp  Next / Previous buffer",
    "  :bd        Delete (close) buffer",
    "  :noh       Clear search highlight",
    "  :set nu    Toggle line numbers",
    "  :!{cmd}    Run shell command",
}

local VIDE_KEYS = {
    "  ╭──────────────────────────────────────────────────────────────╮",
    "  │                ⚙  VIDE CUSTOM KEYBINDINGS                   │",
    "  ╰──────────────────────────────────────────────────────────────╯",
    "  Leader key = <Space>",
    "",
    "  ── VIDE & WORKSPACE ────────────────────────────────────────────",
    "  <Space> e              Toggle Left File Tree (Yazi/Neo-tree)",
    "  <Space> m t            Toggle IDE / Zen Mode",
    "  <Space> j              Toggle Bottom Terminal Split",
    "  <Space> ?              Show Vide Quickstart Guide",
    "  <Space> ,              Open Settings",
    "",
    "  ── TTY & KEYBOARD NAVIGATION ───────────────────────────────────",
    "  Ctrl+E                 Toggle and focus File Tree",
    "  Ctrl+T                 Toggle and focus Terminal panel",
    "  <Esc>                  Return focus to Editor from panels",
    "  <Alt> h/j/k/l          Navigate splits & WezTerm panes seamlessly",
    "",
    "  ── TELESCOPE & SEARCH ──────────────────────────────────────────",
    "  <Space> <Space>        Telescope: Show All Commands",
    "  <Space> f f            Telescope: Find Files",
    "  <Space> f r            Telescope: Open Recent Files",
    "  Ctrl+F                 Telescope / Search",
    "",
    "  ── VSCODE-LIKE ESSENTIALS ──────────────────────────────────────",
    "  Ctrl+S                 Save file",
    "  Ctrl+Q                 Force quit Vide",
    "  Ctrl+W                 Close current Tab/Buffer",
    "  Ctrl+N / Ctrl+T        Open new Tab/Buffer",
    "  Ctrl+Tab               Next Tab",
    "  Ctrl+Shift+Tab         Previous Tab",
    "  Ctrl+Z                 Undo",
    "  Ctrl+Y                 Redo",
    "  Ctrl+C                 Copy selection to system clipboard",
    "  Ctrl+X                 Cut selection to system clipboard",
    "  Ctrl+V                 Paste from system clipboard",
    "  Ctrl+A                 Select all text",
    "",
    "  ── PORTED NMUX42 KEYS ──────────────────────────────────────────",
    "  J / K (Visual)         Move selected lines down / up",
    "  J (Normal)             Join lines without moving cursor",
    "  Ctrl+D / Ctrl+U        Scroll half page and keep cursor centered",
    "  n / N                  Next / Prev search match and keep centered",
    "  <Space> p (Visual)     Paste over selection without yanking it",
    "  <Space> d              Delete to black hole (without yanking)",
    "  <Space> s              Substitute word under cursor everywhere",
    "  <Space> x              Make current file executable (chmod +x)",
}

local state = { active_tab = "vim", buf = nil, win = nil }

local function open_bindings_window()
    local width  = math.min(74, vim.o.columns - 4)
    local height = math.floor(vim.o.lines * 0.85)
    local row    = math.floor((vim.o.lines - height) / 2)
    local col    = math.floor((vim.o.columns - width) / 2)

    local border_style = (not vim.g.vide_zen_mode) and "none" or "rounded"
    local title_str = border_style == "rounded" and "  Vide Help Reference " or nil

    local buf = vim.api.nvim_create_buf(false, true)
    local win = vim.api.nvim_open_win(buf, true, {
        relative    = "editor",
        width       = width,
        height      = height,
        row         = row,
        col         = col,
        style       = "minimal",
        border      = border_style,
        title       = title_str,
        title_pos   = border_style == "rounded" and "center" or nil,
    })
    return buf, win
end

local function render()
    if not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) then return end

    local tab_vim  = state.active_tab == "vim"
    local tab1_lbl = tab_vim and "●[1] Vim Motions " or "  [1] Vim Motions "
    local tab2_lbl = tab_vim and "  [2] Vide Keys  " or "●[2] Vide Keys  "

    local header = {
        "  " .. tab1_lbl .. " │ " .. tab2_lbl,
        "  ────────────────────────────────────────────────────────────",
        "",
    }

    local content = tab_vim and VIM_MOTIONS or VIDE_KEYS
    local lines = {}
    for _, l in ipairs(header) do table.insert(lines, l) end
    for _, l in ipairs(content) do table.insert(lines, l) end
    table.insert(lines, "")
    table.insert(lines, "  [Tab]/[1]/[2] Switch tab  │  [/] Search  │  [q/Esc] Close")

    vim.bo[state.buf].modifiable = true
    vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
    vim.bo[state.buf].modifiable = false
    vim.api.nvim_win_set_cursor(state.win, { 1, 0 })

    -- Highlight header
    local ns = vim.api.nvim_create_namespace("vimbindings_hl")
    vim.api.nvim_buf_clear_namespace(state.buf, ns, 0, -1)
    vim.api.nvim_buf_add_highlight(state.buf, ns, "Title",   0, 0, -1)
    vim.api.nvim_buf_add_highlight(state.buf, ns, "Comment", 1, 0, -1)
    -- Highlight section headers
    for i, l in ipairs(lines) do
        if l:match("^%s+──") then
            vim.api.nvim_buf_add_highlight(state.buf, ns, "Special", i - 1, 0, -1)
        elseif l:match("^%s+╭") or l:match("^%s+│") or l:match("^%s+╰") then
            vim.api.nvim_buf_add_highlight(state.buf, ns, "DiagnosticInfo", i - 1, 0, -1)
        elseif l:match("^%s+%[") and i == #lines then
            vim.api.nvim_buf_add_highlight(state.buf, ns, "Comment", i - 1, 0, -1)
        end
    end
end

_G.open_help_menu = function()
    -- Stop insert mode if we are in it
    if vim.fn.mode() == 'i' then vim.cmd("stopinsert") end

    state.buf, state.win = open_bindings_window()
    vim.bo[state.buf].buftype   = "nofile"
    vim.bo[state.buf].bufhidden = "wipe"
    vim.bo[state.buf].swapfile  = false
    vim.bo[state.buf].filetype = "vimbindings"

    local map = function(k, fn, desc)
        vim.keymap.set({"n", "i"}, k, fn, { buffer = state.buf, silent = true, desc = desc })
    end

    map("q",     function() pcall(vim.api.nvim_win_close, state.win, true) end, "Close")
    map("<Esc>", function() pcall(vim.api.nvim_win_close, state.win, true) end, "Close")
    map("<C-c>", function() pcall(vim.api.nvim_win_close, state.win, true) end, "Close")

    map("<Tab>", function()
        state.active_tab = state.active_tab == "vim" and "vide" or "vim"
        render()
    end, "Switch tab")
    map("1", function() state.active_tab = "vim";  render() end, "Vim Motions tab")
    map("2", function() state.active_tab = "vide"; render() end, "Vide Keys tab")

    -- Search within the buffer using built-in /
    map("/", function()
        vim.api.nvim_feedkeys("/", "n", false)
    end, "Search in buffer")

    render()
end



        -- Keymap to open
        -- We bind to normal and visual mode as well. But wait, since vide forces insert mode,
        -- if the user hits <space> in insert mode it types a space. So we should create a user command.
        vim.api.nvim_create_user_command("HelpMenu", _G.open_help_menu, {})
        vim.keymap.set({ "n", "i", "v" }, "<leader>hk", _G.open_help_menu, { desc = "Show Help Menu" })
    
function _G.OpenAITerminal(cmd)
    vim.cmd("botright vsplit")
    vim.cmd("wincmd L")
    vim.cmd("enew")
    local shell = vim.env.SHELL or "bash"
    vim.fn.termopen(shell)
    -- Send the command and enter
    vim.fn.chansend(vim.b.terminal_job_id, cmd .. "\n")
    vim.cmd("startinsert")
end
