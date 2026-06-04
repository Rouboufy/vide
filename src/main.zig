const std = @import("std");
const posix = std.posix;
const Terminal = @import("tui/terminal.zig").Terminal;
const Renderer = @import("tui/renderer.zig").Renderer;
const Layout = @import("tui/layout.zig").Layout;
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

const NvimProcess = @import("nvim/process.zig").NvimProcess;
const RpcClient = @import("nvim/rpc.zig").RpcClient;
const ui_protocol = @import("nvim/ui_protocol.zig");
const UiState = ui_protocol.UiState;
const msgpack = @import("nvim/msgpack.zig");
const Value = msgpack.Value;
const App = @import("tui/app.zig").App;
const RpcContext = @import("tui/app.zig").RpcContext;
const nvim_helpers = @import("nvim/helpers.zig");
const views = @import("tui/views.zig");
const events = @import("tui/events.zig");

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

        runNvimSession(initial_file, init, alloc, &term, &renderer, &rpc, &ui_state, &rpc_term, &ui_term, sigwinch_pipe[0]) catch |err| {
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
    ren: *Renderer,
    rpc: *RpcClient,
    ui_state: *UiState,
    rpc_term: *RpcClient,
    ui_term: *UiState,
    sigwinch_read_fd: std.posix.fd_t,
) !void {
    var app = App.init(alloc, term, ren, rpc, rpc_term, ui_state, ui_term);
    defer {
        for (app.tabs.items) |t| {
            alloc.free(t.name);
            if (t.path) |p| alloc.free(p);
        }
        app.tabs.deinit();
    }

    var rpc_ctx_main = RpcContext{ .app = &app, .ui_state = ui_state };
    var rpc_ctx_term = RpcContext{ .app = &app, .ui_state = ui_term };

    rpc.on_notification = nvim_helpers.handleNotification;
    rpc.on_notification_ctx = &rpc_ctx_main;

    rpc_term.on_notification = nvim_helpers.handleNotification;
    rpc_term.on_notification_ctx = &rpc_ctx_term;

    var explorer = Explorer.init(alloc, init.io);
    defer explorer.deinit();
    explorer.refresh() catch {};
    app.explorer = &explorer;

    var git_panel = GitPanel.init(alloc, init.io);
    defer git_panel.deinit();
    git_panel.refresh() catch {};
    app.git_panel = &git_panel;

    var search_panel = SearchPanel.init(alloc);
    defer search_panel.deinit();
    app.search_panel = &search_panel;

    var output_panel = OutputPanel.init(alloc);
    defer output_panel.deinit();
    app.output_panel = &output_panel;

    var debug_console = DebugConsole.init(alloc);
    defer debug_console.deinit();
    app.debug_console = &debug_console;

    const home = init.environ_map.get("HOME") orelse "";
    const settings_path = try std.fs.path.join(alloc, &[_][]const u8{ home, ".local", "share", "vide", "settings.json" });
    const preview_path = try std.fs.path.join(alloc, &[_][]const u8{ home, ".local", "share", "vide", "preview.json" });
    defer alloc.free(settings_path);
    defer alloc.free(preview_path);
    var settings_widget = SettingsWidget.init(alloc, settings_path);
    defer settings_widget.deinit();
    app.settings_widget = &settings_widget;
    
    var mason_widget = MasonWidget.init(alloc);
    defer mason_widget.deinit();
    app.mason_widget = &mason_widget;
    var lazy_widget = LazyWidget.init(alloc);
    defer lazy_widget.deinit();
    app.lazy_widget = &lazy_widget;
    var git_detailed_widget = GitDetailedWidget.init(alloc, init.io);
    defer git_detailed_widget.deinit();
    app.git_detailed_widget = &git_detailed_widget;

    const initial_layout = Layout.compute(ren.width, ren.height, app.mode == .zen, app.show_file_tree, app.file_tree_width, app.root_split);

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

    if (initial_file) |f| {
        try app.tabs.append(.{
            .name = try alloc.dupe(u8, std.fs.path.basename(f)),
            .path = try alloc.dupe(u8, f),
        });
        nvim_helpers.openFile(rpc, alloc, f) catch {};
    } else {
        var params = try alloc.alloc(Value, 2);
        params[0] = .{ .string = @embedFile("nvim/vide_init.lua") };
        params[1] = .{ .array = &[_]Value{} };
        if (rpc.call("nvim_exec_lua", params)) |res| {
            msgpack.freeValue(res, alloc);
        } else |_| {}
        alloc.free(params);
    }

    while (true) {
        var ts: std.posix.timespec = undefined;
        _ = std.posix.system.clock_gettime(std.posix.CLOCK.MONOTONIC, &ts);
        const now = ts.sec;

        if (now - app.last_explorer_refresh >= 2) {
            app.last_explorer_refresh = now;
            if (app.explorer.refreshStatus(rpc)) {
                app.needs_resize = true; // force redraw
            }
            if (app.activity_bar.active_idx == 2) {
                app.git_panel.refresh() catch {};
                app.needs_resize = true;
            }
        }

        const cols = ren.width;
        const rows = ren.height;
        const layout = Layout.compute(cols, rows, app.mode == .zen, app.show_file_tree, app.file_tree_width, app.root_split);

        if (app.needs_resize) {
            app.needs_resize = false;
            var rp = try alloc.alloc(Value, 2);
            defer alloc.free(rp);
            rp[0] = .{ .integer = @max(1, layout.editor.w) };
            rp[1] = .{ .integer = @max(1, layout.editor.h) };
            rpc.notify("nvim_ui_try_resize", rp) catch {};
            if (layout.panel) |panel| {
                var tp = try alloc.alloc(Value, 2);
                defer alloc.free(tp);
                tp[0] = .{ .integer = @max(1, panel.w) };
                tp[1] = .{ .integer = if (panel.h > 0) @max(1, panel.h - 1) else 1 };
                rpc_term.notify("nvim_ui_try_resize", tp) catch {};
            }
        }

        const nvim_alive = try nvim_helpers.processNvimEvents(rpc);
        if (!nvim_alive) return;
        _ = try nvim_helpers.processNvimEvents(rpc_term);

        views.drawWorkspace(&app, layout);

        if (!app.settings_widget.is_open and app.was_settings_open) {
            if (alloc.dupeZ(u8, preview_path)) |p| {
                _ = std.os.linux.unlinkat(std.posix.AT.FDCWD, p, 0);
                alloc.free(p);
            } else |_| {}
        }
        app.was_settings_open = app.settings_widget.is_open;

        try ren.flush();
        const final_cursor_x = if (app.terminal_focus and app.active_terminal_panel_idx == 0 and layout.panel != null) panel_info: {
            const panel = layout.panel.?;
            break :panel_info panel.x + ui_term.cursor_x;
        } else layout.editor.x + ui_state.cursor_x;
        const final_cursor_y = if (app.terminal_focus and app.active_terminal_panel_idx == 0 and layout.panel != null) panel_info: {
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
                        try ren.resize(alloc, ws.col, ws.row);
                        app.needs_resize = true;
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
                    if (app.tabs.items.len == 0) {
                        const basename = std.fs.path.basename(p);
                        if (alloc.dupe(u8, basename)) |new_name| {
                            if (alloc.dupe(u8, p)) |new_path| {
                                app.tabs.append(.{ .name = new_name, .path = new_path }) catch {};
                                app.active_tab = 0;
                            } else |_| alloc.free(new_name);
                        } else |_| {}
                    } else if (app.active_tab < app.tabs.items.len) {
                        const basename = std.fs.path.basename(p);
                        if (alloc.dupe(u8, basename)) |new_name| {
                            alloc.free(app.tabs.items[app.active_tab].name);
                            app.tabs.items[app.active_tab].name = new_name;
                        } else |_| {}
                        if (alloc.dupe(u8, p)) |new_path| {
                            if (app.tabs.items[app.active_tab].path) |old_p| alloc.free(old_p);
                            app.tabs.items[app.active_tab].path = new_path;
                        } else |_| {}
                    }
                    app.needs_resize = true;
                }
            }
        }

        if (poll_num > 0) {
            if ((fds[3].revents & std.posix.POLL.IN) != 0) {
                var discard: [32]u8 = undefined;
                _ = std.posix.read(sigwinch_read_fd, &discard) catch 0;
            }
            if ((fds[1].revents & (std.posix.POLL.IN | std.posix.POLL.HUP | std.posix.POLL.ERR)) != 0) {
                const alive = try nvim_helpers.processNvimEvents(rpc);
                if (!alive) return;
            }
            if ((fds[2].revents & (std.posix.POLL.IN | std.posix.POLL.HUP | std.posix.POLL.ERR)) != 0) {
                const alive_term = try nvim_helpers.processNvimEvents(rpc_term);
                if (!alive_term) return;
            }
            
            if (ui_state.toggle_zen_requested) {
                ui_state.toggle_zen_requested = false;
                app.mode = if (app.mode == .zen) .ide else .zen;
                if (app.mode == .zen) {
                    app.settings_widget.is_open = false;
                    app.mason_widget.is_open = false;
                    app.lazy_widget.is_open = false;
                    app.git_detailed_widget.is_open = false;
                }
                app.needs_resize = true;
            }
            if (ui_state.toggle_ide_requested) {
                ui_state.toggle_ide_requested = false;
                app.mode = .ide;
                app.needs_resize = true;
            }
            if (ui_state.theme_changed) {
                ui_state.theme_changed = false;
                app.needs_resize = true;
            }

            if (app.settings_widget.needs_apply) {
                app.settings_widget.needs_apply = false;
                app.settings_widget.config.save(preview_path) catch {};
                
                app.needs_resize = true; // force redraw
                
                if (app.settings_widget.config.zen) {
                    app.mode = .zen;
                } else if (app.settings_widget.config.ide) {
                    app.mode = .ide;
                }
                
                var cmd_p = try alloc.alloc(Value, 1);
                var cmd_buf: [256]u8 = undefined;
                
                if (std.fmt.bufPrint(&cmd_buf, "colorscheme {s}", .{app.settings_widget.config.theme})) |cmd_str| {
                    cmd_p[0] = .{ .string = cmd_str };
                    rpc.notify("nvim_command", cmd_p) catch {};
                } else |_| {}
                
                if (std.mem.eql(u8, app.settings_widget.config.line_numbers, "relative")) {
                    cmd_p[0] = .{ .string = "setglobal relativenumber number" };
                } else if (std.mem.eql(u8, app.settings_widget.config.line_numbers, "normal")) {
                    cmd_p[0] = .{ .string = "setglobal norelativenumber number" };
                } else {
                    cmd_p[0] = .{ .string = "setglobal norelativenumber nonumber" };
                }
                rpc.notify("nvim_command", cmd_p) catch {};
                
                if (std.fmt.bufPrint(&cmd_buf, "set shiftwidth={d} tabstop={d} {s} {s}", .{
                    app.settings_widget.config.indent_size,
                    app.settings_widget.config.indent_size,
                    if (app.settings_widget.config.use_tabs) @as([]const u8, "noexpandtab") else @as([]const u8, "expandtab"),
                    if (app.settings_widget.config.wrap) @as([]const u8, "wrap") else @as([]const u8, "nowrap"),
                })) |cmd_str| {
                    cmd_p[0] = .{ .string = cmd_str };
                    rpc.notify("nvim_command", cmd_p) catch {};
                } else |_| {}

                if (app.settings_widget.config.clip) {
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
                        _ = try events.handleKey(&app, k, layout);
                    },
                    .paste => |p| {
                        defer alloc.free(p);
                        var params = try alloc.alloc(Value, 3);
                        defer alloc.free(params);
                        params[0] = .{ .string = p };
                        params[1] = .{ .bool = true };
                        params[2] = .{ .integer = -1 };
                        if ((if (app.terminal_focus) rpc_term else rpc).call("nvim_paste", params) catch null) |res| {
                            msgpack.freeValue(res, alloc);
                        }
                    },
                    .mouse => |m| {
                        try events.handleMouse(&app, m, layout);
                    },
                    .resize => |r| {
                        try ren.resize(alloc, r.cols, r.rows);
                        app.needs_resize = true;
                    },
                    .quit => return error.QuitApplication,
                    .none => {},
                }
            }
        }
    }
}
