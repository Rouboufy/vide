const std = @import("std");
const log_console = @import("log_console.zig");

pub const DebugConsole = log_console.LogConsole(
    \\ local bufs = vim.api.nvim_list_bufs()
    \\ for _, b in ipairs(bufs) do
    \\     local name = vim.api.nvim_buf_get_name(b)
    \\     if name:match('%[dap%-repl%]') or name:match('dap%-terminal') then
    \\         return table.concat(vim.api.nvim_buf_get_lines(b, 0, -1, false), '\n')
    \\     end
    \\ end
    \\ return "No active DAP REPL or Terminal found. Start debugging with nvim-dap first."
    ,
    false,
);
