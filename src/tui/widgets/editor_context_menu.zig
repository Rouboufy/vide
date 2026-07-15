const std = @import("std");
const input = @import("../input.zig");
const renderer = @import("../renderer.zig");
const primitives = @import("primitives.zig");

pub const EditorContextMenu = struct {
    is_open: bool = false,
    x: u16 = 0,
    y: u16 = 0,
    selected: usize = 0,
    hovered: ?usize = null,

    pub const width: u16 = 26;
    pub const height: u16 = items.len + 2;

    const Item = struct {
        label: []const u8,
        shortcut: []const u8 = "",
        action: ?[]const u8,
    };

    const items = [_]Item{
        .{ .label = "Undo", .shortcut = "Ctrl+Z", .action = "undo" },
        .{ .label = "Redo", .shortcut = "Ctrl+Y", .action = "redo" },
        .{ .label = "", .action = null },
        .{ .label = "Cut", .shortcut = "Ctrl+X", .action = "cut" },
        .{ .label = "Copy", .shortcut = "Ctrl+C", .action = "copy" },
        .{ .label = "Paste", .shortcut = "Ctrl+V", .action = "paste" },
        .{ .label = "", .action = null },
        .{ .label = "Select All", .shortcut = "Ctrl+A", .action = "select_all" },
        .{ .label = "", .action = null },
        .{ .label = "Explain with AI", .action = "ai_explain_selection" },
        .{ .label = "Fix / Improve with AI", .action = "ai_fix_selection" },
        .{ .label = "Add to AI Context", .action = "ai_add_context" },
    };

    pub const KeyResult = union(enum) { ignored, handled, action: []const u8 };

    pub fn open(self: *EditorContextMenu, x: u16, y: u16, screen_w: u16, screen_h: u16) void {
        self.x = @min(x, screen_w -| width);
        self.y = @min(y, screen_h -| height);
        self.selected = firstAction();
        self.hovered = null;
        self.is_open = true;
    }

    pub fn close(self: *EditorContextMenu) void {
        self.is_open = false;
        self.hovered = null;
    }

    fn firstAction() usize {
        for (items, 0..) |item, idx| if (item.action != null) return idx;
        return 0;
    }

    fn moveSelection(self: *EditorContextMenu, down: bool) void {
        var idx = self.selected;
        var remaining = items.len;
        while (remaining > 0) : (remaining -= 1) {
            idx = if (down) (idx + 1) % items.len else if (idx == 0) items.len - 1 else idx - 1;
            if (items[idx].action != null) {
                self.selected = idx;
                return;
            }
        }
    }

    fn itemAt(self: *const EditorContextMenu, x: u16, y: u16) ?usize {
        if (x <= self.x or x >= self.x + width - 1 or y <= self.y or y >= self.y + height - 1) return null;
        const idx: usize = y - self.y - 1;
        return if (idx < items.len) idx else null;
    }

    pub fn handleMouse(self: *EditorContextMenu, m: input.MouseEvent) ?[]const u8 {
        if (!self.is_open) return null;
        if (m.action == .move) {
            self.hovered = self.itemAt(m.col, m.row);
            if (self.hovered) |idx| {
                if (items[idx].action != null) self.selected = idx;
            }
            return null;
        }
        if (m.button == .wheel_up or m.button == .wheel_down) {
            self.moveSelection(m.button == .wheel_down);
            return null;
        }
        if (m.action != .press or m.button != .left) return null;
        const idx = self.itemAt(m.col, m.row) orelse {
            self.close();
            return null;
        };
        const action = items[idx].action orelse return null;
        self.close();
        return action;
    }

    pub fn handleKey(self: *EditorContextMenu, key: []const u8) KeyResult {
        if (!self.is_open) return .ignored;
        if (std.mem.eql(u8, key, "<Esc>")) {
            self.close();
            return .handled;
        }
        if (std.mem.eql(u8, key, "j") or std.mem.eql(u8, key, "<Down>")) {
            self.moveSelection(true);
            return .handled;
        }
        if (std.mem.eql(u8, key, "k") or std.mem.eql(u8, key, "<Up>")) {
            self.moveSelection(false);
            return .handled;
        }
        if (std.mem.eql(u8, key, "<Enter>") or std.mem.eql(u8, key, "<Space>")) {
            const action = items[self.selected].action orelse return .handled;
            self.close();
            return .{ .action = action };
        }
        return .handled;
    }

    pub fn draw(self: *const EditorContextMenu, ren: *renderer.Renderer, theme: anytype) void {
        if (!self.is_open) return;
        const modal = primitives.Modal{ .rect = .{ .x = self.x, .y = self.y, .w = width, .h = height } };
        primitives.drawModalFrame(ren, modal, .rounded, theme.fg_primary, theme.bg_sidebar, theme.border_color, theme.bg_editor);

        for (items, 0..) |item, idx| {
            const row_y = self.y + 1 + @as(u16, @intCast(idx));
            if (item.action == null) {
                var col: u16 = 1;
                while (col < width - 1) : (col += 1) ren.drawText(self.x + col, row_y, "─", theme.border_color, theme.bg_sidebar, false, false);
                continue;
            }
            const active = self.hovered == idx or (self.hovered == null and self.selected == idx);
            const bg = if (active) theme.bg_accent else theme.bg_sidebar;
            ren.drawRect(.{ .x = self.x + 1, .y = row_y, .w = width - 2, .h = 1 }, " ", theme.fg_primary, bg);
            if (active) ren.drawText(self.x + 1, row_y, "▋", theme.fg_accent, bg, true, false);
            ren.drawText(self.x + 3, row_y, item.label, theme.fg_primary, bg, active, false);
            if (item.shortcut.len > 0) {
                const shortcut_x = self.x + width - 2 - @as(u16, @intCast(item.shortcut.len));
                ren.drawText(shortcut_x, row_y, item.shortcut, theme.fg_secondary, bg, false, false);
            }
        }
    }
};

test "editor context menu clamps and skips separators" {
    var menu = EditorContextMenu{};
    menu.open(95, 38, 100, 40);
    try std.testing.expectEqual(@as(u16, 74), menu.x);
    try std.testing.expectEqual(@as(u16, 26), menu.y);
    try std.testing.expectEqual(@as(usize, 0), menu.selected);
    menu.moveSelection(true);
    try std.testing.expectEqual(@as(usize, 1), menu.selected);
    menu.moveSelection(true);
    try std.testing.expectEqual(@as(usize, 3), menu.selected);
}
