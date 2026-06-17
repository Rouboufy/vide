const std = @import("std");
const renderer = @import("../renderer.zig");
const Color = renderer.Color;
const Rect = @import("../layout.zig").Rect;

pub const Item = struct {
    label: []const u8,
    icon: []const u8,
    cmd: []const u8,
    fallback_icon: []const u8 = "  ",
};

pub fn ListPanel(comptime items: []const Item, comptime header_text: []const u8) type {
    return struct {
        allocator: std.mem.Allocator,
        hover_idx: ?usize = null,

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator) Self {
            return Self{
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            _ = self;
        }

        pub fn draw(self: *Self, rend: *renderer.Renderer, rect: Rect, colors: anytype) void {
            // Draw background
            rend.drawRect(rect, " ", colors.fg_secondary, colors.bg_sidebar);

            // Header
            rend.drawText(rect.x, rect.y, header_text, colors.fg_primary, colors.bg_sidebar, true, false);

            var y: u16 = 2;
            for (items, 0..) |item, idx| {
                if (rect.y + y >= rect.y + rect.h) break;

                const is_sep = std.mem.eql(u8, item.cmd, "");
                const is_hover = (!is_sep and self.hover_idx != null and self.hover_idx.? == idx);
                const bg = if (is_hover) colors.bg_editor else colors.bg_sidebar;
                const fg = if (is_sep) colors.border_color else (if (is_hover) colors.fg_primary else colors.fg_secondary);

                if (!is_sep) {
                    var row_rect = rect;
                    row_rect.y = rect.y + y;
                    row_rect.h = 1;
                    rend.drawRect(row_rect, " ", fg, bg);
                    if (is_hover) {
                        rend.drawText(rect.x, rect.y + y, "▋", colors.fg_accent, bg, true, false);
                    }
                    const icon_str = if (colors.nerd_fonts) item.icon else item.fallback_icon;
                    rend.drawText(rect.x + 2, rect.y + y, icon_str, fg, bg, false, false);
                    rend.drawText(rect.x + 5, rect.y + y, item.label, fg, bg, false, false);
                } else {
                    rend.drawText(rect.x + 2, rect.y + y, item.label, fg, bg, false, false);
                }

                y += 1;
            }

            // Draw right border
            var by: u16 = 0;
            while (by < rect.h) : (by += 1) {
                var cell = renderer.Cell{
                    .fg = colors.border_color,
                    .bg = colors.bg_sidebar,
                };
                cell.setChar("│");
                rend.setCell(rect.x + rect.w - 1, rect.y + by, cell);
            }
        }

        pub fn handleMouse(self: *Self, mx: u16, my: u16, rect: Rect) ?[]const u8 {
            if (mx < rect.x or mx >= rect.x + rect.w) {
                self.hover_idx = null;
                return null;
            }
            if (my < rect.y + 2) {
                self.hover_idx = null;
                return null;
            }

            const idx = my - (rect.y + 2);
            if (idx < items.len) {
                if (std.mem.eql(u8, items[idx].cmd, "")) {
                    self.hover_idx = null;
                    return null;
                }
                self.hover_idx = idx;
                return items[idx].cmd;
            }

            self.hover_idx = null;
            return null;
        }

        pub fn handleKey(self: *Self, key: []const u8) ?[]const u8 {
            if (std.mem.eql(u8, key, "j") or std.mem.eql(u8, key, "<Down>")) {
                if (self.hover_idx == null) {
                    var start_idx: usize = 0;
                    while (start_idx < items.len and std.mem.eql(u8, items[start_idx].cmd, "")) : (start_idx += 1) {}
                    if (start_idx < items.len) self.hover_idx = start_idx;
                } else if (self.hover_idx.? < items.len - 1) {
                    var next_idx = self.hover_idx.? + 1;
                    while (next_idx < items.len and std.mem.eql(u8, items[next_idx].cmd, "")) : (next_idx += 1) {}
                    if (next_idx < items.len) {
                        self.hover_idx = next_idx;
                    }
                }
            } else if (std.mem.eql(u8, key, "k") or std.mem.eql(u8, key, "<Up>")) {
                if (self.hover_idx == null) {
                    var start_idx: usize = 0;
                    while (start_idx < items.len and std.mem.eql(u8, items[start_idx].cmd, "")) : (start_idx += 1) {}
                    if (start_idx < items.len) self.hover_idx = start_idx;
                } else if (self.hover_idx.? > 0) {
                    var prev_idx = self.hover_idx.? - 1;
                    while (prev_idx > 0 and std.mem.eql(u8, items[prev_idx].cmd, "")) : (prev_idx -= 1) {}
                    if (!std.mem.eql(u8, items[prev_idx].cmd, "")) {
                        self.hover_idx = prev_idx;
                    }
                }
            } else if (std.mem.eql(u8, key, "<Enter>") or std.mem.eql(u8, key, "o")) {
                if (self.hover_idx) |idx| {
                    if (!std.mem.eql(u8, items[idx].cmd, "")) {
                        return items[idx].cmd;
                    }
                }
            }
            return null;
        }
    };
}
