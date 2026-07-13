vim.g.vide_is_terminal = true
vim.opt.termguicolors = true
vim.opt.laststatus = 0
vim.opt.showmode = false

local function notify_win_positions()
    local windows = {}
    local current = vim.api.nvim_get_current_win()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_is_valid(win) then
            local config = vim.api.nvim_win_get_config(win)
            if config.relative == "" then
                local pos = vim.api.nvim_win_get_position(win)
                local buf = vim.api.nvim_win_get_buf(win)
                local name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":t")
                table.insert(windows, {
                    id = win,
                    row = pos[1],
                    col = pos[2],
                    width = vim.api.nvim_win_get_width(win),
                    height = vim.api.nvim_win_get_height(win),
                    active = win == current,
                    name = name == "" and "Terminal" or name,
                })
            end
        end
    end
    vim.rpcnotify(1, "vide_win_positions", windows)
end

vim.api.nvim_create_autocmd({ "WinNew", "WinClosed", "WinEnter", "WinLeave", "TermOpen" }, {
    group = vim.api.nvim_create_augroup("VideTerminalFrontend", { clear = true }),
    callback = function() vim.schedule(notify_win_positions) end,
})
-- Let the synchronous nvim_exec_lua setup response reach Vide before sending
-- notifications that are consumed by the main event loop.
vim.defer_fn(notify_win_positions, 10)
