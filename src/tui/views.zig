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

fn getHorizontalSeparator(vert: []const u8) []const u8 {
    if (std.mem.eql(u8, vert, "│")) return "─";
    if (std.mem.eql(u8, vert, "▏")) return "▔";
    if (std.mem.eql(u8, vert, "▍")) return "▀";
    if (std.mem.eql(u8, vert, "")) return "━";
    if (std.mem.eql(u8, vert, "┃")) return "━";
    if (std.mem.eql(u8, vert, "║")) return "═";
    if (std.mem.eql(u8, vert, "┊")) return "┄";
    return " ";
}

pub fn drawWorkspace(a: *App, layout: Layout) void {
    const t = &a.active_theme;
    drawRect(a.ren, layout.total, " ", t.fg_primary, t.bg_editor);

    // Draw grid 1 (global grid) first for cmdline, messages, and global statusline
    if (a.ui_state.grid.width > 0 and a.ui_state.grid.height > 0) {
        var gy: u16 = 0;
        while (gy < a.ui_state.grid.height) : (gy += 1) {
            const sy_i = @as(i32, @intCast(layout.editor.y)) + @as(i32, @intCast(gy));
            if (sy_i < 0 or sy_i >= @as(i32, @intCast(layout.editor.y + layout.editor.h))) continue;
            const sy = @as(u16, @intCast(sy_i));
            var gx: u16 = 0;
            while (gx < a.ui_state.grid.width) : (gx += 1) {
                const sx_i = @as(i32, @intCast(layout.editor.x)) + @as(i32, @intCast(gx));
                if (sx_i < 0 or sx_i >= @as(i32, @intCast(layout.editor.x + layout.editor.w))) continue;
                const sx = @as(u16, @intCast(sx_i));
                var cell = a.ui_state.grid.cells[@as(usize, gy) * @as(usize, a.ui_state.grid.width) + gx];
                
                // Only draw if there's actual content or different background
                if (cell.char[0] == ' ' and cell.char[1] == 0 and std.meta.activeTag(cell.bg) == .none) {
                    continue;
                }
                
                if (std.meta.eql(cell.bg, a.ui_state.default_bg) or std.meta.activeTag(cell.bg) == .none) {
                    cell.bg = t.bg_editor;
                }
                if (std.meta.eql(cell.fg, a.ui_state.default_fg) or std.meta.activeTag(cell.fg) == .none) {
                    cell.fg = t.fg_primary;
                }
                if (cell.reverse) {
                    const tmp = cell.fg;
                    cell.fg = cell.bg;
                    cell.bg = tmp;
                }
                a.ren.setCell(sx, sy, cell);
            }
        }
    }

    // With ext_multigrid, editor content lives on secondary grids (grid 2+).
    // Render regular (non-float) windows first, then floats on top.
    // Two passes: pass 0 = regular windows, pass 1 = floats
    for (0..2) |pass| {
        for (a.ui_state.secondary_grids.items) |*entry| {
            const fg = &entry.data;
            // pass 0 = regular windows, pass 1 = floats
            if (pass == 0 and fg.is_float) continue;
            if (pass == 1 and !fg.is_float) continue;
            if (!fg.visible or fg.width == 0 or fg.height == 0) continue;
            var gy: u16 = 0;
            while (gy < fg.height) : (gy += 1) {
                const sy_i = @as(i32, @intCast(layout.editor.y)) + fg.row + @as(i32, @intCast(gy));
                if (sy_i < 0 or sy_i >= @as(i32, @intCast(layout.editor.y + layout.editor.h))) continue;
                const sy = @as(u16, @intCast(sy_i));

                var gx: u16 = 0;
                while (gx < fg.width) : (gx += 1) {
                    const sx_i = @as(i32, @intCast(layout.editor.x)) + fg.col + @as(i32, @intCast(gx));
                    if (sx_i < 0 or sx_i >= @as(i32, @intCast(layout.editor.x + layout.editor.w))) continue;
                    const sx = @as(u16, @intCast(sx_i));
                    var cell = fg.cells[@as(usize, gy) * @as(usize, fg.width) + gx];
                    if (std.meta.eql(cell.bg, a.ui_state.default_bg) or std.meta.eql(cell.bg, a.ui_state.normal_bg) or std.meta.eql(cell.bg, a.ui_state.cursorline_bg) or std.meta.eql(cell.bg, t.bg_editor) or std.meta.activeTag(cell.bg) == .none) {
                        cell.bg = t.bg_editor;
                    }
                    if (std.meta.eql(cell.fg, a.ui_state.default_fg) or std.meta.activeTag(cell.fg) == .none) {
                        cell.fg = t.fg_primary;
                    }
                    if (cell.reverse) {
                        const tmp = cell.fg;
                        cell.fg = cell.bg;
                        cell.bg = tmp;
                    }
                    a.ren.setCell(sx, sy, cell);
                }
            }
        }

        // After rendering regular windows (pass 0), draw split separators in between them
        if (pass == 0 and a.editor_wins.items.len > 1) {
            var sep_char = a.settings_widget.config.split_separator;
            if (std.mem.eql(u8, sep_char, "│") and a.settings_widget.config.nerd_fonts) {
                sep_char = "";
            }
            const horiz_sep_char = getHorizontalSeparator(sep_char);
            
            for (a.editor_wins.items) |win| {
                // Check for vertical separator to the right of this window
                var has_vsplit = false;
                for (a.editor_wins.items) |other| {
                    if (other.col == win.col + win.width + 1) {
                        has_vsplit = true;
                        break;
                    }
                }
                
                if (has_vsplit) {
                    const sx = layout.editor.x + win.col + win.width;
                    if (sx < layout.editor.x + layout.editor.w) {
                        var gy: u16 = 0;
                        const end_gy = @min(win.row + win.height + 1, layout.editor.h);
                        while (win.row + gy < end_gy) : (gy += 1) {
                            const sy = layout.editor.y + win.row + gy;
                            if (sy < layout.editor.y + layout.editor.h) {
                                var cell = Cell{ .fg = t.border_color, .bg = t.bg_editor };
                                cell.setChar(sep_char);
                                a.ren.setCell(sx, sy, cell);
                            }
                        }
                    }
                }
                
                // Check for horizontal separator below this window
                var has_hsplit = false;
                for (a.editor_wins.items) |other| {
                    if (other.row == win.row + win.height + 1) {
                        has_hsplit = true;
                        break;
                    }
                }
                
                if (has_hsplit) {
                    const sy = layout.editor.y + win.row + win.height;
                    if (sy < layout.editor.y + layout.editor.h) {
                        var gx: u16 = 0;
                        const end_gx = @min(win.col + win.width + 1, layout.editor.w);
                        while (win.col + gx < end_gx) : (gx += 1) {
                            const sx = layout.editor.x + win.col + gx;
                            if (sx < layout.editor.x + layout.editor.w) {
                                var cell = Cell{ .fg = t.border_color, .bg = t.bg_editor };
                                cell.setChar(horiz_sep_char);
                                a.ren.setCell(sx, sy, cell);
                            }
                        }
                    }
                }
            }
        }
    }

    if (a.mode != .zen) {
        a.activity_bar.draw(a.ren, layout.activity_bar, .{
            .bg_sidebar = t.bg_sidebar, .bg_accent = t.bg_accent,
            .fg_primary = t.fg_primary, .fg_secondary = t.fg_secondary, .border_color = t.border_color,
            .nerd_fonts = a.settings_widget.config.nerd_fonts,
        });
        if (a.show_file_tree) {
            if (a.activity_bar.active_idx == 0) {
                a.explorer.draw(a.ren, layout.file_tree, .{
                    .bg_sidebar = t.bg_sidebar, .bg_editor = t.bg_editor, .bg_accent = t.bg_accent,
                    .fg_primary = t.fg_primary, .fg_secondary = t.fg_secondary, .border_color = t.border_color, .fg_accent = t.fg_accent,
                    .nerd_fonts = a.settings_widget.config.nerd_fonts,
                });
            } else if (a.activity_bar.active_idx == 1) {
                a.search_panel.draw(a.ren, layout.file_tree, .{
                    .bg_sidebar = t.bg_sidebar, .bg_editor = t.bg_editor, .bg_accent = t.bg_accent,
                    .fg_primary = t.fg_primary, .fg_secondary = t.fg_secondary, .border_color = t.border_color, .fg_accent = t.fg_accent,
                    .nerd_fonts = a.settings_widget.config.nerd_fonts,
                });
            } else if (a.activity_bar.active_idx == 2) {
                a.git_panel.draw(a.ren, layout.file_tree, .{
                    .bg_sidebar = t.bg_sidebar, .bg_editor = t.bg_editor, .bg_accent = t.bg_accent,
                    .fg_primary = t.fg_primary, .fg_secondary = t.fg_secondary, .border_color = t.border_color, .fg_accent = t.fg_accent,
                });
            } else if (a.activity_bar.active_idx == 3) {
                a.ai_panel.draw(a.ren, layout.file_tree, .{
                    .bg_sidebar = t.bg_sidebar, .bg_editor = t.bg_editor, .bg_accent = t.bg_accent,
                    .fg_primary = t.fg_primary, .fg_secondary = t.fg_secondary, .border_color = t.border_color, .fg_accent = t.fg_accent,
                    .nerd_fonts = a.settings_widget.config.nerd_fonts,
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
            const tab_close_icon = if (a.settings_widget.config.nerd_fonts) "󰅖" else "x";
            drawText(a.ren, tx + tab_w - 3, layout.tab_bar.y, tab_close_icon, close_color, bg, false, false);
            tx += tab_w;
        }
        // Draw + button for new tab
        drawText(a.ren, tx + 1, layout.tab_bar.y, "+", t.fg_secondary, t.bg_sidebar, true, false);

        // Draw split buttons at the top right of the editor (in tab bar)
        if (layout.tab_bar.w > 15) {
            const btn_y = layout.tab_bar.y;
            const right_edge = layout.tab_bar.x + layout.tab_bar.w;
            // Draw Split Vertically (Right) pill: "  |  " on editor bg
            drawText(a.ren, right_edge - 13, btn_y, " ", t.fg_primary, t.bg_sidebar, false, false);
            drawText(a.ren, right_edge - 12, btn_y, "  |  ", t.fg_primary, t.bg_editor, false, false);
            
            // Draw Split Horizontally (Down) pill: "  -  " on editor bg
            drawText(a.ren, right_edge - 7, btn_y, " ", t.fg_primary, t.bg_sidebar, false, false);
            drawText(a.ren, right_edge - 6, btn_y, "  -  ", t.fg_primary, t.bg_editor, false, false);
        }
        
        // Draw Status Bar background
        drawRect(a.ren, layout.status_bar, " ", t.fg_primary, t.bg_statusbar);
        
        // Draw mode indicator
        const mode_str = switch (a.mode) {
            .ide => if (a.settings_widget.config.nerd_fonts) " 󰚌  IDE " else " IDE ",
            .normal => if (a.settings_widget.config.nerd_fonts) " 󰚌  NORMAL " else " NORMAL ",
            .zen => if (a.settings_widget.config.nerd_fonts) " 󰚌  ZEN " else " ZEN ",
        };
        drawText(a.ren, layout.status_bar.x + 1, layout.status_bar.y, mode_str, t.fg_statusbar, t.bg_statusbar, true, false);
        
        // Draw Branch in Status Bar
        const branch_name = a.git_panel.current_branch orelse "main";
        var status_buf: [128]u8 = undefined;
        const branch_display = if (a.settings_widget.config.nerd_fonts)
            std.fmt.bufPrint(&status_buf, "  {s} ", .{branch_name}) catch "  main "
        else
            std.fmt.bufPrint(&status_buf, " * {s} ", .{branch_name}) catch " * main ";
        drawText(a.ren, layout.status_bar.x + 12, layout.status_bar.y, branch_display, t.fg_statusbar, t.bg_statusbar, true, false);
        
        // Draw File in Status Bar
        const file_x = 12 + @as(u16, @intCast(branch_display.len)) + 1;
        var file_name_buf: [128]u8 = undefined;
        const active_file_name = if (a.tabs.items.len > a.active_tab) a.tabs.items[a.active_tab].name else "No File";
        const file_str = if (a.settings_widget.config.nerd_fonts)
            std.fmt.bufPrint(&file_name_buf, "󰌆  {s}", .{active_file_name}) catch active_file_name
        else
            active_file_name;
        drawText(a.ren, layout.status_bar.x + file_x, layout.status_bar.y, file_str, t.fg_statusbar, t.bg_statusbar, false, false);

        // Draw Help Button in Status Bar (Right aligned)
        const help_btn = if (a.settings_widget.config.nerd_fonts) " 󰋖 Help " else " [?] Help ";
        const help_x = layout.status_bar.w - @as(u16, @intCast(help_btn.len));
        drawText(a.ren, layout.status_bar.x + help_x, layout.status_bar.y, help_btn, t.fg_statusbar, t.bg_statusbar, true, false);

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
        }
        for (a.ui_state.telescope_rects, 0..) |rect_opt, idx| {
            if (rect_opt) |rect| {
                const draw_x = layout.editor.x + rect.x;
                const draw_y = layout.editor.y + rect.y;

                const wx = if (draw_x > 0) draw_x - 1 else 0;
                const wy = if (draw_y > 0) draw_y - 1 else 0;
                const shadow_color = Color{ .rgb = .{ .r = 10, .g = 10, .b = 10 } };

                const other_rect_opt = a.ui_state.telescope_rects[1 - idx];
                const has_other = (other_rect_opt != null);
                const ox1 = if (has_other) layout.editor.x + other_rect_opt.?.x - 1 else 0;
                const oy1 = if (has_other) layout.editor.y + other_rect_opt.?.y - 1 else 0;
                const ox2 = if (has_other) ox1 + other_rect_opt.?.w + 1 else 0;
                const oy2 = if (has_other) oy1 + other_rect_opt.?.h + 1 else 0;

                // Draw shadow right
                var sy: u16 = 1;
                while (sy <= rect.h + 1) : (sy += 1) {
                    const shadow_y = wy + sy;
                    const shadow_x1 = wx + rect.w + 2;
                    const shadow_x2 = wx + rect.w + 3;
                    
                    if (!has_other or !(shadow_x1 >= ox1 and shadow_x1 <= ox2 and shadow_y >= oy1 and shadow_y <= oy2)) {
                        a.ren.drawText(shadow_x1, shadow_y, " ", t.fg_primary, shadow_color, false, false);
                    }
                    if (!has_other or !(shadow_x2 >= ox1 and shadow_x2 <= ox2 and shadow_y >= oy1 and shadow_y <= oy2)) {
                        a.ren.drawText(shadow_x2, shadow_y, " ", t.fg_primary, shadow_color, false, false);
                    }
                }
                // Draw shadow bottom
                var sx: u16 = 1;
                while (sx <= rect.w + 3) : (sx += 1) {
                    const shadow_x = wx + sx;
                    const shadow_y = wy + rect.h + 2;
                    if (!has_other or !(shadow_x >= ox1 and shadow_x <= ox2 and shadow_y >= oy1 and shadow_y <= oy2)) {
                        a.ren.drawText(shadow_x, shadow_y, " ", t.fg_primary, shadow_color, false, false);
                    }
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
                    if (a.ui_state.widget_title_len > 0) {
                        a.ren.drawText(wx + 5, wy, a.ui_state.widget_title[0..a.ui_state.widget_title_len], t.fg_primary, t.border_color, true, false);
                    } else {
                        a.ren.drawText(wx + 5, wy, " Telescope ", t.fg_primary, t.border_color, true, false);
                    }
                } else {
                    // Top bar text
                    a.ren.drawText(wx + 5, wy, " Preview ", t.fg_primary, t.border_color, true, false);
                }
                
                // Red cross (Top Right) on both
                a.ren.drawText(wx + rect.w - 2, wy, " ✖ ", .{ .rgb = .{ .r = 255, .g = 80, .b = 80 } }, t.border_color, true, false);
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

    // Draw split dropdown menu if open
    if (a.show_split_menu) {
        const mx = a.split_menu_x;
        const my = a.split_menu_y;
        const mw: u16 = 24;
        const mh: u16 = 6;
        
        // Draw background shadow / fill
        var sy: u16 = 0;
        while (sy < mh) : (sy += 1) {
            var sx: u16 = 0;
            while (sx < mw) : (sx += 1) {
                a.ren.setCell(mx + sx, my + sy, Cell{
                    .char = [_]u8{ ' ', 0, 0, 0 }, .len = 1,
                    .fg = t.fg_primary, .bg = t.bg_sidebar,
                });
            }
        }
        
        // Draw borders
        var bx: u16 = 1;
        while (bx < mw - 1) : (bx += 1) {
            var top_c = Cell{ .fg = t.border_color, .bg = t.bg_sidebar };
            top_c.setChar("─");
            a.ren.setCell(mx + bx, my, top_c);
            var bot_c = Cell{ .fg = t.border_color, .bg = t.bg_sidebar };
            bot_c.setChar("─");
            a.ren.setCell(mx + bx, my + mh - 1, bot_c);
        }
        var by: u16 = 1;
        while (by < mh - 1) : (by += 1) {
            var left_c = Cell{ .fg = t.border_color, .bg = t.bg_sidebar };
            left_c.setChar("│");
            a.ren.setCell(mx, my + by, left_c);
            var right_c = Cell{ .fg = t.border_color, .bg = t.bg_sidebar };
            right_c.setChar("│");
            a.ren.setCell(mx + mw - 1, my + by, right_c);
        }
        
        var tl = Cell{ .fg = t.border_color, .bg = t.bg_sidebar }; tl.setChar("┌"); a.ren.setCell(mx, my, tl);
        var tr = Cell{ .fg = t.border_color, .bg = t.bg_sidebar }; tr.setChar("┐"); a.ren.setCell(mx + mw - 1, my, tr);
        var bl = Cell{ .fg = t.border_color, .bg = t.bg_sidebar }; bl.setChar("└"); a.ren.setCell(mx, my + mh - 1, bl);
        var br = Cell{ .fg = t.border_color, .bg = t.bg_sidebar }; br.setChar("┘"); a.ren.setCell(mx + mw - 1, my + mh - 1, br);
        
        // Draw menu items based on split menu direction
        if (a.split_menu_dir == .right) {
            drawText(a.ren, mx + 2, my + 1, "  Terminal (Right)", t.fg_primary, t.bg_sidebar, false, false);
            drawText(a.ren, mx + 2, my + 2, "  Terminal (Left) ", t.fg_primary, t.bg_sidebar, false, false);
            drawText(a.ren, mx + 2, my + 3, "󰝒  Editor (Right)  ", t.fg_primary, t.bg_sidebar, false, false);
            drawText(a.ren, mx + 2, my + 4, "󰝒  Editor (Left)   ", t.fg_primary, t.bg_sidebar, false, false);
        } else {
            drawText(a.ren, mx + 2, my + 1, "  Terminal (Bottom)", t.fg_primary, t.bg_sidebar, false, false);
            drawText(a.ren, mx + 2, my + 2, "  Terminal (Top)   ", t.fg_primary, t.bg_sidebar, false, false);
            drawText(a.ren, mx + 2, my + 3, "󰝒  Editor (Bottom)  ", t.fg_primary, t.bg_sidebar, false, false);
            drawText(a.ren, mx + 2, my + 4, "󰝒  Editor (Top)     ", t.fg_primary, t.bg_sidebar, false, false);
        }
    }

    // Draw close buttons on each active split window if there are multiple splits
    if (a.editor_wins.items.len > 1) {
        for (a.editor_wins.items) |win| {
            if (win.width > 4 and win.height > 1) {
                const w_gx = win.col + win.width - 2;
                const w_gy = win.row;
                var cell = Cell{
                    .char = [_]u8{ 226, 156, 150, 0 }, .len = 3, // '✖' is \u{2716} which is 3-bytes: [226, 156, 150]
                    .fg = if (win.active) Color{ .rgb = .{ .r = 255, .g = 80, .b = 80 } } else t.fg_secondary,
                    .bg = t.bg_editor,
                };
                if (w_gy < a.ui_state.grid.height and w_gx < a.ui_state.grid.width) {
                    const orig = a.ui_state.grid.cells[@as(usize, w_gy) * @as(usize, a.ui_state.grid.width) + w_gx];
                    if (std.meta.activeTag(orig.bg) != .none) {
                        cell.bg = orig.bg;
                    }
                }
                if (layout.editor.x + w_gx < a.ren.width and layout.editor.y + w_gy < a.ren.height) {
                    a.ren.setCell(layout.editor.x + w_gx, layout.editor.y + w_gy, cell);
                }
            }
        }
    }

    if (layout.panel != null and a.terminal_wins.items.len > 1) {
        for (a.terminal_wins.items) |win| {
            if (win.width > 4 and win.height > 1) {
                const w_gx = win.col + win.width - 2;
                const w_gy = win.row;
                var cell = Cell{
                    .char = [_]u8{ 226, 156, 150, 0 }, .len = 3,
                    .fg = if (win.active) Color{ .rgb = .{ .r = 255, .g = 80, .b = 80 } } else t.fg_secondary,
                    .bg = t.bg_terminal,
                };
                if (w_gy < a.ui_term.grid.height and w_gx < a.ui_term.grid.width) {
                    const orig = a.ui_term.grid.cells[@as(usize, w_gy) * @as(usize, a.ui_term.grid.width) + w_gx];
                    if (std.meta.activeTag(orig.bg) != .none) {
                        cell.bg = orig.bg;
                    }
                }
                if (layout.panel.?.x + w_gx < a.ren.width and layout.panel.?.y + 1 + w_gy < a.ren.height) {
                    a.ren.setCell(layout.panel.?.x + w_gx, layout.panel.?.y + 1 + w_gy, cell);
                }
            }
        }
    }
}
