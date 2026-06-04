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
            }
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
            var layout = Layout{
                .total = .{ .x = 0, .y = 0, .w = cols, .h = rows },
                .tab_bar = .{ .x = 0, .y = 0, .w = 0, .h = 0 },
                .activity_bar = .{ .x = 0, .y = 0, .w = 0, .h = 0 },
                .file_tree = .{ .x = 0, .y = 0, .w = 0, .h = 0 },
                .editor = .{ .x = 0, .y = 0, .w = cols, .h = rows },
                .panel = null,
                .status_bar = .{ .x = 0, .y = 0, .w = 0, .h = 0 },
            };
            if (content_tree) |tree| {
                tree.compute(layout.editor, &layout.editor, &layout.panel);
            }
            return layout;
        }

        const actbar_w: u16 = 5;
        const tree_w: u16 = if (show_file_tree) file_tree_width else 0;
        const editor_w = if (cols > actbar_w + tree_w) cols - actbar_w - tree_w else 0;
        
        const content_rect = Rect{
            .x = actbar_w + tree_w,
            .y = 1,
            .w = @max(1, editor_w),
            .h = if (rows > 2) @max(1, rows - 2) else 1,
        };

        var layout = Layout{
            .total = .{ .x = 0, .y = 0, .w = cols, .h = rows },
            .tab_bar = .{ .x = actbar_w + tree_w, .y = 0, .w = editor_w, .h = 1 },
            .activity_bar = .{ .x = 0, .y = 0, .w = actbar_w, .h = if (rows > 1) rows - 1 else 0 },
            .file_tree = .{ .x = actbar_w, .y = 0, .w = tree_w, .h = if (rows > 1) rows - 1 else 0 },
            .editor = content_rect,
            .panel = null,
            .status_bar = .{ .x = 0, .y = if (rows > 1) rows - 1 else 0, .w = cols, .h = 1 },
        };

        if (content_tree) |tree| {
            tree.compute(content_rect, &layout.editor, &layout.panel);
        }

        return layout;
    }
};
