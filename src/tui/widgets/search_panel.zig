const std = @import("std");
const list_panel = @import("list_panel.zig");

pub const SearchPanel = list_panel.ListPanel(&[_]list_panel.Item{
    .{ .label = "Find Files", .icon = " ", .cmd = "__CMD__:Telescope find_files", .fallback_icon = "f " },
    .{ .label = "Live Grep", .icon = "󰱽 ", .cmd = "__CMD__:Telescope live_grep", .fallback_icon = "g " },
    .{ .label = "Buffers", .icon = "󰈔 ", .cmd = "__CMD__:Telescope buffers", .fallback_icon = "b " },
    .{ .label = "Help Tags", .icon = "󰋖 ", .cmd = "__CMD__:Telescope help_tags", .fallback_icon = "h " },
    .{ .label = "Git Commits", .icon = "󰜘 ", .cmd = "__CMD__:Telescope git_commits", .fallback_icon = "c " },
    .{ .label = "Git Status", .icon = "󰊢 ", .cmd = "__CMD__:Telescope git_status", .fallback_icon = "s " },
}, " SEARCH (TELESCOPE)");
