for i = 0, 15 do
    print("vim.api.nvim_buf_set_var(buf, 'terminal_color_' .. " .. i .. ", vim.g.terminal_color_" .. i .. ")")
end
