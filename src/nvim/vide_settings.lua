local M = {}

local themes = {
    "vscode", "tokyonight", "tokyonight-storm", "catppuccin", "gruvbox", "nord",
    "cyberdream", "rose-pine", "kanagawa", "nightfox"
}

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

return M
