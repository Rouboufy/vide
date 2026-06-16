const std = @import("std");
const Renderer = @import("../renderer.zig").Renderer;
const Color = @import("../renderer.zig").Color;
const Cell = @import("../renderer.zig").Cell;
const Rect = @import("../layout.zig").Rect;

pub const ActivityBar = struct {
    active_idx: usize = 0,

    pub const Item = struct {
        icon: []const u8,
        label: []const u8,
    };

    pub const Theme = struct {
        bg_sidebar: Color,
        bg_accent: Color,
        fg_primary: Color,
        fg_secondary: Color,
        border_color: Color,
        nerd_fonts: bool = true,
    };

    pub const items = [_]Item{
        .{ .icon = " ", .label = "Explorer" },
        .{ .icon = " ", .label = "Search" },
        .{ .icon = " ", .label = "Source Control" },
        .{ .icon = "󰚩 ", .label = "AI Assistants" },
        .{ .icon = " ", .label = "Extensions" },
    };

    pub fn draw(self: *const ActivityBar, renderer: *Renderer, rect: Rect, theme: Theme) void {
        // Draw background panel
        renderer.drawRect(rect, " ", theme.fg_secondary, theme.bg_sidebar);

        // Draw right border
        var y: u16 = 0;
        while (y < rect.h) : (y += 1) {
            var cell = Cell{
                .fg = theme.border_color,
                .bg = theme.bg_sidebar,
            };
            cell.setChar("│");
            renderer.setCell(rect.x + rect.w - 1, rect.y + y, cell);
        }

        // Draw items
        for (items, 0..) |item, idx| {
            const icon_y = rect.y + @as(u16, @intCast(idx)) * 3 + 1;
            const is_active = (idx == self.active_idx);
            const fg = if (is_active) theme.fg_primary else theme.fg_secondary;
            const icon_str = if (theme.nerd_fonts) item.icon else switch (idx) {
                0 => "E ",
                1 => "S ",
                2 => "G ",
                3 => "A ",
                4 => "X ",
                else => "  ",
            };

            if (is_active) {
                // Vertical blue accent indicator on the left side
                renderer.drawText(rect.x, icon_y, "▋", theme.bg_accent, theme.bg_sidebar, true, false);
                renderer.drawText(rect.x + 2, icon_y, icon_str, fg, theme.bg_sidebar, true, false);
            } else {
                renderer.drawText(rect.x + 2, icon_y, icon_str, fg, theme.bg_sidebar, true, false);
            }
        }

        // Settings and profile icons at the bottom
        if (rect.h > 4) {
            const settings_y = rect.y + rect.h - 4;
            const profile_y = rect.y + rect.h - 2;
            const settings_icon = if (theme.nerd_fonts) " " else "* ";
            const profile_icon = if (theme.nerd_fonts) " " else "U ";
            renderer.drawText(rect.x + 2, settings_y, settings_icon, theme.fg_secondary, theme.bg_sidebar, true, false);
            renderer.drawText(rect.x + 2, profile_y, profile_icon, theme.fg_secondary, theme.bg_sidebar, true, false);
        }
    }

    pub fn handleMouse(self: *ActivityBar, mx: u16, my: u16, rect: Rect) ?usize {
        // If click is not inside the horizontal bounds of the activity bar, return null
        if (mx < rect.x or mx >= rect.x + rect.w) return null;

        for (items, 0..) |_, idx| {
            const start_y = rect.y + @as(u16, @intCast(idx)) * 3;
            if (my >= start_y and my < start_y + 3) {
                self.active_idx = idx;
                return idx;
            }
        }
        
        if (rect.h > 4) {
            const settings_y = rect.y + rect.h - 4;
            if (my >= settings_y - 1 and my <= settings_y + 1) {
                return 99; // 99 for settings
            }
        }
        return null;
    }
};
