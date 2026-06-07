const std = @import("std");
const RpcClient = @import("rpc.zig").RpcClient;
const msgpack = @import("msgpack.zig");
const Value = msgpack.Value;
const input = @import("../tui/input.zig");
const ui_protocol = @import("ui_protocol.zig");
const UiState = ui_protocol.UiState;
const App = @import("../tui/app.zig").App;
const WinInfo = @import("../tui/app.zig").WinInfo;
const RpcContext = @import("../tui/app.zig").RpcContext;
const theme = @import("../tui/theme.zig");
const Rect = @import("../tui/layout.zig").Rect;
const settings = @import("../tui/widgets/settings.zig");

pub fn sendMouseEvent(rpc: *RpcClient, alloc: std.mem.Allocator, m: input.MouseEvent, rel_col: u16, rel_row: u16) void {
    const button_str: []const u8 = switch (m.button) {
        .left => "left",
        .middle => "middle",
        .right => "right",
        .wheel_up => "wheel",
        .wheel_down => "wheel",
        .none => "none",
    };
    if (std.mem.eql(u8, button_str, "none")) return;
    
    const action_str: []const u8 = switch (m.action) {
        .press => if (m.button == .wheel_up) "up" else if (m.button == .wheel_down) "down" else "press",
        .release => "release",
        .move => "drag",
    };
    
    var p = alloc.alloc(Value, 6) catch return;
    p[0] = .{ .string = button_str };
    p[1] = .{ .string = action_str };
    p[2] = .{ .string = "" }; // modifier
    p[3] = .{ .integer = 0 }; // grid
    p[4] = .{ .integer = rel_row }; // row
    p[5] = .{ .integer = rel_col }; // col
    
    rpc.notify("nvim_input_mouse", p) catch {};
    alloc.free(p);
}

pub fn handleNotification(ctx: ?*anyopaque, method: []const u8, params: Value) anyerror!void {
    const rpc_ctx: *RpcContext = @alignCast(@ptrCast(ctx orelse return));
    const ui_state = rpc_ctx.ui_state;
    const app = rpc_ctx.app;

    if (std.mem.eql(u8, method, "redraw") and params == .array) {
        try ui_state.handleRedraw(params.array);
    } else if (std.mem.eql(u8, method, "vide_buf_enter") and params == .array and params.array.len > 0) {
        if (params.array[0] == .string) {
            if (ui_state.current_buf_path) |p| ui_state.allocator.free(p);
            ui_state.current_buf_path = try ui_state.allocator.dupe(u8, params.array[0].string);
            ui_state.buf_path_changed = true;
        }
    } else if (std.mem.eql(u8, method, "vide_telescope_rect")) {
        if (params == .array and params.array.len >= 2) {
            for (params.array[0..2], 0..) |p, i| {
                if (p == .array and p.array.len == 4) {
                    const arr = p.array;
                    ui_state.telescope_rects[i] = Rect{
                        .y = @as(u16, @intCast(@max(0, arr[0].integer))),
                        .x = @as(u16, @intCast(@max(0, arr[1].integer))),
                        .w = @as(u16, @intCast(@max(0, arr[2].integer))),
                        .h = @as(u16, @intCast(@max(0, arr[3].integer))),
                    };
                } else {
                    ui_state.telescope_rects[i] = null;
                }
            }
            if (params.array.len >= 3 and params.array[2] == .string) {
                const title = params.array[2].string;
                const len = @min(title.len, 32);
                std.mem.copyForwards(u8, ui_state.widget_title[0..len], title[0..len]);
                ui_state.widget_title_len = len;
            } else {
                ui_state.widget_title_len = 0;
            }
        } else {
            ui_state.telescope_rects[0] = null;
            ui_state.telescope_rects[1] = null;
            ui_state.widget_title_len = 0;
        }
    } else if (std.mem.eql(u8, method, "vide_toggle_zen")) {
        ui_state.toggle_zen_requested = true;
    } else if (std.mem.eql(u8, method, "vide_toggle_ide")) {
        ui_state.toggle_ide_requested = true;
    } else if (std.mem.eql(u8, method, "vide_settings_changed")) {
        const old_cfg = app.settings_widget.config;
        if (settings.SettingsConfig.load(app.settings_widget.allocator, app.settings_widget.settings_path)) |new_cfg| {
            app.settings_widget.config = new_cfg;
            app.settings_widget.allocator.free(old_cfg.theme);
            app.settings_widget.allocator.free(old_cfg.line_numbers);
            app.settings_widget.allocator.free(old_cfg.split_separator);
            app.settings_widget.allocator.free(old_cfg.mode);
            app.settings_widget.allocator.free(old_cfg.keybindings.toggle_terminal);
            app.settings_widget.allocator.free(old_cfg.keybindings.toggle_explorer);
            app.settings_widget.allocator.free(old_cfg.keybindings.toggle_zen);
            app.settings_widget.allocator.free(old_cfg.keybindings.new_file);
            app.settings_widget.allocator.free(old_cfg.keybindings.find_file);
            app.settings_widget.allocator.free(old_cfg.keybindings.quit);
            
            if (std.mem.eql(u8, app.settings_widget.config.mode, "zen")) {
                app.mode = .zen;
            } else if (std.mem.eql(u8, app.settings_widget.config.mode, "ide")) {
                app.mode = .ide;
            } else {
                app.mode = .normal;
            }
            if (app.mode != .zen) {
                app.prev_mode = app.mode;
            } else {
                app.settings_widget.is_open = false;
                app.mason_widget.is_open = false;
                app.lazy_widget.is_open = false;
                app.git_detailed_widget.is_open = false;
            }
        } else |_| {}
        app.needs_resize = true;
    } else if (std.mem.eql(u8, method, "vide_win_count") and params == .array and params.array.len > 0) {
        if (params.array[0] == .integer) {
            app.editor_win_count = @as(usize, @intCast(@max(1, params.array[0].integer)));
            app.needs_resize = true;
        }
    } else if (std.mem.eql(u8, method, "vide_win_positions") and params == .array and params.array.len > 0) {
        const wins = if (ui_state == app.ui_state) &app.editor_wins else &app.terminal_wins;
        wins.clearRetainingCapacity();
        const list_val = params.array[0];
        if (list_val == .array) {
            for (list_val.array) |w_val| {
                if (w_val == .map) {
                    var info = WinInfo{ .id = 0, .row = 0, .col = 0, .width = 0, .height = 0, .active = false };
                    for (w_val.map) |kv| {
                        if (kv.key == .string) {
                            const key = kv.key.string;
                            if (std.mem.eql(u8, key, "id") and kv.value == .integer) {
                                info.id = kv.value.integer;
                            } else if (std.mem.eql(u8, key, "row") and kv.value == .integer) {
                                info.row = @as(u16, @intCast(kv.value.integer));
                            } else if (std.mem.eql(u8, key, "col") and kv.value == .integer) {
                                info.col = @as(u16, @intCast(kv.value.integer));
                            } else if (std.mem.eql(u8, key, "width") and kv.value == .integer) {
                                info.width = @as(u16, @intCast(kv.value.integer));
                            } else if (std.mem.eql(u8, key, "height") and kv.value == .integer) {
                                info.height = @as(u16, @intCast(kv.value.integer));
                            } else if (std.mem.eql(u8, key, "active") and kv.value == .bool) {
                                info.active = kv.value.bool;
                            }
                        }
                    }
                    wins.append(info) catch {};
                }
            }
        }
        if (ui_state == app.ui_state) {
            app.editor_win_count = app.editor_wins.items.len;
        } else {
            app.terminal_win_count = app.terminal_wins.items.len;
        }

        app.needs_resize = true;
    } else if (std.mem.eql(u8, method, "vide_boundary_hit") and params == .array and params.array.len > 0) {
        if (params.array[0] == .string) {
            const dir = params.array[0].string;
            if (std.mem.eql(u8, dir, "j")) {
                if (app.show_terminal_panel and app.panel_position == .bottom) {
                    app.terminal_focus = true;
                    app.needs_resize = true;
                }
            } else if (std.mem.eql(u8, dir, "l")) {
                if (app.show_terminal_panel and app.panel_position == .right) {
                    app.terminal_focus = true;
                    app.needs_resize = true;
                }
            }
        }
    } else if (std.mem.eql(u8, method, "vide_theme_changed") and params == .array and params.array.len > 0) {
        if (params.array[0] == .map) {
            ui_state.theme_changed = true;
            // update theme directly using app.active_theme
            for (params.array[0].map) |kv| {
                if (kv.key == .string and kv.value == .string) {
                    const k = kv.key.string;
                    const v = kv.value.string;
                    if (theme.Theme.parseHexColor(v)) |c| {
                        if (std.mem.eql(u8, k, "bg_editor")) app.active_theme.bg_editor = c;
                        if (std.mem.eql(u8, k, "bg_sidebar")) app.active_theme.bg_sidebar = c;
                        if (std.mem.eql(u8, k, "bg_tab_active")) app.active_theme.bg_tab_active = c;
                        if (std.mem.eql(u8, k, "bg_tab_inactive")) app.active_theme.bg_tab_inactive = c;
                        if (std.mem.eql(u8, k, "bg_statusbar")) app.active_theme.bg_statusbar = c;
                        if (std.mem.eql(u8, k, "fg_statusbar")) app.active_theme.fg_statusbar = c;
                        if (std.mem.eql(u8, k, "bg_terminal")) app.active_theme.bg_terminal = c;
                        if (std.mem.eql(u8, k, "bg_accent")) app.active_theme.bg_accent = c;
                        if (std.mem.eql(u8, k, "fg_primary")) app.active_theme.fg_primary = c;
                        if (std.mem.eql(u8, k, "fg_secondary")) app.active_theme.fg_secondary = c;
                        if (std.mem.eql(u8, k, "fg_accent")) app.active_theme.fg_accent = c;
                        if (std.mem.eql(u8, k, "border_color")) app.active_theme.border_color = c;
                    }
                }
            }
        }
    }
}

pub fn processNvimEvents(rpc: *RpcClient) !bool {
    return try rpc.processNotifications();
}

pub fn openFile(rpc: *RpcClient, allocator: std.mem.Allocator, path: []const u8) !void {
    var params = try allocator.alloc(Value, 2);
    defer allocator.free(params);
    params[0] = .{ .string = "local path = select(1, ...); while #vim.api.nvim_win_get_config(0).relative > 0 do vim.cmd('close') end; vim.cmd('edit ' .. vim.fn.fnameescape(path))" };
    
    var lua_args = try allocator.alloc(Value, 1);
    defer allocator.free(lua_args);
    lua_args[0] = .{ .string = path };
    
    params[1] = .{ .array = lua_args };
    
    try rpc.notify("nvim_exec_lua", params);
}
