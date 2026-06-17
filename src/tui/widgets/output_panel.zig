const std = @import("std");
const log_console = @import("log_console.zig");

pub const OutputPanel = log_console.LogConsole(
    "return vim.api.nvim_exec('messages', true)",
    true,
);
