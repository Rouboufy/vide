const std = @import("std");
const renderer = @import("renderer.zig");
const Renderer = renderer.Renderer;
const Color = renderer.Color;
const Cell = renderer.Cell;
const Layout = @import("layout.zig").Layout;
const Rect = @import("layout.zig").Rect;
const theme = @import("theme.zig");
const app = @import("app.zig");
const App = app.App;

fn drawRect(ren: *Renderer, rect: Rect, char: []const u8, fg: Color, bg: Color) void {
    ren.drawRect(rect, char, fg, bg);
}

fn drawText(ren: *Renderer, x: u16, y: u16, text: []const u8, fg: Color, bg: Color, bold: bool, italic: bool) void {
    ren.drawText(x, y, text, fg, bg, bold, italic);
}

pub fn drawWorkspace(a: *App, layout: Layout) void {
    const t = &a.active_theme;
    drawRect(a.ren, layout.total, " ", t.fg_primary, t.bg_editor);

    var gy: u16 = 0;
    while (gy < layout.editor.h) : (gy += 1) {
        var gx: u16 = 0;
        while (gx < layout.editor.w) : (gx += 1) {
            if (gy < a.ui_state.grid.height and gx < a.ui_state.grid.width) {
                var cell = a.ui_state.grid.cells[@as(usize, gy) * @as(usize, a.ui_state.grid.width) + gx];
                
                if (std.meta.eql(cell.bg, a.ui_state.default_bg) or std.meta.activeTag(cell.bg) == .none) {
                    cell.bg = t.bg_editor;
                }
                if (std.meta.eql(cell.fg, a.ui_state.default_fg) or std.meta.activeTag(cell.fg) == .none) {
                    cell.fg = t.fg_primary;
                }
                a.ren.setCell(layout.editor.x + gx, layout.editor.y + gy, cell);
            } else {
                a.ren.setCell(layout.editor.x + gx, layout.editor.y + gy, Cell{
                    .char = [_]u8{ ' ', 0, 0, 0 }, .len = 1,
                    .fg = a.ui_state.default_fg, .bg = t.bg_editor,
                });
            }
        }
    }

    if (a.mode == .ide) {
        a.activity_bar.draw(a.ren, layout.activity_bar, .{
            .bg_sidebar = t.bg_sidebar, .bg_accent = t.bg_accent,
            .fg_primary = t.fg_primary, .fg_secondary = t.fg_secondary, .border_color = t.border_color,
        });
        if (a.show_file_tree) {
            if (a.activity_bar.active_idx == 0) {
                a.explorer.draw(a.ren, layout.file_tree, .{
                    .bg_sidebar = t.bg_sidebar, .bg_editor = t.bg_editor, .bg_accent = t.bg_accent,
                    .fg_primary = t.fg_primary, .fg_secondary = t.fg_secondary, .border_color = t.border_color, .fg_accent = t.fg_accent,
                });
            } else if (a.activity_bar.active_idx == 1) {
                a.search_panel.draw(a.ren, layout.file_tree, .{
                    .bg_sidebar = t.bg_sidebar, .bg_editor = t.bg_editor, .bg_accent = t.bg_accent,
                    .fg_primary = t.fg_primary, .fg_secondary = t.fg_secondary, .border_color = t.border_color, .fg_accent = t.fg_accent,
                });
            } else if (a.activity_bar.active_idx == 2) {
                a.git_panel.draw(a.ren, layout.file_tree, .{
                    .bg_sidebar = t.bg_sidebar, .bg_editor = t.bg_editor, .bg_accent = t.bg_accent,
                    .fg_primary = t.fg_primary, .fg_secondary = t.fg_secondary, .border_color = t.border_color, .fg_accent = t.fg_accent,
                });
            } else {
                drawRect(a.ren, layout.file_tree, " ", t.fg_primary, t.bg_sidebar);
            }
            var y: u16 = 0;
            while (y < layout.file_tree.h) : (y += 1) {
                var cell = Cell{ .fg = t.border_color, .bg = t.bg_sidebar };
                cell.setChar("│");
                a.ren.setCell(layout.file_tree.x + layout.file_tree.w - 1, layout.file_tree.y + y, cell);
            }
        }
        drawRect(a.ren, layout.tab_bar, " ", t.fg_secondary, t.bg_sidebar);
        var tx: u16 = layout.tab_bar.x;
        for (a.tabs.items, 0..) |tab, i| {
            const is_active = (i == a.active_tab);
            const tab_w: u16 = @as(u16, @intCast(tab.name.len)) + 8;
            const bg = if (is_active) t.bg_tab_active else t.bg_tab_inactive;
            const fg = if (is_active) t.fg_primary else t.fg_secondary;
            
            drawRect(a.ren, Rect{ .x = tx, .y = layout.tab_bar.y, .w = tab_w, .h = 1 }, " ", fg, bg);
            drawText(a.ren, tx + 2, layout.tab_bar.y, tab.name, fg, bg, is_active, false);
            const close_color = if (is_active) Color{ .rgb = .{ .r = 235, .g = 100, .b = 100 } } else t.fg_secondary;
            drawText(a.ren, tx + tab_w - 3, layout.tab_bar.y, "󰅖", close_color, bg, false, false);
            tx += tab_w;
        }
        // Draw + button for new tab
        drawText(a.ren, tx + 1, layout.tab_bar.y, "+", t.fg_secondary, t.bg_sidebar, true, false);
        
        // Draw Status Bar background
        drawRect(a.ren, layout.status_bar, " ", t.fg_primary, t.bg_statusbar);
        
        // Draw mode indicator
        drawText(a.ren, layout.status_bar.x + 1, layout.status_bar.y, " 󰚌  NORMAL ", t.fg_statusbar, t.bg_statusbar, true, false);
        
        // Draw Branch in Status Bar
        const branch_name = a.git_panel.current_branch orelse "main";
        var status_buf: [128]u8 = undefined;
        const branch_display = std.fmt.bufPrint(&status_buf, "  {s} ", .{branch_name}) catch "  main ";
        drawText(a.ren, layout.status_bar.x + 12, layout.status_bar.y, branch_display, t.fg_statusbar, t.bg_statusbar, true, false);
        
        // Draw File in Status Bar
        const file_x = 12 + @as(u16, @intCast(branch_display.len)) + 1;
        drawText(a.ren, layout.status_bar.x + file_x, layout.status_bar.y, "󰌆  main.zig", t.fg_statusbar, t.bg_statusbar, false, false);

        if (layout.panel) |panel| {
            // Draw terminal panel background
            drawRect(a.ren, panel, " ", t.fg_primary, t.bg_terminal);
            
            var px: u16 = 0;
            while (px < panel.w) : (px += 1) {
                var cell = Cell{ .fg = t.bg_accent, .bg = t.bg_sidebar };
                cell.setChar("━");
                a.ren.setCell(panel.x + px, panel.y, cell);
            }
            
            // Draw terminal header
            const term_header_fg = if (a.active_terminal_panel_idx == 0) t.bg_accent else t.fg_secondary;
            const debug_header_fg = if (a.active_terminal_panel_idx == 1) t.bg_accent else t.fg_secondary;
            const output_header_fg = if (a.active_terminal_panel_idx == 2) t.bg_accent else t.fg_secondary;
            
            drawText(a.ren, panel.x + 2, panel.y, " TERMINAL ", term_header_fg, t.bg_terminal, a.active_terminal_panel_idx == 0, false);
            drawText(a.ren, panel.x + 13, panel.y, " DEBUG CONSOLE ", debug_header_fg, t.bg_terminal, a.active_terminal_panel_idx == 1, false);
            drawText(a.ren, panel.x + 30, panel.y, " OUTPUT ", output_header_fg, t.bg_terminal, a.active_terminal_panel_idx == 2, false);

            if (panel.h > 1) {
                var py: u16 = 0;
                while (py < panel.h - 1) : (py += 1) {
                    px = 0;
                    while (px < panel.w) : (px += 1) {
                        if (a.active_terminal_panel_idx == 0 and py < a.ui_term.grid.height and px < a.ui_term.grid.width) {
                            var cell = a.ui_term.grid.cells[@as(usize, py) * @as(usize, a.ui_term.grid.width) + px];
                            if (std.meta.eql(cell.bg, a.ui_term.default_bg) or std.meta.activeTag(cell.bg) == .none) {
                                cell.bg = t.bg_terminal;
                            }
                            if (std.meta.eql(cell.fg, a.ui_term.default_fg) or std.meta.activeTag(cell.fg) == .none) {
                                cell.fg = t.fg_primary;
                            } else if (std.meta.activeTag(cell.fg) == .rgb) {
                                const r = cell.fg.rgb.r;
                                const g = cell.fg.rgb.g;
                                const b = cell.fg.rgb.b;
                                if (r < 80 and g < 80 and b > 50) {
                                    cell.fg.rgb.r = 86;
                                    cell.fg.rgb.g = 182;
                                    cell.fg.rgb.b = 194;
                                } else if (r < 60 and g < 60 and b < 60) {
                                    cell.fg.rgb.r = r +| 100;
                                    cell.fg.rgb.g = g +| 100;
                                    cell.fg.rgb.b = b +| 100;
                                }
                            }
                            a.ren.setCell(panel.x + px, panel.y + 1 + py, cell);
                        } else if (a.active_terminal_panel_idx == 1 or a.active_terminal_panel_idx == 2) {
                            // Delay rendering slightly, it will be done below
                        } else {
                            a.ren.setCell(panel.x + px, panel.y + 1 + py, Cell{
                                .char = [_]u8{ ' ', 0, 0, 0 }, .len = 1,
                                .fg = t.fg_primary, .bg = t.bg_terminal,
                            });
                        }
                    }
                }
            }
            
            if (a.active_terminal_panel_idx == 1) {
                const content_rect = Rect{ .x = panel.x, .y = panel.y + 1, .w = panel.w, .h = if (panel.h > 0) @max(1, panel.h - 1) else 1 };
                a.debug_console.draw(a.ren, content_rect, .{ .fg_primary = t.fg_primary, .fg_secondary = t.fg_secondary, .fg_accent = t.fg_accent, .bg_terminal = t.bg_terminal });
            } else if (a.active_terminal_panel_idx == 2) {
                const content_rect = Rect{ .x = panel.x, .y = panel.y + 1, .w = panel.w, .h = if (panel.h > 0) @max(1, panel.h - 1) else 1 };
                a.output_panel.draw(a.ren, content_rect, .{ .fg_primary = t.fg_primary, .fg_secondary = t.fg_secondary, .fg_accent = t.fg_accent, .bg_terminal = t.bg_terminal });
            }
            for (a.ui_state.telescope_rects, 0..) |rect_opt, idx| {
                if (rect_opt) |rect| {
                    const draw_x = layout.editor.x + rect.x;
                    const draw_y = layout.editor.y + rect.y;

                    const wx = if (draw_x > 0) draw_x - 1 else 0;
                    const wy = if (draw_y > 0) draw_y - 1 else 0;
                    const shadow_color = Color{ .rgb = .{ .r = 10, .g = 10, .b = 10 } };

                    // Draw shadow right
                    var sy: u16 = 1;
                    while (sy <= rect.h + 1) : (sy += 1) {
                        a.ren.drawText(wx + rect.w + 2, wy + sy, " ", t.fg_primary, shadow_color, false, false);
                        a.ren.drawText(wx + rect.w + 3, wy + sy, " ", t.fg_primary, shadow_color, false, false);
                    }
                    // Draw shadow bottom
                    var sx: u16 = 1;
                    while (sx <= rect.w + 3) : (sx += 1) {
                        a.ren.drawText(wx + sx, wy + rect.h + 2, " ", t.fg_primary, shadow_color, false, false);
                    }

                    // Top border
                    var bw: u16 = 0;
                    while (bw < rect.w + 2) : (bw += 1) {
                        a.ren.drawText(wx + bw, wy, " ", t.fg_primary, t.border_color, false, false);
                        a.ren.drawText(wx + bw, wy + rect.h + 1, " ", t.fg_primary, t.border_color, false, false);
                    }
                    // Side borders
                    var bh: u16 = 0;
                    while (bh < rect.h + 2) : (bh += 1) {
                        a.ren.drawText(wx, wy + bh, " ", t.fg_primary, t.border_color, false, false);
                        a.ren.drawText(wx + rect.w + 1, wy + bh, " ", t.fg_primary, t.border_color, false, false);
                    }

                    if (idx == 0) {
                        // Top bar text
                        a.ren.drawText(wx + 5, wy, " Telescope ", t.fg_primary, t.border_color, true, false);
                    } else {
                        // Top bar text
                        a.ren.drawText(wx + 5, wy, " Preview ", t.fg_primary, t.border_color, true, false);
                    }
                    
                    // Red cross (Top Right) on both
                    a.ren.drawText(wx + rect.w - 2, wy, " ✖ ", .{ .rgb = .{ .r = 255, .g = 80, .b = 80 } }, t.border_color, true, false);
                }
            }
        }
    }
    if (a.settings_widget.is_open) {
        a.settings_widget.draw(a.ren, a.ren.width, a.ren.height, .{
            .bg_editor = t.bg_editor, .bg_sidebar = t.bg_sidebar, .bg_accent = t.bg_accent,
            .fg_primary = t.fg_primary, .fg_secondary = t.fg_secondary, .border_color = t.border_color, .fg_accent = t.fg_accent,
        });
    }
    if (a.mason_widget.is_open) {
        a.mason_widget.draw(a.ren, a.ren.width, a.ren.height, .{
            .bg_editor = t.bg_editor, .bg_sidebar = t.bg_sidebar, .bg_accent = t.bg_accent,
            .fg_primary = t.fg_primary, .fg_secondary = t.fg_secondary, .border_color = t.border_color, .fg_accent = t.fg_accent,
            .fg_comment = t.fg_secondary,
        });
    }
    if (a.lazy_widget.is_open) {
        a.lazy_widget.draw(a.ren, a.ren.width, a.ren.height, .{
            .bg_editor = t.bg_editor, .bg_sidebar = t.bg_sidebar, .bg_accent = t.bg_accent,
            .fg_primary = t.fg_primary, .fg_secondary = t.fg_secondary, .border_color = t.border_color, .fg_accent = t.fg_accent,
            .fg_comment = t.fg_secondary,
        });
    }
    if (a.git_detailed_widget.is_open) {
        a.git_detailed_widget.draw(a.ren, a.ren.width, a.ren.height, .{
            .bg_editor = t.bg_editor, .bg_sidebar = t.bg_sidebar, .bg_accent = t.bg_accent,
            .fg_primary = t.fg_primary, .fg_secondary = t.fg_secondary, .border_color = t.border_color, .fg_accent = t.fg_accent,
            .fg_comment = t.fg_secondary,
        });
    }
}
