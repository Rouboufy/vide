const std = @import("std");

pub const Rect = struct {
    x: u16,
    y: u16,
    w: u16,
    h: u16,
};

pub const Layout = struct {
    total: Rect,
    activity_bar: Rect,
    file_tree: Rect,
    editor: Rect,
    tab_bar: Rect,
    status_bar: Rect,
    panel: ?Rect,

    pub fn compute(cols: u16, rows: u16, show_panel: bool, is_zen: bool, show_file_tree: bool, file_tree_width: u16, target_panel_h: u16) Layout {
        if (is_zen) {
            return .{
                .total = .{ .x = 0, .y = 0, .w = cols, .h = rows },
                .tab_bar = .{ .x = 0, .y = 0, .w = 0, .h = 0 },
                .activity_bar = .{ .x = 0, .y = 0, .w = 0, .h = 0 },
                .file_tree = .{ .x = 0, .y = 0, .w = 0, .h = 0 },
                .editor = .{ .x = 0, .y = 0, .w = cols, .h = rows },
                .panel = null,
                .status_bar = .{ .x = 0, .y = 0, .w = 0, .h = 0 },
            };
        }

        const actbar_w: u16 = 5;
        const tree_w: u16 = if (show_file_tree) file_tree_width else 0;
        
        const editor_w = if (cols > actbar_w + tree_w) cols - actbar_w - tree_w else cols;
        const panel_h: u16 = if (show_panel) target_panel_h else 0;

        return .{
            .total = .{ .x = 0, .y = 0, .w = cols, .h = rows },
            .tab_bar = .{ .x = actbar_w + tree_w, .y = 0, .w = editor_w, .h = 1 },
            .activity_bar = .{ .x = 0, .y = 0, .w = actbar_w, .h = if (rows > 1) rows - 1 else 0 },
            .file_tree = .{ .x = actbar_w, .y = 0, .w = tree_w, .h = if (rows > 1) rows - 1 else 0 },
            .editor = .{ 
                .x = actbar_w + tree_w, 
                .y = 1, 
                .w = @max(1, editor_w), 
                .h = if (rows > 2 + panel_h) @max(1, rows - 2 - panel_h) else 1 
            },
            .panel = if (show_panel and rows > 1 + panel_h) .{
                .x = actbar_w + tree_w,
                .y = rows - 1 - panel_h,
                .w = editor_w,
                .h = panel_h,
            } else null,
            .status_bar = .{ .x = 0, .y = if (rows > 1) rows - 1 else 0, .w = cols, .h = 1 },
        };
    }
};
