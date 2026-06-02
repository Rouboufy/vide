const std = @import("std");
const posix = std.posix;
const Terminal = @import("tui/terminal.zig").Terminal;
const Renderer = @import("tui/renderer.zig").Renderer;
const Color = @import("tui/renderer.zig").Color;
const Cell = @import("tui/renderer.zig").Cell;
const Layout = @import("tui/layout.zig").Layout;
const Rect = @import("tui/layout.zig").Rect;
const input = @import("tui/input.zig");
const ActivityBar = @import("tui/widgets/activity_bar.zig").ActivityBar;
const Explorer = @import("tui/widgets/explorer.zig").Explorer;
const GitPanel = @import("tui/widgets/git_panel.zig").GitPanel;
const SettingsWidget = @import("tui/widgets/settings.zig").SettingsWidget;
const MasonWidget = @import("tui/widgets/mason.zig").MasonWidget;
const LazyWidget = @import("tui/widgets/lazy.zig").LazyWidget;
const GitDetailedWidget = @import("tui/widgets/git_detailed.zig").GitDetailedWidget;
const SearchPanel = @import("tui/widgets/search_panel.zig").SearchPanel;
const OutputPanel = @import("tui/widgets/output_panel.zig").OutputPanel;
const DebugConsole = @import("tui/widgets/debug_console.zig").DebugConsole;

var global_term: ?*Terminal = null;

pub fn panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    _ = error_return_trace;
    if (global_term) |term| {
        term.deinit();
    } else {
        const esc = "\x1b[?2004l\x1b[?1002l\x1b[?1006l\x1b[?25h\x1b[?1049l\x1b[0m\r\n";
        _ = posix.system.write(2, esc, esc.len);
    }
    std.debug.defaultPanic(msg, ret_addr);
}

const Mode = enum { ide, zen };

// VSCode Colors Theme Mapping
var bg_editor = Color{ .rgb = .{ .r = 30, .g = 30, .b = 30 } };
var bg_sidebar = Color{ .rgb = .{ .r = 37, .g = 37, .b = 38 } };
var bg_tab_active = Color{ .rgb = .{ .r = 30, .g = 30, .b = 30 } };
var bg_tab_inactive = Color{ .rgb = .{ .r = 45, .g = 45, .b = 45 } };
var bg_statusbar = Color{ .rgb = .{ .r = 0, .g = 95, .b = 184 } }; // Highly visible bright blue
var fg_statusbar = Color{ .rgb = .{ .r = 255, .g = 255, .b = 255 } }; // White default
var bg_terminal = Color{ .rgb = .{ .r = 10, .g = 10, .b = 10 } }; // Darker background for terminal
var bg_accent = Color{ .rgb = .{ .r = 0, .g = 122, .b = 204 } };
var fg_primary = Color{ .rgb = .{ .r = 212, .g = 212, .b = 212 } };
var fg_secondary = Color{ .rgb = .{ .r = 133, .g = 133, .b = 133 } };
var fg_accent = Color{ .rgb = .{ .r = 204, .g = 204, .b = 204 } };
var border_color = Color{ .rgb = .{ .r = 60, .g = 60, .b = 60 } };

fn parseHexColor(hex: []const u8) ?Color {
    if (hex.len != 7 or hex[0] != '#') return null;
    const r = std.fmt.parseInt(u8, hex[1..3], 16) catch return null;
    const g = std.fmt.parseInt(u8, hex[3..5], 16) catch return null;
    const b = std.fmt.parseInt(u8, hex[5..7], 16) catch return null;
    return Color{ .rgb = .{ .r = r, .g = g, .b = b } };
}

fn drawRect(renderer: *Renderer, rect: Rect, char: []const u8, fg: Color, bg: Color) void {
    renderer.drawRect(rect, char, fg, bg);
}

fn drawText(renderer: *Renderer, x: u16, y: u16, text: []const u8, fg: Color, bg: Color, bold: bool, italic: bool) void {
    renderer.drawText(x, y, text, fg, bg, bold, italic);
}

const NvimProcess = @import("nvim/process.zig").NvimProcess;
const RpcClient = @import("nvim/rpc.zig").RpcClient;
const UiState = @import("nvim/ui_protocol.zig").UiState;
const msgpack = @import("nvim/msgpack.zig");
const Value = msgpack.Value;
const Pty = @import("tui/pty.zig").Pty;

fn sendMouseEvent(rpc: *RpcClient, alloc: std.mem.Allocator, m: input.MouseEvent, rel_col: u16, rel_row: u16) void {
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

fn handleNotification(ctx: ?*anyopaque, method: []const u8, params: Value) anyerror!void {
    const ui_state: *UiState = @alignCast(@ptrCast(ctx orelse return));
    if (std.mem.eql(u8, method, "redraw") and params == .array) {
        try ui_state.handleRedraw(params.array);
    } else if (std.mem.eql(u8, method, "vide_buf_enter") and params == .array and params.array.len > 0) {
        if (params.array[0] == .string) {
            if (ui_state.current_buf_path) |p| ui_state.allocator.free(p);
            ui_state.current_buf_path = try ui_state.allocator.dupe(u8, params.array[0].string);
            ui_state.buf_path_changed = true;
        }
    } else if (std.mem.eql(u8, method, "vide_telescope_rect") and params == .array) {
        if (params.array.len > 0 and params.array[0] == .array) {
            const arr = params.array[0].array;
            if (arr.len == 4 and arr[0] == .integer and arr[1] == .integer and arr[2] == .integer and arr[3] == .integer) {
                ui_state.telescope_rect = Rect{
                    .y = @as(u16, @intCast(@min(65535, @max(0, arr[0].integer)))),
                    .x = @as(u16, @intCast(@min(65535, @max(0, arr[1].integer)))),
                    .w = @as(u16, @intCast(@min(65535, @max(0, arr[2].integer)))),
                    .h = @as(u16, @intCast(@min(65535, @max(0, arr[3].integer)))),
                };
            } else {
                ui_state.telescope_rect = null;
            }
        } else {
            ui_state.telescope_rect = null;
        }
    } else if (std.mem.eql(u8, method, "vide_toggle_zen")) {
        // Toggle zen mode
        ui_state.toggle_zen_requested = true;
    } else if (std.mem.eql(u8, method, "vide_toggle_ide")) {
        // Toggle ide mode
        ui_state.toggle_ide_requested = true;
    } else if (std.mem.eql(u8, method, "vide_theme_changed") and params == .array and params.array.len > 0) {
        if (params.array[0] == .map) {
            ui_state.theme_changed = true;
            for (params.array[0].map) |kv| {
                if (kv.key == .string and kv.value == .string) {
                    const k = kv.key.string;
                    const v = kv.value.string;
                    if (parseHexColor(v)) |c| {
                        if (std.mem.eql(u8, k, "bg_editor")) bg_editor = c;
                        if (std.mem.eql(u8, k, "bg_sidebar")) bg_sidebar = c;
                        if (std.mem.eql(u8, k, "bg_tab_active")) bg_tab_active = c;
                        if (std.mem.eql(u8, k, "bg_tab_inactive")) bg_tab_inactive = c;
                        if (std.mem.eql(u8, k, "bg_statusbar")) bg_statusbar = c;
                        if (std.mem.eql(u8, k, "fg_statusbar")) fg_statusbar = c;
                        if (std.mem.eql(u8, k, "bg_terminal")) bg_terminal = c;
                        if (std.mem.eql(u8, k, "bg_accent")) bg_accent = c;
                        if (std.mem.eql(u8, k, "fg_primary")) fg_primary = c;
                        if (std.mem.eql(u8, k, "fg_secondary")) fg_secondary = c;
                        if (std.mem.eql(u8, k, "fg_accent")) fg_accent = c;
                        if (std.mem.eql(u8, k, "border_color")) border_color = c;
                    }
                }
            }
        }
    }
}

fn processNvimEvents(rpc: *RpcClient) !bool {
    return try rpc.processNotifications();
}

fn openFile(rpc: *RpcClient, allocator: std.mem.Allocator, path: []const u8) !void {
    var params = try allocator.alloc(Value, 2);
    defer allocator.free(params);
    params[0] = .{ .string = "local path = select(1, ...); while #vim.api.nvim_win_get_config(0).relative > 0 do vim.cmd('close') end; vim.cmd('edit ' .. vim.fn.fnameescape(path))" };
    
    var lua_args = try allocator.alloc(Value, 1);
    defer allocator.free(lua_args);
    lua_args[0] = .{ .string = path };
    
    params[1] = .{ .array = lua_args };
    
    try rpc.notify("nvim_exec_lua", params);
}

pub fn main(init: std.process.Init) !void {
    innerMain(init) catch |err| {
        if (err == error.EndOfStream or err == error.QuitApplication) return;
        return err;
    };
}

fn innerMain(init: std.process.Init) !void {
    const alloc = init.gpa;
    var term = try Terminal.init();
    defer term.deinit();
    global_term = &term;

    var sa = std.posix.Sigaction{
        .handler = .{ .handler = input.handleSigwinch },
        .mask = std.mem.zeroes(std.posix.sigset_t),
        .flags = 0,
    };
    std.posix.sigaction(std.posix.SIG.WINCH, &sa, null);

    var sigwinch_pipe: [2]std.posix.fd_t = undefined;
    _ = std.os.linux.pipe2(&sigwinch_pipe, .{ .NONBLOCK = true });
    input.sigwinch_pipe_write_fd = sigwinch_pipe[1];

    const size = try term.getSize();
    var renderer = try Renderer.init(alloc, size[0], size[1], term.writer());
    defer renderer.deinit(alloc);

    var mode: Mode = .ide;
    var activity_bar = ActivityBar{ .active_idx = 0 };
    var last_click_x: u16 = 0;
    var last_click_y: u16 = 0;

    app_loop: while (true) {
        var nvim = try NvimProcess.spawn(init.io, alloc);
        defer nvim.deinit(init.io);
        var rpc = RpcClient.init(nvim, alloc, init.io);
        var ui_state = UiState.init(alloc);
        defer ui_state.deinit();

        var nvim_term = try NvimProcess.spawn(init.io, alloc);
        defer nvim_term.deinit(init.io);
        var rpc_term = RpcClient.init(nvim_term, alloc, init.io);
        var ui_term = UiState.init(alloc);
        defer ui_term.deinit();

        var args = init.minimal.args.iterate();
        _ = args.skip(); // skip executable name
        const initial_file: ?[]const u8 = args.next();

        runNvimSession(initial_file, init, alloc, &term, &renderer, &rpc, &ui_state, &rpc_term, &ui_term, &mode, &activity_bar, &last_click_x, &last_click_y, sigwinch_pipe[0]) catch |err| {
            if (err == error.EndOfStream) continue :app_loop;
            if (err == error.QuitApplication) break :app_loop;
            return err;
        };
    }
}

fn runNvimSession(
    initial_file: ?[]const u8,
    init: std.process.Init,
    alloc: std.mem.Allocator,
    term: *Terminal,
    renderer: *Renderer,
    rpc: *RpcClient,
    ui_state: *UiState,
    rpc_term: *RpcClient,
    ui_term: *UiState,
    mode_ptr: *Mode,
    activity_bar: *ActivityBar,
    lc_x: *u16,
    lc_y: *u16,
    sigwinch_read_fd: std.posix.fd_t,
) !void {
    rpc.on_notification = handleNotification;
    rpc.on_notification_ctx = ui_state;

    rpc_term.on_notification = handleNotification;
    rpc_term.on_notification_ctx = ui_term;

    var show_file_tree = true;
    var file_tree_width: u16 = @max(15, @min(40, @as(u16, @intFromFloat(
        @as(f32, @floatFromInt(renderer.width)) * 0.20
    ))));
    var is_resizing_sidebar = false;
    var is_resizing_panel = false;
    var terminal_panel_height: u16 = 8;
    
    var explorer = Explorer.init(alloc, init.io);
    defer explorer.deinit();
    explorer.refresh() catch {};

    var git_panel = GitPanel.init(alloc, init.io);
    defer git_panel.deinit();
    git_panel.refresh() catch {};

    var search_panel = SearchPanel.init(alloc);
    defer search_panel.deinit();

    var output_panel = OutputPanel.init(alloc);
    defer output_panel.deinit();

    var debug_console = DebugConsole.init(alloc);
    defer debug_console.deinit();

    const home = init.environ_map.get("HOME") orelse "";
    const settings_path = try std.fs.path.join(alloc, &[_][]const u8{ home, ".local", "share", "vide", "settings.json" });
    const preview_path = try std.fs.path.join(alloc, &[_][]const u8{ home, ".local", "share", "vide", "preview.json" });
    defer alloc.free(settings_path);
    defer alloc.free(preview_path);
    var settings_widget = SettingsWidget.init(alloc, settings_path);
    
    var mason_widget = MasonWidget.init(alloc);
    defer mason_widget.deinit();
    var lazy_widget = LazyWidget.init(alloc);
    defer lazy_widget.deinit();
    var git_detailed_widget = GitDetailedWidget.init(alloc, init.io);
    defer git_detailed_widget.deinit();
    defer settings_widget.deinit();

    const initial_show_panel = (mode_ptr.* == .ide) and false; // initial show_terminal_panel
    const initial_layout = Layout.compute(renderer.width, renderer.height, initial_show_panel, mode_ptr.* == .zen, show_file_tree, file_tree_width, terminal_panel_height);

    var opt_kvs = try alloc.alloc(Value.KV, 2);
    defer alloc.free(opt_kvs);
    opt_kvs[0] = .{ .key = .{ .string = "rgb" }, .value = .{ .bool = true } };
    opt_kvs[1] = .{ .key = .{ .string = "ext_linegrid" }, .value = .{ .bool = true } };

    var attach_params = try alloc.alloc(Value, 3);
    defer alloc.free(attach_params);
    attach_params[0] = .{ .integer = initial_layout.editor.w };
    attach_params[1] = .{ .integer = initial_layout.editor.h };
    attach_params[2] = .{ .map = opt_kvs };

    const attach_result = try rpc.call("nvim_ui_attach", attach_params);
    msgpack.freeValue(attach_result, alloc);

    var term_attach_params = try alloc.alloc(Value, 3);
    defer alloc.free(term_attach_params);
    term_attach_params[0] = .{ .integer = if (initial_layout.panel) |p| p.w else 80 };
    term_attach_params[1] = .{ .integer = if (initial_layout.panel) |p| (if (p.h > 0) @max(1, p.h - 1) else 1) else 7 };
    term_attach_params[2] = .{ .map = opt_kvs };
    const term_attach_result = try rpc_term.call("nvim_ui_attach", term_attach_params);
    msgpack.freeValue(term_attach_result, alloc);

    {
        var cp = try alloc.alloc(Value, 1);
        defer alloc.free(cp);
        
        cp[0] = .{ .string = "set laststatus=0" };
        const r1 = try rpc_term.call("nvim_command", cp);
        msgpack.freeValue(r1, alloc);

        cp[0] = .{ .string = "autocmd BufEnter * call rpcnotify(1, 'vide_buf_enter', expand('%:p'))" };
        const r_au = try rpc.call("nvim_command", cp);
        msgpack.freeValue(r_au, alloc);

        cp[0] = .{ .string = "autocmd BufWritePost * let b:vide_session_saved = 1" };
        const r_au2 = try rpc.call("nvim_command", cp);
        msgpack.freeValue(r_au2, alloc);

        cp[0] = .{ .string = "set shortmess+=I" };
        const r_sm = try rpc.call("nvim_command", cp);
        msgpack.freeValue(r_sm, alloc);

        cp[0] = .{ .string = "terminal" };
        const r2 = try rpc_term.call("nvim_command", cp);
        msgpack.freeValue(r2, alloc);

        cp[0] = .{ .string = "startinsert" };
        const r3 = try rpc_term.call("nvim_command", cp);
        msgpack.freeValue(r3, alloc);
    }

    var seq_buf: [4096]u8 = undefined;
    var needs_resize = false;
    var was_settings_open = false;

    const TabInfo = struct {
        name: []const u8,
        path: ?[]const u8,
    };
    var tabs = std.array_list.Managed(TabInfo).init(alloc);
    defer {
        for (tabs.items) |t| {
            alloc.free(t.name);
            if (t.path) |p| alloc.free(p);
        }
        tabs.deinit();
    }
    if (initial_file) |f| {
        try tabs.append(.{
            .name = try alloc.dupe(u8, std.fs.path.basename(f)),
            .path = try alloc.dupe(u8, f),
        });
        openFile(rpc, alloc, f) catch {};
    } else {
        var params = try alloc.alloc(Value, 2);
        params[0] = .{ .string = @embedFile("nvim/vide_init.lua") };
        params[1] = .{ .array = &[_]Value{} };
        if (rpc.call("nvim_exec_lua", params)) |res| {
            msgpack.freeValue(res, alloc);
        } else |_| {}
        alloc.free(params);
    }
    var active_tab: usize = 0;

    var terminal_focus = false;
    var show_terminal_panel = false;
    var active_terminal_panel_idx: u8 = 0;
    var last_explorer_refresh: i64 = 0;

    while (true) {
        var ts: std.posix.timespec = undefined;
        _ = std.posix.system.clock_gettime(std.posix.CLOCK.MONOTONIC, &ts);
        const now = ts.sec;

        if (now - last_explorer_refresh >= 2) {
            last_explorer_refresh = now;
            if (explorer.refreshStatus(rpc)) {
                needs_resize = true; // force redraw
            }
            if (activity_bar.active_idx == 2) {
                git_panel.refresh() catch {};
                needs_resize = true;
            }
        }

        const cols = renderer.width;
        const rows = renderer.height;
        const show_panel = (mode_ptr.* == .ide) and show_terminal_panel;
        const layout = Layout.compute(cols, rows, show_panel, mode_ptr.* == .zen, show_file_tree, file_tree_width, terminal_panel_height);

        if (needs_resize) {
            needs_resize = false;
            var rp = try alloc.alloc(Value, 2);
            defer alloc.free(rp);
            rp[0] = .{ .integer = layout.editor.w };
            rp[1] = .{ .integer = layout.editor.h };
            if (rpc.call("nvim_ui_try_resize", rp) catch null) |res| {
                msgpack.freeValue(res, alloc);
            }
            if (layout.panel) |panel| {
                var tp = try alloc.alloc(Value, 2);
                defer alloc.free(tp);
                tp[0] = .{ .integer = panel.w };
                tp[1] = .{ .integer = if (panel.h > 0) @max(1, panel.h - 1) else 1 };
                if (rpc_term.call("nvim_ui_try_resize", tp) catch null) |tres| {
                    msgpack.freeValue(tres, alloc);
                }
            }
        }

        const nvim_alive = try processNvimEvents(rpc);
        if (!nvim_alive) return;
        _ = try processNvimEvents(rpc_term);



        drawRect(renderer, layout.total, " ", fg_primary, bg_editor);

        var gy: u16 = 0;
        while (gy < layout.editor.h) : (gy += 1) {
            var gx: u16 = 0;
            while (gx < layout.editor.w) : (gx += 1) {
                if (gy < ui_state.grid.height and gx < ui_state.grid.width) {
                    var cell = ui_state.grid.cells[@as(usize, gy) * @as(usize, ui_state.grid.width) + gx];
                    
                    if (std.meta.eql(cell.bg, ui_state.default_bg) or std.meta.activeTag(cell.bg) == .none) {
                        cell.bg = bg_editor;
                    }
                    if (std.meta.eql(cell.fg, ui_state.default_fg) or std.meta.activeTag(cell.fg) == .none) {
                        cell.fg = fg_primary;
                    }
                    renderer.setCell(layout.editor.x + gx, layout.editor.y + gy, cell);
                } else {
                    renderer.setCell(layout.editor.x + gx, layout.editor.y + gy, Cell{
                        .char = [_]u8{ ' ', 0, 0, 0 }, .len = 1,
                        .fg = ui_state.default_fg, .bg = bg_editor,
                    });
                }
            }
        }

        if (mode_ptr.* == .ide) {
            activity_bar.draw(renderer, layout.activity_bar, .{
                .bg_sidebar = bg_sidebar, .bg_accent = bg_accent,
                .fg_primary = fg_primary, .fg_secondary = fg_secondary, .border_color = border_color,
            });
            if (show_file_tree) {
                if (activity_bar.active_idx == 0) {
                    explorer.draw(renderer, layout.file_tree, .{
                        .bg_sidebar = bg_sidebar, .bg_editor = bg_editor, .bg_accent = bg_accent,
                        .fg_primary = fg_primary, .fg_secondary = fg_secondary, .border_color = border_color, .fg_accent = fg_accent,
                    });
                } else if (activity_bar.active_idx == 1) {
                    search_panel.draw(renderer, layout.file_tree, .{
                        .bg_sidebar = bg_sidebar, .bg_editor = bg_editor, .bg_accent = bg_accent,
                        .fg_primary = fg_primary, .fg_secondary = fg_secondary, .border_color = border_color, .fg_accent = fg_accent,
                    });
                } else if (activity_bar.active_idx == 2) {
                    git_panel.draw(renderer, layout.file_tree, .{
                        .bg_sidebar = bg_sidebar, .bg_editor = bg_editor, .bg_accent = bg_accent,
                        .fg_primary = fg_primary, .fg_secondary = fg_secondary, .border_color = border_color, .fg_accent = fg_accent,
                    });
                } else {
                    drawRect(renderer, layout.file_tree, " ", fg_primary, bg_sidebar);
                }
                var y: u16 = 0;
                while (y < layout.file_tree.h) : (y += 1) {
                    var cell = Cell{ .fg = border_color, .bg = bg_sidebar };
                    cell.setChar("│");
                    renderer.setCell(layout.file_tree.x + layout.file_tree.w - 1, layout.file_tree.y + y, cell);
                }
            }
            drawRect(renderer, layout.tab_bar, " ", fg_secondary, bg_sidebar);
            var tx: u16 = layout.tab_bar.x;
            for (tabs.items, 0..) |tab, i| {
                const is_active = (i == active_tab);
                const tab_w: u16 = @as(u16, @intCast(tab.name.len)) + 8;
                const bg = if (is_active) bg_tab_active else bg_tab_inactive;
                const fg = if (is_active) fg_primary else fg_secondary;
                
                drawRect(renderer, Rect{ .x = tx, .y = layout.tab_bar.y, .w = tab_w, .h = 1 }, " ", fg, bg);
                drawText(renderer, tx + 2, layout.tab_bar.y, tab.name, fg, bg, is_active, false);
                const close_color = if (is_active) Color{ .rgb = .{ .r = 235, .g = 100, .b = 100 } } else fg_secondary;
                drawText(renderer, tx + tab_w - 3, layout.tab_bar.y, "󰅖", close_color, bg, false, false);
                tx += tab_w;
            }
            // Draw + button for new tab
            drawText(renderer, tx + 1, layout.tab_bar.y, "+", fg_secondary, bg_sidebar, true, false);
            
            // Draw Status Bar background
            drawRect(renderer, layout.status_bar, " ", fg_primary, bg_statusbar);
            
            // Draw mode indicator
            drawText(renderer, layout.status_bar.x + 1, layout.status_bar.y, " 󰚌  NORMAL ", fg_statusbar, bg_statusbar, true, false);
            
            // Draw Branch in Status Bar
            const branch_name = git_panel.current_branch orelse "main";
            var status_buf: [128]u8 = undefined;
            const branch_display = std.fmt.bufPrint(&status_buf, "  {s} ", .{branch_name}) catch "  main ";
            drawText(renderer, layout.status_bar.x + 12, layout.status_bar.y, branch_display, fg_statusbar, bg_statusbar, true, false);
            
            // Draw File in Status Bar
            const file_x = 12 + @as(u16, @intCast(branch_display.len)) + 1;
            drawText(renderer, layout.status_bar.x + file_x, layout.status_bar.y, "󰌆  main.zig", fg_statusbar, bg_statusbar, false, false);

            if (layout.panel) |panel| {
                // Draw terminal panel background
                drawRect(renderer, panel, " ", fg_primary, bg_terminal);
                
                var px: u16 = 0;
                while (px < panel.w) : (px += 1) {
                    var cell = Cell{ .fg = bg_accent, .bg = bg_sidebar };
                    cell.setChar("━");
                    renderer.setCell(panel.x + px, panel.y, cell);
                }
                
                // Draw terminal header
                const term_header_fg = if (active_terminal_panel_idx == 0) bg_accent else fg_secondary;
                const debug_header_fg = if (active_terminal_panel_idx == 1) bg_accent else fg_secondary;
                const output_header_fg = if (active_terminal_panel_idx == 2) bg_accent else fg_secondary;
                
                drawText(renderer, panel.x + 2, panel.y, " TERMINAL ", term_header_fg, bg_terminal, active_terminal_panel_idx == 0, false);
                drawText(renderer, panel.x + 13, panel.y, " DEBUG CONSOLE ", debug_header_fg, bg_terminal, active_terminal_panel_idx == 1, false);
                drawText(renderer, panel.x + 30, panel.y, " OUTPUT ", output_header_fg, bg_terminal, active_terminal_panel_idx == 2, false);

                if (panel.h > 1) {
                    var py: u16 = 0;
                    while (py < panel.h - 1) : (py += 1) {
                    px = 0;
                    while (px < panel.w) : (px += 1) {
                        if (active_terminal_panel_idx == 0 and py < ui_term.grid.height and px < ui_term.grid.width) {
                            var cell = ui_term.grid.cells[@as(usize, py) * @as(usize, ui_term.grid.width) + px];
                            if (std.meta.eql(cell.bg, ui_term.default_bg) or std.meta.activeTag(cell.bg) == .none) {
                                cell.bg = bg_terminal;
                            }
                            if (std.meta.eql(cell.fg, ui_term.default_fg) or std.meta.activeTag(cell.fg) == .none) {
                                cell.fg = fg_primary;
                            } else if (std.meta.activeTag(cell.fg) == .rgb) {
                                const r = cell.fg.rgb.r;
                                const g = cell.fg.rgb.g;
                                const b = cell.fg.rgb.b;
                                // If the color is very dark blue, snap it to a highly visible vivid light blue (cyan-ish)
                                if (r < 80 and g < 80 and b > 50) {
                                    cell.fg.rgb.r = 86;
                                    cell.fg.rgb.g = 182;
                                    cell.fg.rgb.b = 194;
                                } else if (r < 60 and g < 60 and b < 60) {
                                    // If it's just very dark (like black on dark background), brighten it
                                    cell.fg.rgb.r = r +| 100;
                                    cell.fg.rgb.g = g +| 100;
                                    cell.fg.rgb.b = b +| 100;
                                }
                            }
                            renderer.setCell(panel.x + px, panel.y + 1 + py, cell);
                        } else if (active_terminal_panel_idx == 1) {
                            // Delay rendering slightly, it will be done below
                        } else if (active_terminal_panel_idx == 2) {
                            // Delay rendering slightly, it will be done below
                        } else {
                            renderer.setCell(panel.x + px, panel.y + 1 + py, Cell{
                                .char = [_]u8{ ' ', 0, 0, 0 }, .len = 1,
                                .fg = fg_primary, .bg = bg_terminal,
                            });
                        }
                    }
                }
                }
                
                if (active_terminal_panel_idx == 1) {
                    const content_rect = Rect{ .x = panel.x, .y = panel.y + 1, .w = panel.w, .h = if (panel.h > 0) @max(1, panel.h - 1) else 1 };
                    debug_console.draw(renderer, content_rect, .{ .fg_primary = fg_primary, .fg_secondary = fg_secondary, .fg_accent = fg_accent, .bg_terminal = bg_terminal });
                } else if (active_terminal_panel_idx == 2) {
                    const content_rect = Rect{ .x = panel.x, .y = panel.y + 1, .w = panel.w, .h = if (panel.h > 0) @max(1, panel.h - 1) else 1 };
                    output_panel.draw(renderer, content_rect, .{ .fg_primary = fg_primary, .fg_secondary = fg_secondary, .fg_accent = fg_accent, .bg_terminal = bg_terminal });
                }
            }
            
            if (ui_state.telescope_rect) |rect| {
                const draw_x = layout.editor.x + rect.x;
                const draw_y = layout.editor.y + rect.y;
                
                const wx = if (draw_x > 0) draw_x - 1 else 0;
                const wy = if (draw_y > 0) draw_y - 1 else 0;
                const shadow_color = Color{ .rgb = .{ .r = 10, .g = 10, .b = 10 } };
                
                // Draw shadow right
                var sy: u16 = 1;
                while (sy <= rect.h + 1) : (sy += 1) {
                    renderer.drawText(wx + rect.w + 2, wy + sy, " ", fg_primary, shadow_color, false, false);
                    renderer.drawText(wx + rect.w + 3, wy + sy, " ", fg_primary, shadow_color, false, false);
                }
                // Draw shadow bottom
                var sx: u16 = 1;
                while (sx <= rect.w + 3) : (sx += 1) {
                    renderer.drawText(wx + sx, wy + rect.h + 2, " ", fg_primary, shadow_color, false, false);
                }
                
                // Top border
                var bw: u16 = 0;
                while (bw < rect.w + 2) : (bw += 1) {
                    renderer.drawText(wx + bw, wy, " ", fg_primary, border_color, false, false);
                    renderer.drawText(wx + bw, wy + rect.h + 1, " ", fg_primary, border_color, false, false);
                }
                // Side borders
                var bh: u16 = 0;
                while (bh < rect.h + 2) : (bh += 1) {
                    renderer.drawText(wx, wy + bh, " ", fg_primary, border_color, false, false);
                    renderer.drawText(wx + rect.w + 1, wy + bh, " ", fg_primary, border_color, false, false);
                }
                
                // Top bar text
                renderer.drawText(wx + 5, wy, " Telescope ", fg_primary, border_color, true, false);
                
                // Red cross
                renderer.drawText(wx + 2, wy, "✖", .{ .rgb = .{ .r = 255, .g = 80, .b = 80 } }, border_color, true, false);
            }
        }
        if (settings_widget.is_open) {
            settings_widget.draw(renderer, renderer.width, renderer.height, .{
                .bg_editor = bg_editor, .bg_sidebar = bg_sidebar, .bg_accent = bg_accent,
                .fg_primary = fg_primary, .fg_secondary = fg_secondary, .border_color = border_color, .fg_accent = fg_accent,
            });
        }
        if (mason_widget.is_open) {
            mason_widget.draw(renderer, renderer.width, renderer.height, .{
                .bg_editor = bg_editor, .bg_sidebar = bg_sidebar, .bg_accent = bg_accent,
                .fg_primary = fg_primary, .fg_secondary = fg_secondary, .border_color = border_color, .fg_accent = fg_accent,
                .fg_comment = fg_secondary,
            });
        }
        if (lazy_widget.is_open) {
            lazy_widget.draw(renderer, renderer.width, renderer.height, .{
                .bg_editor = bg_editor, .bg_sidebar = bg_sidebar, .bg_accent = bg_accent,
                .fg_primary = fg_primary, .fg_secondary = fg_secondary, .border_color = border_color, .fg_accent = fg_accent,
                .fg_comment = fg_secondary,
            });
        }
        if (git_detailed_widget.is_open) {
            git_detailed_widget.draw(renderer, renderer.width, renderer.height, .{
                .bg_editor = bg_editor, .bg_sidebar = bg_sidebar, .bg_accent = bg_accent,
                .fg_primary = fg_primary, .fg_secondary = fg_secondary, .border_color = border_color, .fg_accent = fg_accent,
                .fg_comment = fg_secondary,
            });
        }
        
        if (!settings_widget.is_open and was_settings_open) {
            if (alloc.dupeZ(u8, preview_path)) |p| {
                _ = std.os.linux.unlinkat(std.posix.AT.FDCWD, p, 0);
                alloc.free(p);
            } else |_| {}
        }
        was_settings_open = settings_widget.is_open;

        try renderer.flush();
        const final_cursor_x = if (terminal_focus and active_terminal_panel_idx == 0 and layout.panel != null) panel_info: {
            const panel = layout.panel.?;
            break :panel_info panel.x + ui_term.cursor_x;
        } else layout.editor.x + ui_state.cursor_x;
        const final_cursor_y = if (terminal_focus and active_terminal_panel_idx == 0 and layout.panel != null) panel_info: {
            const panel = layout.panel.?;
            break :panel_info panel.y + 1 + ui_term.cursor_y;
        } else layout.editor.y + ui_state.cursor_y;
        try term.writer().print("\x1b[{d};{d}H\x1b[?25h", .{ final_cursor_y + 1, final_cursor_x + 1 });

        var fds = [4]std.posix.pollfd{
            .{ .fd = term.tty_fd, .events = std.posix.POLL.IN, .revents = 0 },
            .{ .fd = rpc.process.stdout.handle, .events = std.posix.POLL.IN, .revents = 0 },
            .{ .fd = rpc_term.process.stdout.handle, .events = std.posix.POLL.IN, .revents = 0 },
            .{ .fd = sigwinch_read_fd, .events = std.posix.POLL.IN, .revents = 0 },
        };

        const timeout: i32 = if (input.sigwinch_received.load(.monotonic)) 0 else 1000;
        const poll_num = std.posix.poll(&fds, timeout) catch |err| {
            if (err == error.BlockedBySignal) {
                if (input.sigwinch_received.swap(false, .monotonic)) {
                    var ws: posix.winsize = undefined;
                    const rc = posix.system.ioctl(term.tty_fd, posix.T.IOCGWINSZ, @intFromPtr(&ws));
                    if (posix.errno(rc) == .SUCCESS) {
                        try renderer.resize(alloc, ws.col, ws.row);
                        needs_resize = true;
                    }
                }
                continue;
            }
            return err;
        };

        if (ui_state.buf_path_changed) {
            ui_state.buf_path_changed = false;
            if (ui_state.current_buf_path) |p| {
                if (p.len > 0) {
                    if (tabs.items.len == 0) {
                        const basename = std.fs.path.basename(p);
                        if (alloc.dupe(u8, basename)) |new_name| {
                            if (alloc.dupe(u8, p)) |new_path| {
                                tabs.append(.{ .name = new_name, .path = new_path }) catch {};
                                active_tab = 0;
                            } else |_| alloc.free(new_name);
                        } else |_| {}
                    } else if (active_tab < tabs.items.len) {
                        const basename = std.fs.path.basename(p);
                        if (alloc.dupe(u8, basename)) |new_name| {
                            alloc.free(tabs.items[active_tab].name);
                            tabs.items[active_tab].name = new_name;
                        } else |_| {}
                        if (alloc.dupe(u8, p)) |new_path| {
                            if (tabs.items[active_tab].path) |old_p| alloc.free(old_p);
                            tabs.items[active_tab].path = new_path;
                        } else |_| {}
                    }
                    needs_resize = true;
                }
            }
        }

        if (poll_num > 0) {
            if ((fds[3].revents & std.posix.POLL.IN) != 0) {
                var discard: [32]u8 = undefined;
                _ = std.posix.read(sigwinch_read_fd, &discard) catch 0;
            }
            if ((fds[1].revents & std.posix.POLL.IN) != 0) {
                const alive = try processNvimEvents(rpc);
                if (!alive) return;
            }
            if ((fds[2].revents & posix.POLL.IN) != 0) {
                _ = try processNvimEvents(rpc_term);
            }
            
            if (ui_state.toggle_zen_requested) {
                ui_state.toggle_zen_requested = false;
                mode_ptr.* = if (mode_ptr.* == .zen) .ide else .zen;
                if (mode_ptr.* == .zen) {
                    settings_widget.is_open = false;
                    mason_widget.is_open = false;
                    lazy_widget.is_open = false;
                    git_detailed_widget.is_open = false;
                }
                needs_resize = true;
            }
            if (ui_state.toggle_ide_requested) {
                ui_state.toggle_ide_requested = false;
                mode_ptr.* = .ide;
                needs_resize = true;
            }
            if (ui_state.theme_changed) {
                ui_state.theme_changed = false;
                needs_resize = true;
            }

            if (settings_widget.needs_apply) {
                settings_widget.needs_apply = false;
                settings_widget.config.save(preview_path) catch {};
                
                needs_resize = true; // force redraw
                
                if (settings_widget.config.zen) {
                    mode_ptr.* = .zen;
                } else if (settings_widget.config.ide) {
                    mode_ptr.* = .ide;
                }
                
                var cmd_p = try alloc.alloc(Value, 1);
                var cmd_buf: [256]u8 = undefined;
                
                if (std.fmt.bufPrint(&cmd_buf, "colorscheme {s}", .{settings_widget.config.theme})) |cmd_str| {
                    cmd_p[0] = .{ .string = cmd_str };
                    rpc.notify("nvim_command", cmd_p) catch {};
                } else |_| {}
                
                if (std.mem.eql(u8, settings_widget.config.line_numbers, "relative")) {
                    cmd_p[0] = .{ .string = "setglobal relativenumber number" };
                } else if (std.mem.eql(u8, settings_widget.config.line_numbers, "normal")) {
                    cmd_p[0] = .{ .string = "setglobal norelativenumber number" };
                } else {
                    cmd_p[0] = .{ .string = "setglobal norelativenumber nonumber" };
                }
                rpc.notify("nvim_command", cmd_p) catch {};
                
                if (std.fmt.bufPrint(&cmd_buf, "set shiftwidth={d} tabstop={d} {s} {s}", .{
                    settings_widget.config.indent_size,
                    settings_widget.config.indent_size,
                    if (settings_widget.config.use_tabs) @as([]const u8, "noexpandtab") else @as([]const u8, "expandtab"),
                    if (settings_widget.config.wrap) @as([]const u8, "wrap") else @as([]const u8, "nowrap"),
                })) |cmd_str| {
                    cmd_p[0] = .{ .string = cmd_str };
                    rpc.notify("nvim_command", cmd_p) catch {};
                } else |_| {}

                if (settings_widget.config.clip) {
                    cmd_p[0] = .{ .string = "set clipboard=unnamedplus" };
                } else {
                    cmd_p[0] = .{ .string = "set clipboard=" };
                }
                rpc.notify("nvim_command", cmd_p) catch {};

                alloc.free(cmd_p);
            }

            if ((fds[0].revents & posix.POLL.IN) != 0 or input.sigwinch_received.load(.monotonic)) {
                const event = try input.readEvent(term.tty_fd, &seq_buf, alloc);
                switch (event) {
                    .key => |k| {
                        if (k.raw.len == 1 and k.raw[0] == 0x03) return error.QuitApplication;
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
                                    if (layout.total.h > 4 and terminal_panel_height < layout.total.h - 4) {
                                        terminal_panel_height +|= 1;
                                        needs_resize = true;
                                    }
                                }
                                break :get_key "";
                            }
                            if (std.mem.eql(u8, k.raw, "\x1b[1;3B")) { // Alt+Down
                                if (layout.panel != null) {
                                    if (terminal_panel_height > 2) {
                                        terminal_panel_height -= 1;
                                        needs_resize = true;
                                    }
                                }
                                break :get_key "";
                            }
                            if (std.mem.eql(u8, k.raw, "\x1b[1;3C")) { // Alt+Right
                                if (show_file_tree) {
                                    if (layout.total.w > layout.activity_bar.w + 10 and file_tree_width < layout.total.w - layout.activity_bar.w - 10) {
                                        file_tree_width += 1;
                                        needs_resize = true;
                                    }
                                }
                                break :get_key "";
                            }
                            if (std.mem.eql(u8, k.raw, "\x1b[1;3D")) { // Alt+Left
                                if (show_file_tree) {
                                    if (file_tree_width > 5) {
                                        file_tree_width -= 1;
                                        needs_resize = true;
                                    }
                                }
                                break :get_key "";
                            }
                            break :get_key k.raw;
                        };

                        if (nk.len > 0) {
                            if (settings_widget.is_open) {
                                if (settings_widget.handleKey(nk)) {
                                    needs_resize = true;
                                } else if (std.mem.eql(u8, nk, "<Esc>")) {
                                    settings_widget.is_open = false;
                                    needs_resize = true;
                                }
                                continue;
                            }
                            if (mason_widget.is_open) {
                                if (mason_widget.handleKey(nk, rpc)) {
                                    needs_resize = true;
                                }
                                continue;
                            }
                            if (lazy_widget.is_open) {
                                if (lazy_widget.handleKey(nk, rpc)) {
                                    needs_resize = true;
                                }
                                continue;
                            }
                            if (git_detailed_widget.is_open) {
                                if (git_detailed_widget.handleKey(nk)) {
                                    needs_resize = true;
                                }
                                continue;
                            }
                        }

                        var toggle_zen = false;
                        var toggle_explorer = false;
                        var toggle_terminal_panel = false;
                        var new_file = false;
                        
                        if (std.mem.eql(u8, nk, settings_widget.config.keybindings.toggle_terminal)) toggle_terminal_panel = true;
                        if (std.mem.eql(u8, nk, settings_widget.config.keybindings.toggle_explorer)) toggle_explorer = true;
                        if (std.mem.eql(u8, nk, settings_widget.config.keybindings.toggle_zen)) toggle_zen = true;
                        if (std.mem.eql(u8, nk, settings_widget.config.keybindings.new_file)) new_file = true;


                        if (toggle_zen) {
                            mode_ptr.* = if (mode_ptr.* == .ide) .zen else .ide;
                            if (mode_ptr.* == .zen) {
                                settings_widget.is_open = false;
                                mason_widget.is_open = false;
                                lazy_widget.is_open = false;
                                git_detailed_widget.is_open = false;
                            }
                            needs_resize = true;
                        } else if (toggle_explorer) {
                            show_file_tree = !show_file_tree;
                            needs_resize = true;
                            continue;
                        } else if (toggle_terminal_panel) {
                            show_terminal_panel = !show_terminal_panel;
                            terminal_focus = show_terminal_panel;
                            needs_resize = true;
                            continue;
                        } else if (new_file) {
                            var buf: [32]u8 = undefined;
                            const new_name = std.fmt.bufPrint(&buf, "File {d}", .{tabs.items.len + 1}) catch "File";
                            tabs.append(.{
                                .name = alloc.dupe(u8, new_name) catch "error",
                                .path = null,
                            }) catch {};
                            active_tab = if (tabs.items.len > 0) tabs.items.len - 1 else 0;
                            needs_resize = true;
                            
                            var cmd_p = try alloc.alloc(Value, 1);
                            cmd_p[0] = .{ .string = "while #vim.api.nvim_win_get_config(0).relative > 0 do vim.cmd('close') end; vim.cmd('enew')" };
                            var params = try alloc.alloc(Value, 2);
                            defer alloc.free(params);
                            params[0] = cmd_p[0];
                            params[1] = .{ .array = &[_]Value{} };
                            if (rpc.call("nvim_exec_lua", params) catch null) |res| {
                                msgpack.freeValue(res, alloc);
                            }
                            alloc.free(cmd_p);
                            continue;
                        }

                        if (nk.len > 0) {
                            if (show_file_tree and activity_bar.active_idx == 0 and explorer.action_state != .none) {
                                if (explorer.handleKey(nk) catch false) {
                                    needs_resize = true;
                                    continue;
                                }
                            }
                            if (show_file_tree and activity_bar.active_idx == 2 and git_panel.is_focus_commit) {
                                if (git_panel.handleKey(nk) catch false) {
                                    needs_resize = true;
                                    continue;
                                }
                            }
                            var ip = try alloc.alloc(Value, 1);
                            defer alloc.free(ip);
                            ip[0] = .{ .string = nk };
                            (if (terminal_focus) rpc_term else rpc).notify("nvim_input", ip) catch {};
                        }
                    },
                    .paste => |p| {
                        defer alloc.free(p);
                        var params = try alloc.alloc(Value, 3);
                        defer alloc.free(params);
                        params[0] = .{ .string = p };
                        params[1] = .{ .bool = true };
                        params[2] = .{ .integer = -1 };
                        if ((if (terminal_focus) rpc_term else rpc).call("nvim_paste", params) catch null) |res| {
                            msgpack.freeValue(res, alloc);
                        }
                    },
                    .mouse => |m| {
                        lc_x.* = m.col; lc_y.* = m.row;
                        
                        if (mode_ptr.* == .ide) {
                            if (mason_widget.is_open) {
                                if (mason_widget.handleMouse(m, renderer.width, renderer.height, rpc)) {
                                    needs_resize = true;
                                    continue;
                                } else if (m.action == .press) {
                                    mason_widget.is_open = false;
                                    needs_resize = true;
                                    continue;
                                }
                            }
                            if (lazy_widget.is_open) {
                                if (lazy_widget.handleMouse(m, renderer.width, renderer.height)) {
                                    needs_resize = true;
                                    continue;
                                } else if (m.action == .press) {
                                    lazy_widget.is_open = false;
                                    needs_resize = true;
                                }
                            }
                            if (git_detailed_widget.is_open) {
                                if (git_detailed_widget.handleMouse(m, renderer.width, renderer.height)) {
                                    needs_resize = true;
                                    continue;
                                } else if (m.action == .press) {
                                    git_detailed_widget.is_open = false;
                                    needs_resize = true;
                                }
                            }

                            if (m.action == .press) {
                                if (ui_state.telescope_rect) |rect| {
                                    const t_x = layout.editor.x + rect.x;
                                    const t_y = layout.editor.y + rect.y;
                                    const wx = if (t_x > 0) t_x - 1 else 0;
                                    const wy = if (t_y > 0) t_y - 1 else 0;
                                    if (m.row == wy and m.col >= wx + 1 and m.col <= wx + 3) {
                                        var ip = try alloc.alloc(Value, 1);
                                        defer alloc.free(ip);
                                        ip[0] = .{ .string = "<Esc><Esc>" };
                                        rpc.notify("nvim_input", ip) catch {};
                                        ui_state.telescope_rect = null;
                                        needs_resize = true;
                                        continue;
                                    }
                                }

                                if (settings_widget.is_open) {
                                    if (settings_widget.handleMouse(m.col, m.row, renderer.width, renderer.height)) {
                                        needs_resize = true;
                                        if (settings_widget.open_mason) {
                                            settings_widget.open_mason = false;
                                            settings_widget.is_open = false;
                                            mason_widget.is_open = true;
                                            mason_widget.refresh(rpc);
                                        } else if (settings_widget.open_lazy) {
                                            settings_widget.open_lazy = false;
                                            settings_widget.is_open = false;
                                            lazy_widget.is_open = true;
                                            lazy_widget.refresh(rpc);
                                        }
                                    } else {
                                        settings_widget.is_open = false;
                                        needs_resize = true;
                                    }
                                    continue;
                                }
                                if (show_file_tree and m.col >= layout.file_tree.x and m.col < layout.file_tree.x + layout.file_tree.w and activity_bar.active_idx == 0 and m.button == .wheel_up) {
                                    explorer.handleScroll(-1);
                                    needs_resize = true;
                                } else if (show_file_tree and m.col >= layout.file_tree.x and m.col < layout.file_tree.x + layout.file_tree.w and activity_bar.active_idx == 0 and m.button == .wheel_down) {
                                    explorer.handleScroll(1);
                                    needs_resize = true;
                                } else if (show_file_tree and m.col >= layout.file_tree.x and m.col < layout.file_tree.x + layout.file_tree.w and activity_bar.active_idx == 2 and m.button == .wheel_up) {
                                    git_panel.handleScroll(-1);
                                    needs_resize = true;
                                } else if (show_file_tree and m.col >= layout.file_tree.x and m.col < layout.file_tree.x + layout.file_tree.w and activity_bar.active_idx == 2 and m.button == .wheel_down) {
                                    git_panel.handleScroll(1);
                                    needs_resize = true;
                                } else if (show_file_tree and m.col >= layout.file_tree.x + layout.file_tree.w - 2 and m.col <= layout.file_tree.x + layout.file_tree.w) {
                                    is_resizing_sidebar = true;
                                } else if (show_file_tree and m.col >= layout.file_tree.x and m.col < layout.file_tree.x + layout.file_tree.w and m.row >= layout.file_tree.y and m.row < layout.file_tree.y + layout.file_tree.h) {
                                    if (activity_bar.active_idx == 0) {
                                        if (explorer.handleMouse(m.col, m.row, layout.file_tree) catch null) |path| {
                                            openFile(rpc, alloc, path) catch {};
                                            if (tabs.items.len == 0) {
                                                const basename = std.fs.path.basename(path);
                                                tabs.append(.{
                                                    .name = alloc.dupe(u8, basename) catch "error",
                                                    .path = alloc.dupe(u8, path) catch null,
                                                }) catch {};
                                                active_tab = 0;
                                            } else if (active_tab < tabs.items.len) {
                                                const basename = std.fs.path.basename(path);
                                                if (alloc.dupe(u8, basename) catch null) |new_name| {
                                                    alloc.free(tabs.items[active_tab].name);
                                                    tabs.items[active_tab].name = new_name;
                                                }
                                                if (alloc.dupe(u8, path) catch null) |new_path| {
                                                    if (tabs.items[active_tab].path) |p| alloc.free(p);
                                                    tabs.items[active_tab].path = new_path;
                                                }
                                            }
                                        }
                                        needs_resize = true;
                                    } else if (activity_bar.active_idx == 1) {
                                        if (search_panel.handleMouse(m.col, m.row, layout.file_tree)) |cmd| {
                                            if (std.mem.startsWith(u8, cmd, "__CMD__:Telescope")) {
                                                const actual_cmd = cmd[8..];
                                                var cmd_p = try alloc.alloc(Value, 1);
                                                defer alloc.free(cmd_p);
                                                cmd_p[0] = .{ .string = actual_cmd };
                                                rpc.notify("nvim_command", cmd_p) catch {};
                                            }
                                        }
                                        needs_resize = true;
                                    } else if (activity_bar.active_idx == 2) {
                                        if (git_panel.handleMouse(m.col, m.row, layout.file_tree) catch null) |path| {
                                            if (std.mem.startsWith(u8, path, "__CMD__:GitWidget")) {
                                                git_detailed_widget.is_open = true;
                                                git_detailed_widget.refresh();
                                                needs_resize = true;
                                            } else {
                                                openFile(rpc, alloc, path) catch {};
                                                if (tabs.items.len == 0) {
                                                    const basename = std.fs.path.basename(path);
                                                    tabs.append(.{
                                                        .name = alloc.dupe(u8, basename) catch "error",
                                                        .path = alloc.dupe(u8, path) catch null,
                                                    }) catch {};
                                                    active_tab = 0;
                                                } else if (active_tab < tabs.items.len) {
                                                    const basename = std.fs.path.basename(path);
                                                    if (alloc.dupe(u8, basename) catch null) |new_name| {
                                                        alloc.free(tabs.items[active_tab].name);
                                                        tabs.items[active_tab].name = new_name;
                                                    }
                                                    if (alloc.dupe(u8, path) catch null) |new_path| {
                                                        if (tabs.items[active_tab].path) |p| alloc.free(p);
                                                        tabs.items[active_tab].path = new_path;
                                                    }
                                                }
                                            }
                                        }
                                        needs_resize = true;
                                    }
                                } else if (layout.panel != null and m.row == layout.panel.?.y) {
                                    const px = m.col - layout.panel.?.x;
                                    if (px >= 2 and px <= 12) {
                                        active_terminal_panel_idx = 0;
                                        terminal_focus = true;
                                    } else if (px >= 13 and px <= 28) {
                                        active_terminal_panel_idx = 1;
                                        terminal_focus = false;
                                        debug_console.refresh(rpc);
                                    } else if (px >= 30 and px <= 38) {
                                        active_terminal_panel_idx = 2;
                                        terminal_focus = false;
                                        output_panel.refresh(rpc);
                                    } else {
                                        is_resizing_panel = true;
                                    }
                                    needs_resize = true;
                                } else if (layout.panel != null and layout.panel.?.y > 0 and (m.row == layout.panel.?.y - 1 or m.row == layout.panel.?.y + 1)) {
                                    is_resizing_panel = true;
                                } else {
                                    const prev_idx = activity_bar.active_idx;
                                    if (activity_bar.handleMouse(m.col, m.row, layout.activity_bar)) |new_idx| {
                                        if (prev_idx != new_idx) needs_resize = true;
                                        if (new_idx == 99) {
                                            settings_widget.is_open = true;
                                            needs_resize = true;
                                            activity_bar.active_idx = prev_idx; // Revert active idx visually
                                        } else if (show_file_tree and prev_idx == new_idx) {
                                            show_file_tree = false;
                                            needs_resize = true;
                                        } else if (!show_file_tree) {
                                            show_file_tree = true;
                                            needs_resize = true;
                                        }
                                    }
                                    
                                    // Handle tab bar clicks
                                    if (m.row == layout.tab_bar.y) {
                                        var tx: u16 = layout.tab_bar.x;
                                        var clicked_tab = false;
                                        for (tabs.items, 0..) |tab, i| {
                                            const tab_w: u16 = @as(u16, @intCast(tab.name.len)) + 8;
                                            if (m.col >= tx and m.col < tx + tab_w) {
                                                if (m.col >= tx + tab_w - 3 and m.col < tx + tab_w) {
                                                    // Close tab
                                                    if (tabs.items.len > 0) {
                                                        const removed = tabs.orderedRemove(i);
                                                        alloc.free(removed.name);
                                                        if (removed.path) |p| alloc.free(p);
                                                        
                                                        // Actually close the buffer in Neovim
                                                        var cmd_p = try alloc.alloc(Value, 1);
                                                        cmd_p[0] = .{ .string = "bdelete" };
                                                        rpc.notify("nvim_command", cmd_p) catch {};
                                                        alloc.free(cmd_p);
                                                        
                                                        if (tabs.items.len == 0) {
                                                            active_tab = 0;
                                                            var alpha_p = try alloc.alloc(Value, 1);
                                                            alpha_p[0] = .{ .string = "lua _G.vide_alpha_start()" };
                                                            rpc.notify("nvim_command", alpha_p) catch {};
                                                            alloc.free(alpha_p);
                                                        } else if (active_tab >= tabs.items.len) {
                                                            active_tab = tabs.items.len - 1;
                                                        }
                                                        needs_resize = true;
                                                    }
                                                } else {
                                                    active_tab = i;
                                                    needs_resize = true; // force redraw
                                                    if (tabs.items[i].path) |p| {
                                                        openFile(rpc, alloc, p) catch {};
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
                                            const new_name = try std.fmt.bufPrint(&buf, "File {d}", .{tabs.items.len + 1});
                                            try tabs.append(.{
                                                .name = try alloc.dupe(u8, new_name),
                                                .path = null,
                                            });
                                            active_tab = tabs.items.len - 1;
                                            needs_resize = true;
                                            var cmd_p = try alloc.alloc(Value, 1);
                                            cmd_p[0] = .{ .string = "enew" };
                                            rpc.notify("nvim_command", cmd_p) catch {};
                                            alloc.free(cmd_p);
                                        }
                                    }
                                }
                            }
                            
                            if (m.action == .move) {
                                if (is_resizing_sidebar) {
                                    if (m.col > layout.activity_bar.w + 5) {
                                        var new_w = m.col - layout.activity_bar.w;
                                        const max_w = if (layout.total.w > layout.activity_bar.w + 10) layout.total.w - layout.activity_bar.w - 10 else 0;
                                        if (new_w > max_w) {
                                            new_w = max_w;
                                        }
                                        file_tree_width = new_w;
                                        needs_resize = true;
                                    }
                                } else if (is_resizing_panel) {
                                    if (layout.total.h > 2 and m.row < layout.total.h - 2) {
                                        const new_h = layout.total.h - 1 - m.row;
                                        if (new_h >= 2 and new_h < layout.total.h - 2) {
                                            terminal_panel_height = new_h;
                                            needs_resize = true;
                                        }
                                    }
                                }
                            }
                            
                            const was_resizing = is_resizing_sidebar or is_resizing_panel;
                            if (m.action == .release) {
                                is_resizing_sidebar = false;
                                is_resizing_panel = false;
                                needs_resize = true;
                            }
                            if (was_resizing) continue;
                        }

                        if (is_resizing_sidebar or is_resizing_panel) continue;

                        if (layout.panel != null and m.col >= layout.panel.?.x and m.col < layout.panel.?.x + layout.panel.?.w and
                            m.row > layout.panel.?.y and m.row < layout.panel.?.y + layout.panel.?.h)
                        {
                            if (active_terminal_panel_idx == 0) {
                                if (m.action == .press or m.action == .release) terminal_focus = true;
                                if (m.button == .wheel_up or m.button == .wheel_down) {
                                    sendMouseEvent(rpc_term, alloc, m, m.col - layout.panel.?.x, m.row - layout.panel.?.y - 1);
                                }
                            } else if (active_terminal_panel_idx == 1) {
                                if (m.action == .press and m.button == .wheel_up) debug_console.handleScroll(-1);
                                if (m.action == .press and m.button == .wheel_down) debug_console.handleScroll(1);
                                needs_resize = true;
                            } else if (active_terminal_panel_idx == 2) {
                                if (m.action == .press and m.button == .wheel_up) output_panel.handleScroll(-1);
                                if (m.action == .press and m.button == .wheel_down) output_panel.handleScroll(1);
                                needs_resize = true;
                            }
                        } else if (m.col >= layout.editor.x and m.col < layout.editor.x + layout.editor.w and
                                   m.row >= layout.editor.y and m.row < layout.editor.y + layout.editor.h)
                        {
                            if (m.action == .press) terminal_focus = false;
                            sendMouseEvent(rpc, alloc, m, m.col - layout.editor.x, m.row - layout.editor.y);
                        } else {
                            if (m.action == .press) terminal_focus = false;
                        }
                    },
                    .resize => |r| {
                        try renderer.resize(alloc, r.cols, r.rows);
                        needs_resize = true;
                    },
                    .quit => return error.QuitApplication,
                    .none => {},
                }
            }
        }
    }
}
