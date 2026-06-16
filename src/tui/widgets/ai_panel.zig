const std = @import("std");
const list_panel = @import("list_panel.zig");

pub const AiPanel = list_panel.ListPanel(&[_]list_panel.Item{
    .{ .label = "Antigravity CLI", .icon = " ", .cmd = "__CMD__:lua OpenAITerminal('agy')", .fallback_icon = "A " },
    .{ .label = "Claude Code", .icon = "󰚩 ", .cmd = "__CMD__:lua OpenAITerminal('claude')", .fallback_icon = "C " },
    .{ .label = "Codex", .icon = "󰧑 ", .cmd = "__CMD__:lua OpenAITerminal('codex')", .fallback_icon = "x " },
    .{ .label = "Gemini", .icon = "󰢚 ", .cmd = "__CMD__:lua OpenAITerminal('gemini')", .fallback_icon = "G " },
    .{ .label = "OpenCode", .icon = "󰊤 ", .cmd = "__CMD__:lua OpenAITerminal('opencode')", .fallback_icon = "O " },
    .{ .label = "Copilot", .icon = " ", .cmd = "__CMD__:lua OpenAITerminal('copilot')", .fallback_icon = "P " },
    
    // separator
    .{ .label = "────────────────", .icon = "  ", .cmd = "", .fallback_icon = "  " },
    
    // Mouseable AI context commands
    .{ .label = "Send Selection", .icon = "󰒅 ", .cmd = "__CMD__:lua _G.SendSelectionToAI()", .fallback_icon = "S " },
    .{ .label = "Send File Path", .icon = "󰈚 ", .cmd = "__CMD__:lua _G.SendFilePathToAI()", .fallback_icon = "P " },
    .{ .label = "Send File Content", .icon = "󰈙 ", .cmd = "__CMD__:lua _G.SendFileContentToAI()", .fallback_icon = "F " },
}, " AI ASSISTANTS");
