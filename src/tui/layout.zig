const std = @import("std");

pub const Rect = struct {
    x: u16,
    y: u16,
    w: u16,
    h: u16,
};

pub const SplitDirection = enum { horizontal, vertical };

pub const ViewType = enum { editor, panel };

pub const SplitNode = struct {
    pub const Data = union(enum) {
        view: ViewType,
        split: struct {
            dir: SplitDirection,
            ratio: f32, // 0.0 to 1.0
            child1: *SplitNode,
            child2: *SplitNode,
        },
    };
    data: Data,

    pub fn compute(self: *SplitNode, rect: Rect, out_editor: *Rect, out_panel: *?Rect) void {
        switch (self.data) {
            .view => |v| {
                if (v == .editor) out_editor.* = rect;
                if (v == .panel) out_panel.* = rect;
            },
            .split => |s| {
                if (s.dir == .horizontal) {
                    const w1 = @max(1, @as(u16, @intFromFloat(@as(f32, @floatFromInt(rect.w)) * s.ratio)));
                    const w2 = if (rect.w > w1) @max(1, rect.w - w1) else 1;
                    const r1 = Rect{ .x = rect.x, .y = rect.y, .w = w1, .h = @max(1, rect.h) };
                    const r2 = Rect{ .x = rect.x + w1, .y = rect.y, .w = w2, .h = @max(1, rect.h) };
                    s.child1.compute(r1, out_editor, out_panel);
                    s.child2.compute(r2, out_editor, out_panel);
                } else {
                    const h1 = @max(1, @as(u16, @intFromFloat(@as(f32, @floatFromInt(rect.h)) * s.ratio)));
                    const h2 = if (rect.h > h1) @max(1, rect.h - h1) else 1;
                    const r1 = Rect{ .x = rect.x, .y = rect.y, .w = @max(1, rect.w), .h = h1 };
                    const r2 = Rect{ .x = rect.x, .y = rect.y + h1, .w = @max(1, rect.w), .h = h2 };
                    s.child1.compute(r1, out_editor, out_panel);
                    s.child2.compute(r2, out_editor, out_panel);
                }
            },
        }
    }
};

pub const Layout = struct {
    total: Rect,
    activity_bar: Rect,
    file_tree: Rect,
    editor: Rect,
    tab_bar: Rect,
    status_bar: Rect,
    panel: ?Rect,

    pub fn compute(cols: u16, rows: u16, is_zen: bool, show_file_tree: bool, file_tree_width: u16, content_tree: ?*SplitNode) Layout {
        if (is_zen) {
            const editor_h = if (rows > 1) rows - 1 else rows;
            return Layout{
                .total = .{ .x = 0, .y = 0, .w = cols, .h = rows },
                .tab_bar = .{ .x = 0, .y = 0, .w = 0, .h = 0 },
                .activity_bar = .{ .x = 0, .y = 0, .w = 0, .h = 0 },
                .file_tree = .{ .x = 0, .y = 0, .w = 0, .h = 0 },
                .editor = .{ .x = 0, .y = 0, .w = cols, .h = editor_h },
                .panel = null,
                .status_bar = .{ .x = 0, .y = editor_h, .w = cols, .h = if (rows > 1) 1 else 0 },
            };
        }

        const actbar_w: u16 = @min(5, cols);
        const after_activity = cols -| actbar_w;
        const tree_w: u16 = if (show_file_tree) @min(file_tree_width, after_activity) else 0;
        const editor_w = after_activity -| tree_w;
        const chrome_h: u16 = if (rows > 0) 1 else 0;

        const content_rect = Rect{
            .x = actbar_w + tree_w,
            .y = @min(1, rows),
            .w = editor_w,
            .h = rows -| 2,
        };

        var layout = Layout{
            .total = .{ .x = 0, .y = 0, .w = cols, .h = rows },
            .tab_bar = .{ .x = actbar_w + tree_w, .y = 0, .w = editor_w, .h = chrome_h },
            .activity_bar = .{ .x = 0, .y = 0, .w = actbar_w, .h = if (rows > 1) rows - 1 else 0 },
            .file_tree = .{ .x = actbar_w, .y = 0, .w = tree_w, .h = if (rows > 1) rows - 1 else 0 },
            .editor = content_rect,
            .panel = null,
            .status_bar = .{ .x = 0, .y = if (rows > 1) rows - 1 else 0, .w = cols, .h = chrome_h },
        };

        if (content_tree) |tree| if (content_rect.w > 0 and content_rect.h > 0) {
            tree.compute(content_rect, &layout.editor, &layout.panel);
        };

        return layout;
    }
};

test "zen mode reserves only the mode indicator row" {
    const layout = Layout.compute(120, 40, true, true, 30, null);
    try std.testing.expectEqual(Rect{ .x = 0, .y = 0, .w = 120, .h = 39 }, layout.editor);
    try std.testing.expectEqual(@as(u16, 1), layout.status_bar.h);
    try std.testing.expect(layout.panel == null);
}

test "normal layouts reserve Vide chrome" {
    const layout = Layout.compute(120, 40, false, true, 30, null);
    try std.testing.expectEqual(@as(u16, 5), layout.activity_bar.w);
    try std.testing.expectEqual(@as(u16, 30), layout.file_tree.w);
    try std.testing.expectEqual(@as(u16, 1), layout.tab_bar.h);
    try std.testing.expectEqual(@as(u16, 1), layout.status_bar.h);
}

test "tiny layouts never extend beyond the terminal" {
    for (0..8) |cols_raw| {
        for (0..5) |rows_raw| {
            const cols: u16 = @intCast(cols_raw);
            const rows: u16 = @intCast(rows_raw);
            const layout = Layout.compute(cols, rows, false, true, 30, null);
            for ([_]Rect{ layout.total, layout.activity_bar, layout.file_tree, layout.editor, layout.tab_bar, layout.status_bar }) |rect| {
                try std.testing.expect(rect.x <= cols);
                try std.testing.expect(rect.y <= rows);
                try std.testing.expect(rect.x +| rect.w <= cols);
                try std.testing.expect(rect.y +| rect.h <= rows);
            }
        }
    }
}

test "very large layouts preserve requested sidebars without overflow" {
    const layout = Layout.compute(500, 200, false, true, 80, null);
    try std.testing.expectEqual(@as(u16, 80), layout.file_tree.w);
    try std.testing.expectEqual(@as(u16, 415), layout.editor.w);
    try std.testing.expectEqual(@as(u16, 198), layout.editor.h);
}
