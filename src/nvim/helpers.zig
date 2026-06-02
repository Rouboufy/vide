const std = @import("std");
const RpcClient = @import("rpc.zig").RpcClient;
const msgpack = @import("msgpack.zig");
const Value = msgpack.Value;
const input = @import("../tui/input.zig");
const ui_protocol = @import("ui_protocol.zig");
const UiState = ui_protocol.UiState;
const App = @import("../tui/app.zig").App;
const RpcContext = @import("../tui/app.zig").RpcContext;
const theme = @import("../tui/theme.zig");
const Rect = @import("../tui/layout.zig").Rect;

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
        if (params == .array and params.array.len == 2) {
            for (params.array, 0..) |p, i| {
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
        } else {
            ui_state.telescope_rects[0] = null;
            ui_state.telescope_rects[1] = null;
        }
    } else if (std.mem.eql(u8, method, "vide_toggle_zen")) {
        ui_state.toggle_zen_requested = true;
    } else if (std.mem.eql(u8, method, "vide_toggle_ide")) {
        ui_state.toggle_ide_requested = true;
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
