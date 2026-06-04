const std = @import("std");
const app = @import("app.zig");
const App = app.App;
const input = @import("input.zig");
const nvim_helpers = @import("../nvim/helpers.zig");
const Value = @import("../nvim/msgpack.zig").Value;
const Layout = @import("layout.zig").Layout;

pub fn handleKey(a: *App, k: input.KeyEvent, layout: Layout) !bool {
    const nk = get_key: {
        if (k.raw.len == 1) {
            const b = k.raw[0];
            if (b == 0x0d or b == 0x0a) break :get_key "<Enter>";
            if (b == 0x1b) break :get_key "<Esc>";
            if (b == 0x7f or b == 0x08) break :get_key "<BS>";
            if (b == 5) break :get_key "<C-e>";
            if (b == 14) break :get_key "<C-n>";
            if (b == 19) break :get_key "<C-s>";
            if (b == 20) break :get_key "<C-t>";
            if (b == 26) break :get_key "<C-z>";
            break :get_key k.raw;
        }
        if (std.mem.eql(u8, k.raw, "\x1b[A") or std.mem.eql(u8, k.raw, "\x1bOA")) break :get_key "<Up>";
        if (std.mem.eql(u8, k.raw, "\x1b[B") or std.mem.eql(u8, k.raw, "\x1bOB")) break :get_key "<Down>";
        if (std.mem.eql(u8, k.raw, "\x1b[C") or std.mem.eql(u8, k.raw, "\x1bOC")) break :get_key "<Right>";
        if (std.mem.eql(u8, k.raw, "\x1b[D") or std.mem.eql(u8, k.raw, "\x1bOD")) break :get_key "<Left>";
        if (std.mem.eql(u8, k.raw, "\x1b[H")) break :get_key "<Home>";
        if (std.mem.eql(u8, k.raw, "\x1b[F")) break :get_key "<End>";
        if (std.mem.eql(u8, k.raw, "\x1b[5~")) break :get_key "<PageUp>";
        if (std.mem.eql(u8, k.raw, "\x1b[6~")) break :get_key "<PageDown>";
        if (std.mem.eql(u8, k.raw, "\x1b[3~")) break :get_key "<Del>";
        if (std.mem.eql(u8, k.raw, "\x1b[1;3A")) { // Alt+Up
            if (layout.panel != null) {
                if (a.panel_position == .bottom) {
                    if (layout.total.h > 4 and a.terminal_panel_height < layout.total.h - 4) {
                        a.terminal_panel_height +|= 1;
                        a.updateLayoutTree();
                        a.needs_resize = true;
                    }
                }
            }
            break :get_key "";
        }
        if (std.mem.eql(u8, k.raw, "\x1b[1;3B")) { // Alt+Down
            if (layout.panel != null) {
                if (a.panel_position == .bottom) {
                    if (a.terminal_panel_height > 2) {
                        a.terminal_panel_height -= 1;
                        a.updateLayoutTree();
                        a.needs_resize = true;
                    }
                }
            }
            break :get_key "";
        }
        if (std.mem.eql(u8, k.raw, "\x1b[1;3C")) { // Alt+Right
            if (layout.panel != null and a.panel_position == .right) {
                if (layout.total.w > 10 and a.terminal_panel_width > 10) {
                    a.terminal_panel_width -= 1;
                    a.updateLayoutTree();
                    a.needs_resize = true;
                }
            } else if (a.show_file_tree) {
                if (layout.total.w > layout.activity_bar.w + 10 and a.file_tree_width < layout.total.w - layout.activity_bar.w - 10) {
                    a.file_tree_width += 1;
                    a.needs_resize = true;
                }
            }
            break :get_key "";
        }
        if (std.mem.eql(u8, k.raw, "\x1b[1;3D")) { // Alt+Left
            if (layout.panel != null and a.panel_position == .right) {
                if (layout.total.w > 10 and a.terminal_panel_width < layout.total.w - 10) {
                    a.terminal_panel_width += 1;
                    a.updateLayoutTree();
                    a.needs_resize = true;
                }
            } else if (a.show_file_tree) {
                if (a.file_tree_width > 5) {
                    a.file_tree_width -= 1;
                    a.needs_resize = true;
                }
            }
            break :get_key "";
        }
        if (std.mem.eql(u8, k.raw, "\x1bp")) { // Alt+P
            a.panel_position = if (a.panel_position == .bottom) .right else .bottom;
            a.updateLayoutTree();
            a.needs_resize = true;
            break :get_key "";
        }
        break :get_key k.raw;
    };

    if (nk.len > 0) {
        if (a.settings_widget.is_open) {
            if (a.settings_widget.handleKey(nk)) {
                a.needs_resize = true;
            } else if (std.mem.eql(u8, nk, "<Esc>")) {
                a.settings_widget.is_open = false;
                a.needs_resize = true;
            }
            return true;
        }
        if (a.mason_widget.is_open) {
            if (a.mason_widget.handleKey(nk, a.rpc)) {
                a.needs_resize = true;
            }
            return true;
        }
        if (a.lazy_widget.is_open) {
            if (a.lazy_widget.handleKey(nk, a.rpc)) {
                a.needs_resize = true;
            }
            return true;
        }
        if (a.git_detailed_widget.is_open) {
            if (a.git_detailed_widget.handleKey(nk)) {
                a.needs_resize = true;
            }
            return true;
        }
    }

    var toggle_zen = false;
    var toggle_explorer = false;
    var toggle_terminal_panel = false;
    var new_file = false;
    
    if (std.mem.eql(u8, nk, a.settings_widget.config.keybindings.toggle_terminal)) toggle_terminal_panel = true;
    if (std.mem.eql(u8, nk, a.settings_widget.config.keybindings.toggle_explorer)) toggle_explorer = true;
    if (std.mem.eql(u8, nk, a.settings_widget.config.keybindings.toggle_zen)) toggle_zen = true;
    if (std.mem.eql(u8, nk, a.settings_widget.config.keybindings.new_file)) new_file = true;

    if (toggle_zen) {
        a.mode = if (a.mode == .ide) .zen else .ide;
        if (a.mode == .zen) {
            a.settings_widget.is_open = false;
            a.mason_widget.is_open = false;
            a.lazy_widget.is_open = false;
            a.git_detailed_widget.is_open = false;
        }
        a.needs_resize = true;
    } else if (toggle_explorer) {
        a.show_file_tree = !a.show_file_tree;
        a.needs_resize = true;
        return true;
    } else if (toggle_terminal_panel) {
        a.show_terminal_panel = !a.show_terminal_panel;
        a.updateLayoutTree();
        a.terminal_focus = a.show_terminal_panel;
        a.needs_resize = true;
        return true;
    } else if (new_file) {
        var buf: [32]u8 = undefined;
        const new_name = std.fmt.bufPrint(&buf, "File {d}", .{a.tabs.items.len + 1}) catch "File";
        a.tabs.append(.{
            .name = a.allocator.dupe(u8, new_name) catch "error",
            .path = null,
        }) catch {};
        a.active_tab = if (a.tabs.items.len > 0) a.tabs.items.len - 1 else 0;
        a.needs_resize = true;
        
        var cmd_p = try a.allocator.alloc(Value, 1);
        cmd_p[0] = .{ .string = "while #vim.api.nvim_win_get_config(0).relative > 0 do vim.cmd('close') end; vim.cmd('enew')" };
        var params = try a.allocator.alloc(Value, 2);
        defer a.allocator.free(params);
        params[0] = cmd_p[0];
        params[1] = .{ .array = &[_]Value{} };
        if (a.rpc.call("nvim_exec_lua", params) catch null) |res| {
            @import("../nvim/msgpack.zig").freeValue(res, a.allocator);
        }
        a.allocator.free(cmd_p);
        return true;
    }

    if (nk.len > 0) {
        if (a.show_file_tree and a.activity_bar.active_idx == 0 and a.explorer.action_state != .none) {
            if (a.explorer.handleKey(nk) catch false) {
                a.needs_resize = true;
                return true;
            }
        }
        if (a.show_file_tree and a.activity_bar.active_idx == 2 and a.git_panel.is_focus_commit) {
            if (a.git_panel.handleKey(nk) catch false) {
                a.needs_resize = true;
                return true;
            }
        }
        var ip = try a.allocator.alloc(Value, 1);
        defer a.allocator.free(ip);
        ip[0] = .{ .string = nk };
        (if (a.terminal_focus) a.rpc_term else a.rpc).notify("nvim_input", ip) catch {};
    }
    return true;
}

pub fn handleMouse(a: *App, m: input.MouseEvent, layout: Layout) !void {
    a.last_click_x = m.col; a.last_click_y = m.row;
    
    if (a.mode == .ide) {
        if (a.mason_widget.is_open) {
            if (a.mason_widget.handleMouse(m, a.ren.width, a.ren.height, a.rpc)) {
                a.needs_resize = true;
                return;
            } else if (m.action == .press) {
                a.mason_widget.is_open = false;
                a.needs_resize = true;
                return;
            }
        }
        if (a.lazy_widget.is_open) {
            if (a.lazy_widget.handleMouse(m, a.ren.width, a.ren.height)) {
                a.needs_resize = true;
                return;
            } else if (m.action == .press) {
                a.lazy_widget.is_open = false;
                a.needs_resize = true;
            }
        }
        if (a.git_detailed_widget.is_open) {
            if (a.git_detailed_widget.handleMouse(m, a.ren.width, a.ren.height)) {
                a.needs_resize = true;
                return;
            } else if (m.action == .press) {
                a.git_detailed_widget.is_open = false;
                a.needs_resize = true;
            }
        }

        if (m.action == .press) {
            for (a.ui_state.telescope_rects) |rect_opt| {
                if (rect_opt) |rect| {
                    const t_x = layout.editor.x + rect.x;
                    const t_y = layout.editor.y + rect.y;
                    const wx = if (t_x > 0) t_x - 1 else 0;
                    const wy = if (t_y > 0) t_y - 1 else 0;
                    if (m.row == wy and m.col >= wx + rect.w - 2 and m.col <= wx + rect.w) {
                        var ip = try a.allocator.alloc(Value, 1);
                        defer a.allocator.free(ip);
                        ip[0] = .{ .string = "<Esc><Esc>" };
                        a.rpc.notify("nvim_input", ip) catch {};
                        a.ui_state.telescope_rects[0] = null;
                        a.ui_state.telescope_rects[1] = null;
                        a.needs_resize = true;
                        return;
                    }
                }
            }

            if (a.settings_widget.is_open) {
                if (a.settings_widget.handleMouse(m.col, m.row, a.ren.width, a.ren.height)) {
                    a.needs_resize = true;
                    if (a.settings_widget.open_mason) {
                        a.settings_widget.open_mason = false;
                        a.settings_widget.is_open = false;
                        a.mason_widget.is_open = true;
                        a.mason_widget.refresh(a.rpc);
                    } else if (a.settings_widget.open_lazy) {
                        a.settings_widget.open_lazy = false;
                        a.settings_widget.is_open = false;
                        a.lazy_widget.is_open = true;
                        a.lazy_widget.refresh(a.rpc);
                    }
                } else {
                    a.settings_widget.is_open = false;
                    a.needs_resize = true;
                }
                return;
            }
            if (a.show_file_tree and m.col >= layout.file_tree.x and m.col < layout.file_tree.x + layout.file_tree.w and a.activity_bar.active_idx == 0 and m.button == .wheel_up) {
                a.explorer.handleScroll(-1);
                a.needs_resize = true;
            } else if (a.show_file_tree and m.col >= layout.file_tree.x and m.col < layout.file_tree.x + layout.file_tree.w and a.activity_bar.active_idx == 0 and m.button == .wheel_down) {
                a.explorer.handleScroll(1);
                a.needs_resize = true;
            } else if (a.show_file_tree and m.col >= layout.file_tree.x and m.col < layout.file_tree.x + layout.file_tree.w and a.activity_bar.active_idx == 2 and m.button == .wheel_up) {
                a.git_panel.handleScroll(-1);
                a.needs_resize = true;
            } else if (a.show_file_tree and m.col >= layout.file_tree.x and m.col < layout.file_tree.x + layout.file_tree.w and a.activity_bar.active_idx == 2 and m.button == .wheel_down) {
                a.git_panel.handleScroll(1);
                a.needs_resize = true;
            } else if (a.show_file_tree and m.col >= layout.file_tree.x + layout.file_tree.w - 2 and m.col <= layout.file_tree.x + layout.file_tree.w) {
                a.is_resizing_sidebar = true;
            } else if (a.show_file_tree and m.col >= layout.file_tree.x and m.col < layout.file_tree.x + layout.file_tree.w and m.row >= layout.file_tree.y and m.row < layout.file_tree.y + layout.file_tree.h) {
                if (a.activity_bar.active_idx == 0) {
                    if (a.explorer.handleMouse(m.col, m.row, layout.file_tree) catch null) |path| {
                        nvim_helpers.openFile(a.rpc, a.allocator, path) catch {};
                        if (a.tabs.items.len == 0) {
                            const basename = std.fs.path.basename(path);
                            a.tabs.append(.{
                                .name = a.allocator.dupe(u8, basename) catch "error",
                                .path = a.allocator.dupe(u8, path) catch null,
                            }) catch {};
                            a.active_tab = 0;
                        } else if (a.active_tab < a.tabs.items.len) {
                            const basename = std.fs.path.basename(path);
                            if (a.allocator.dupe(u8, basename) catch null) |new_name| {
                                a.allocator.free(a.tabs.items[a.active_tab].name);
                                a.tabs.items[a.active_tab].name = new_name;
                            }
                            if (a.allocator.dupe(u8, path) catch null) |new_path| {
                                if (a.tabs.items[a.active_tab].path) |p| a.allocator.free(p);
                                a.tabs.items[a.active_tab].path = new_path;
                            }
                        }
                    }
                    a.needs_resize = true;
                } else if (a.activity_bar.active_idx == 1) {
                    if (a.search_panel.handleMouse(m.col, m.row, layout.file_tree)) |cmd| {
                        if (std.mem.startsWith(u8, cmd, "__CMD__:Telescope")) {
                            const actual_cmd = cmd[8..];
                            var cmd_p = try a.allocator.alloc(Value, 1);
                            defer a.allocator.free(cmd_p);
                            cmd_p[0] = .{ .string = actual_cmd };
                            a.rpc.notify("nvim_command", cmd_p) catch {};
                        }
                    }
                    a.needs_resize = true;
                } else if (a.activity_bar.active_idx == 2) {
                    if (a.git_panel.handleMouse(m.col, m.row, layout.file_tree) catch null) |path| {
                        if (std.mem.startsWith(u8, path, "__CMD__:GitWidget")) {
                            a.git_detailed_widget.is_open = true;
                            a.git_detailed_widget.refresh();
                            a.needs_resize = true;
                        } else {
                            nvim_helpers.openFile(a.rpc, a.allocator, path) catch {};
                            if (a.tabs.items.len == 0) {
                                const basename = std.fs.path.basename(path);
                                a.tabs.append(.{
                                    .name = a.allocator.dupe(u8, basename) catch "error",
                                    .path = a.allocator.dupe(u8, path) catch null,
                                }) catch {};
                                a.active_tab = 0;
                            } else if (a.active_tab < a.tabs.items.len) {
                                const basename = std.fs.path.basename(path);
                                if (a.allocator.dupe(u8, basename) catch null) |new_name| {
                                    a.allocator.free(a.tabs.items[a.active_tab].name);
                                    a.tabs.items[a.active_tab].name = new_name;
                                }
                                if (a.allocator.dupe(u8, path) catch null) |new_path| {
                                    if (a.tabs.items[a.active_tab].path) |p| a.allocator.free(p);
                                    a.tabs.items[a.active_tab].path = new_path;
                                }
                            }
                        }
                    }
                    a.needs_resize = true;
                }
            } else if (layout.panel != null and m.row == layout.panel.?.y) {
                const px = m.col - layout.panel.?.x;
                if (px >= 2 and px <= 12) {
                    a.active_terminal_panel_idx = 0;
                    a.terminal_focus = true;
                } else if (px >= 13 and px <= 28) {
                    a.active_terminal_panel_idx = 1;
                    a.terminal_focus = false;
                    a.debug_console.refresh(a.rpc);
                } else if (px >= 30 and px <= 38) {
                    a.active_terminal_panel_idx = 2;
                    a.terminal_focus = false;
                    a.output_panel.refresh(a.rpc);
                } else {
                    a.is_resizing_panel = true;
                }
                a.needs_resize = true;
            } else if (layout.panel != null and a.panel_position == .bottom and layout.panel.?.y > 0 and (m.row == layout.panel.?.y - 1 or m.row == layout.panel.?.y + 1)) {
                a.is_resizing_panel = true;
            } else if (layout.panel != null and a.panel_position == .right and layout.panel.?.x > 0 and (m.col == layout.panel.?.x - 1 or m.col == layout.panel.?.x)) {
                a.is_resizing_panel = true;
            } else {
                const prev_idx = a.activity_bar.active_idx;
                if (a.activity_bar.handleMouse(m.col, m.row, layout.activity_bar)) |new_idx| {
                    if (prev_idx != new_idx) a.needs_resize = true;
                    if (new_idx == 99) {
                        a.settings_widget.is_open = true;
                        a.needs_resize = true;
                        a.activity_bar.active_idx = prev_idx; // Revert active idx visually
                    } else if (a.show_file_tree and prev_idx == new_idx) {
                        a.show_file_tree = false;
                        a.needs_resize = true;
                    } else if (!a.show_file_tree) {
                        a.show_file_tree = true;
                        a.needs_resize = true;
                    }
                }
                
                // Handle tab bar clicks
                if (m.row == layout.tab_bar.y) {
                    var tx: u16 = layout.tab_bar.x;
                    var clicked_tab = false;
                    for (a.tabs.items, 0..) |tab, i| {
                        const tab_w: u16 = @as(u16, @intCast(tab.name.len)) + 8;
                        if (m.col >= tx and m.col < tx + tab_w) {
                            if (m.col >= tx + tab_w - 3 and m.col < tx + tab_w) {
                                // Close tab
                                if (a.tabs.items.len > 0) {
                                    const removed = a.tabs.orderedRemove(i);
                                    a.allocator.free(removed.name);
                                    if (removed.path) |p| a.allocator.free(p);
                                    
                                    // Actually close the buffer in Neovim
                                    var cmd_p = try a.allocator.alloc(Value, 1);
                                    cmd_p[0] = .{ .string = "bdelete" };
                                    a.rpc.notify("nvim_command", cmd_p) catch {};
                                    a.allocator.free(cmd_p);
                                    
                                    if (a.tabs.items.len == 0) {
                                        a.active_tab = 0;
                                        var alpha_p = try a.allocator.alloc(Value, 1);
                                        alpha_p[0] = .{ .string = "lua _G.vide_alpha_start()" };
                                        a.rpc.notify("nvim_command", alpha_p) catch {};
                                        a.allocator.free(alpha_p);
                                    } else if (a.active_tab >= a.tabs.items.len) {
                                        a.active_tab = a.tabs.items.len - 1;
                                    }
                                    a.needs_resize = true;
                                }
                            } else {
                                a.active_tab = i;
                                a.needs_resize = true; // force redraw
                                if (a.tabs.items[i].path) |p| {
                                    nvim_helpers.openFile(a.rpc, a.allocator, p) catch {};
                                }
                            }
                            clicked_tab = true;
                            break;
                        }
                        tx += tab_w;
                    }
                    if (!clicked_tab and m.col == tx + 1) {
                        // New tab
                        var buf: [32]u8 = undefined;
                        const new_name = try std.fmt.bufPrint(&buf, "File {d}", .{a.tabs.items.len + 1});
                        try a.tabs.append(.{
                            .name = try a.allocator.dupe(u8, new_name),
                            .path = null,
                        });
                        a.active_tab = a.tabs.items.len - 1;
                        a.needs_resize = true;
                        var cmd_p = try a.allocator.alloc(Value, 1);
                        cmd_p[0] = .{ .string = "enew" };
                        a.rpc.notify("nvim_command", cmd_p) catch {};
                        a.allocator.free(cmd_p);
                    }
                }
            }
        }
        
        if (m.action == .move) {
            if (a.is_resizing_sidebar) {
                if (m.col > layout.activity_bar.w + 5) {
                    var new_w = m.col - layout.activity_bar.w;
                    const max_w = if (layout.total.w > layout.activity_bar.w + 10) layout.total.w - layout.activity_bar.w - 10 else 0;
                    if (new_w > max_w) {
                        new_w = max_w;
                    }
                    a.file_tree_width = new_w;
                    a.needs_resize = true;
                }
            } else if (a.is_resizing_panel) {
                if (a.panel_position == .bottom) {
                    if (layout.total.h > 2 and m.row < layout.total.h - 2) {
                        const new_h = layout.total.h - 1 - m.row;
                        if (new_h >= 2 and new_h < layout.total.h - 2) {
                            a.terminal_panel_height = new_h;
                            a.updateLayoutTree();
                            a.needs_resize = true;
                        }
                    }
                } else {
                    if (layout.total.w > 10 and m.col < layout.total.w - 5) {
                        const new_w = layout.total.w - 1 - m.col;
                        if (new_w >= 10 and new_w < layout.total.w - 10) {
                            a.terminal_panel_width = new_w;
                            a.updateLayoutTree();
                            a.needs_resize = true;
                        }
                    }
                }
            }
        }
        
        const was_resizing = a.is_resizing_sidebar or a.is_resizing_panel;
        if (m.action == .release) {
            a.is_resizing_sidebar = false;
            a.is_resizing_panel = false;
            a.needs_resize = true;
        }
        if (was_resizing) return;
    }

    if (a.is_resizing_sidebar or a.is_resizing_panel) return;

    if (layout.panel != null and m.col >= layout.panel.?.x and m.col < layout.panel.?.x + layout.panel.?.w and
        m.row > layout.panel.?.y and m.row < layout.panel.?.y + layout.panel.?.h)
    {
        if (a.active_terminal_panel_idx == 0) {
            if (m.action == .press or m.action == .release) a.terminal_focus = true;
            if (m.button == .wheel_up or m.button == .wheel_down) {
                nvim_helpers.sendMouseEvent(a.rpc_term, a.allocator, m, m.col - layout.panel.?.x, m.row - layout.panel.?.y - 1);
            }
        } else if (a.active_terminal_panel_idx == 1) {
            if (m.action == .press and m.button == .wheel_up) a.debug_console.handleScroll(-1);
            if (m.action == .press and m.button == .wheel_down) a.debug_console.handleScroll(1);
            a.needs_resize = true;
        } else if (a.active_terminal_panel_idx == 2) {
            if (m.action == .press and m.button == .wheel_up) a.output_panel.handleScroll(-1);
            if (m.action == .press and m.button == .wheel_down) a.output_panel.handleScroll(1);
            a.needs_resize = true;
        }
    } else if (m.col >= layout.editor.x and m.col < layout.editor.x + layout.editor.w and
                m.row >= layout.editor.y and m.row < layout.editor.y + layout.editor.h)
    {
        if (m.action == .press) a.terminal_focus = false;
        nvim_helpers.sendMouseEvent(a.rpc, a.allocator, m, m.col - layout.editor.x, m.row - layout.editor.y);
    } else {
        if (m.action == .press) a.terminal_focus = false;
    }
}
