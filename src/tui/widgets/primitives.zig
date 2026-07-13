const std = @import("std");
const renderer = @import("../renderer.zig");
const Renderer = renderer.Renderer;
const Color = renderer.Color;
const Rect = @import("../layout.zig").Rect;

pub const ControlState = enum { normal, focused, hovered, disabled, selected };
pub const BorderStyle = enum { square, rounded };

pub const Palette = struct {
    fg: Color,
    bg: Color,
    accent_fg: Color,
    accent_bg: Color,
    muted_fg: Color,
};

pub const Button = struct {
    rect: Rect,
    state: ControlState = .normal,

    pub fn hit(self: Button, x: u16, y: u16) bool {
        return self.state != .disabled and containsRect(self.rect, x, y);
    }

    pub fn draw(self: Button, ren: *Renderer, label: []const u8, palette: Palette) void {
        if (self.rect.w == 0 or self.rect.h == 0) return;
        const active = self.state == .focused or self.state == .hovered or self.state == .selected;
        const fg = if (self.state == .disabled) palette.muted_fg else if (active) palette.accent_fg else palette.fg;
        const bg = if (active) palette.accent_bg else palette.bg;
        ren.drawRect(self.rect, " ", fg, bg);
        const padding: u16 = if (self.rect.w > 2) 1 else 0;
        ren.drawTextClipped(self.rect.x + padding, self.rect.y, self.rect.w -| padding *| 2, label, fg, bg, active, false);
    }
};

pub const ListViewport = struct {
    rect: Rect,
    item_count: usize,
    offset: usize,

    pub fn visibleCount(self: ListViewport) usize {
        return self.rect.h;
    }

    pub fn rowAt(self: ListViewport, x: u16, y: u16) ?usize {
        if (!containsRect(self.rect, x, y)) return null;
        const index = self.offset + (y - self.rect.y);
        return if (index < self.item_count) index else null;
    }

    pub fn scroll(self: *ListViewport, delta: i8) void {
        if (delta < 0) self.offset -|= @as(usize, @intCast(-delta)) else self.offset +|= @as(usize, @intCast(delta));
        self.offset = clampScroll(self.offset, self.item_count, self.visibleCount());
    }

    pub fn reveal(self: *ListViewport, selected: usize) void {
        self.offset = revealSelection(self.offset, selected, self.visibleCount(), self.item_count);
    }
};

pub const Modal = struct {
    rect: Rect,

    pub fn centered(screen_w: u16, screen_h: u16, max_w: u16, max_h: u16, margin: u16) Modal {
        const available_w = screen_w -| @min(screen_w, margin *| 2);
        const available_h = screen_h -| @min(screen_h, margin *| 2);
        const w = @min(max_w, available_w);
        const h = @min(max_h, available_h);
        return .{ .rect = .{ .x = (screen_w -| w) / 2, .y = (screen_h -| h) / 2, .w = w, .h = h } };
    }

    pub fn contains(self: Modal, x: u16, y: u16) bool {
        return containsRect(self.rect, x, y);
    }

    pub fn closeButton(self: Modal) Rect {
        return .{ .x = self.rect.x +| self.rect.w -| 4, .y = self.rect.y, .w = @min(3, self.rect.w), .h = @min(1, self.rect.h) };
    }

    pub fn content(self: Modal, inset: u16) Rect {
        const twice = inset *| 2;
        return .{ .x = self.rect.x +| inset, .y = self.rect.y +| inset, .w = self.rect.w -| twice, .h = self.rect.h -| twice };
    }
};

pub fn containsRect(rect: Rect, x: u16, y: u16) bool {
    return rect.w > 0 and rect.h > 0 and x >= rect.x and x < rect.x +| rect.w and y >= rect.y and y < rect.y +| rect.h;
}

pub fn usable(modal: Modal, min_w: u16, min_h: u16) bool {
    return modal.rect.w >= min_w and modal.rect.h >= min_h;
}

pub fn drawSizeWarning(ren: *Renderer, title: []const u8, fg: Color, bg: Color) void {
    const rect = Rect{ .x = 0, .y = 0, .w = ren.width, .h = ren.height };
    ren.drawRect(rect, " ", fg, bg);
    if (ren.height == 0 or ren.width == 0) return;
    const title_y = ren.height / 2 -| 1;
    ren.drawTextClipped(1, title_y, ren.width -| 2, title, fg, bg, true, false);
    if (title_y + 1 < ren.height) ren.drawTextClipped(1, title_y + 1, ren.width -| 2, "Terminal too small; resize or press Esc to close.", fg, bg, false, false);
}

pub fn clampScroll(offset: usize, item_count: usize, visible_count: usize) usize {
    if (item_count <= visible_count) return 0;
    return @min(offset, item_count - visible_count);
}

pub fn revealSelection(offset: usize, selected: usize, visible_count: usize, item_count: usize) usize {
    if (visible_count == 0 or item_count == 0) return 0;
    var next = clampScroll(offset, item_count, visible_count);
    if (selected < next) next = selected;
    if (selected >= next + visible_count) next = selected - visible_count + 1;
    return clampScroll(next, item_count, visible_count);
}

pub fn drawModalFrame(ren: *Renderer, modal: Modal, style: BorderStyle, fg: Color, bg: Color, border: Color, shadow: Color) void {
    const r = modal.rect;
    if (r.w == 0 or r.h == 0) return;
    ren.drawRect(.{ .x = r.x +| 1, .y = r.y +| 1, .w = @min(r.w, ren.width -| (r.x +| 1)), .h = @min(r.h, ren.height -| (r.y +| 1)) }, " ", shadow, shadow);
    ren.drawRect(r, " ", fg, bg);
    if (r.w < 2 or r.h < 2) return;
    const glyphs = if (style == .rounded) [_][]const u8{ "─", "│", "╭", "╮", "╰", "╯" } else [_][]const u8{ "─", "│", "┌", "┐", "└", "┘" };
    var x = r.x;
    while (x < r.x + r.w) : (x += 1) {
        ren.drawText(x, r.y, glyphs[0], border, bg, false, false);
        ren.drawText(x, r.y + r.h - 1, glyphs[0], border, bg, false, false);
    }
    var y = r.y;
    while (y < r.y + r.h) : (y += 1) {
        ren.drawText(r.x, y, glyphs[1], border, bg, false, false);
        ren.drawText(r.x + r.w - 1, y, glyphs[1], border, bg, false, false);
    }
    ren.drawText(r.x, r.y, glyphs[2], border, bg, false, false);
    ren.drawText(r.x + r.w - 1, r.y, glyphs[3], border, bg, false, false);
    ren.drawText(r.x, r.y + r.h - 1, glyphs[4], border, bg, false, false);
    ren.drawText(r.x + r.w - 1, r.y + r.h - 1, glyphs[5], border, bg, false, false);
}

test "modal drawing and hit testing share centered geometry" {
    const modal = Modal.centered(100, 40, 80, 24, 5);
    try std.testing.expectEqual(Rect{ .x = 10, .y = 8, .w = 80, .h = 24 }, modal.rect);
    try std.testing.expect(modal.contains(10, 8));
    try std.testing.expect(!modal.contains(90, 8));
    try std.testing.expect(containsRect(modal.closeButton(), 87, 8));
}

test "small screens and scroll state clamp safely" {
    const modal = Modal.centered(3, 2, 80, 24, 5);
    try std.testing.expectEqual(@as(u16, 0), modal.rect.w);
    try std.testing.expectEqual(@as(usize, 0), clampScroll(9, 2, 5));
    try std.testing.expectEqual(@as(usize, 6), clampScroll(9, 10, 4));
    try std.testing.expectEqual(@as(usize, 4), revealSelection(0, 6, 3, 10));
    try std.testing.expectEqual(@as(usize, 1), revealSelection(4, 1, 3, 10));
    try std.testing.expect(!usable(modal, 20, 10));
}

test "button state controls hit testing" {
    var button = Button{ .rect = .{ .x = 2, .y = 3, .w = 8, .h = 1 } };
    try std.testing.expect(button.hit(2, 3));
    try std.testing.expect(!button.hit(10, 3));
    button.state = .disabled;
    try std.testing.expect(!button.hit(2, 3));
}

test "list viewport shares scrolling and row hit geometry" {
    var list = ListViewport{ .rect = .{ .x = 5, .y = 4, .w = 20, .h = 3 }, .item_count = 8, .offset = 0 };
    try std.testing.expectEqual(@as(?usize, 1), list.rowAt(6, 5));
    list.scroll(2);
    try std.testing.expectEqual(@as(?usize, 3), list.rowAt(6, 5));
    list.reveal(7);
    try std.testing.expectEqual(@as(usize, 5), list.offset);
    try std.testing.expect(list.rowAt(30, 5) == null);
}
