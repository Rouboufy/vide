const std = @import("std");
const renderer = @import("../renderer.zig");
const Color = renderer.Color;
const Rect = @import("../layout.zig").Rect;

pub const AiPanel = struct {
    allocator: std.mem.Allocator,
    hover_idx: ?usize = null,
    
    pub const Item = struct {
        label: []const u8,
        icon: []const u8,
        cmd: []const u8,
    };
    
    pub const items = [_]Item{
        .{ .label = "Claude Code", .icon = "󰚩 ", .cmd = "__CMD__:lua OpenAITerminal('claude')" },
        .{ .label = "Codex", .icon = "󰧑 ", .cmd = "__CMD__:lua OpenAITerminal('codex')" },
        .{ .label = "Gemini", .icon = "󰢚 ", .cmd = "__CMD__:lua OpenAITerminal('gemini')" },
        .{ .label = "OpenCode", .icon = "󰊤 ", .cmd = "__CMD__:lua OpenAITerminal('opencode')" },
        .{ .label = "Copilot", .icon = " ", .cmd = "__CMD__:lua OpenAITerminal('copilot')" },
    };

    pub fn init(allocator: std.mem.Allocator) AiPanel {
        return AiPanel{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *AiPanel) void {
        _ = self;
    }

    pub fn draw(self: *AiPanel, rend: *renderer.Renderer, rect: Rect, colors: anytype) void {
        // Draw background
        rend.drawRect(rect, " ", colors.fg_secondary, colors.bg_sidebar);

        // Header
        const header_text = " AI ASSISTANTS";
        rend.drawText(rect.x, rect.y, header_text, colors.fg_primary, colors.bg_sidebar, true, false);

        var y: u16 = 2;
        for (items, 0..) |item, idx| {
            if (rect.y + y >= rect.y + rect.h) break;

            const is_hover = (self.hover_idx != null and self.hover_idx.? == idx);
            const bg = if (is_hover) colors.bg_editor else colors.bg_sidebar;
            const fg = if (is_hover) colors.fg_primary else colors.fg_secondary;

            // Draw full row highlight if hovered
            var row_rect = rect;
            row_rect.y = rect.y + y;
            row_rect.h = 1;
            rend.drawRect(row_rect, " ", fg, bg);
            if (is_hover) {
                rend.drawText(rect.x, rect.y + y, "▋", colors.fg_accent, bg, true, false);
            }

            const icon_str = if (colors.nerd_fonts) item.icon else switch (idx) {
                0 => "C ",
                1 => "x ",
                2 => "G ",
                3 => "O ",
                4 => "P ",
                else => "  ",
            };
            rend.drawText(rect.x + 2, rect.y + y, icon_str, fg, bg, false, false);
            rend.drawText(rect.x + 5, rect.y + y, item.label, fg, bg, false, false);

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

    pub fn handleMouse(self: *AiPanel, mx: u16, my: u16, rect: Rect) ?[]const u8 {
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
            self.hover_idx = idx;
            return items[idx].cmd;
        }

        self.hover_idx = null;
        return null;
    }

    pub fn handleKey(self: *AiPanel, key: []const u8) ?[]const u8 {
        if (std.mem.eql(u8, key, "j") or std.mem.eql(u8, key, "<Down>")) {
            if (self.hover_idx == null) {
                self.hover_idx = 0;
            } else if (self.hover_idx.? < items.len - 1) {
                self.hover_idx = self.hover_idx.? + 1;
            }
        } else if (std.mem.eql(u8, key, "k") or std.mem.eql(u8, key, "<Up>")) {
            if (self.hover_idx != null and self.hover_idx.? > 0) {
                self.hover_idx = self.hover_idx.? - 1;
            }
        } else if (std.mem.eql(u8, key, "<Enter>")) {
            if (self.hover_idx != null and self.hover_idx.? < items.len) {
                return items[self.hover_idx.?].cmd;
            }
        }
        return null;
    }
};
