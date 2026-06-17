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
const ExtensionShop = @import("tui/widgets/extension_shop.zig").ExtensionShop;

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
var log_path: ?[]const u8 = null;

pub fn log(
    comptime message_level: std.log.Level,
    comptime scope: @TypeOf(.default),
    comptime format: []const u8,
    args: anytype,
) void {
    const path = log_path orelse return;
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    
    const path_z = alloc.dupeSentinel(u8, path, 0) catch return;
    const fd = std.posix.openatZ(std.posix.AT.FDCWD, path_z, .{ .ACCMODE = .WRONLY, .CREAT = true, .APPEND = true }, 0o644) catch return;
    defer _ = std.os.linux.close(fd);

    var buf = std.ArrayList(u8).init(alloc);
    defer buf.deinit();
    var writer = buf.writer();

    const level_str = switch (message_level) {
        .err => "ERROR",
        .warn => "WARN",
        .info => "INFO",
        .debug => "DEBUG",
    };
    
    if (scope == .default) {
        writer.print("[{s}] ", .{level_str}) catch return;
    } else {
        writer.print("[{s}] ({s}) ", .{level_str, @tagName(scope)}) catch return;
    }
    writer.print(format, args) catch return;
    writer.print("\n", .{}) catch return;

    const items = buf.items;
    var written: usize = 0;
    while (written < items.len) {
        const sub = items[written..];
        const rc = std.posix.system.write(fd, sub.ptr, sub.len);
        switch (std.posix.errno(rc)) {
            .SUCCESS => written += @as(usize, @intCast(rc)),
            .INTR => continue,
            else => return,
        }
    }
}

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
    const home = init.environ_map.get("HOME") orelse "";
    
    // Set up logging
    const log_dir = try std.fs.path.join(alloc, &[_][]const u8{ home, ".local", "share", "vide" });
    defer alloc.free(log_dir);
    std.Io.Dir.cwd().createDir(init.io, log_dir, .default_dir) catch {};
    log_path = try std.fs.path.join(alloc, &[_][]const u8{ log_dir, "vide.log" });
    defer {
        if (log_path) |p| {
            alloc.free(p);
            log_path = null;
        }
    }

    // Write store search helper script
    {
        const script_path = try std.fs.path.join(alloc, &[_][]const u8{ log_dir, "store_search.py" });
        defer alloc.free(script_path);
        const script_content = @embedFile("nvim/store_search.py");
        if (std.posix.openat(std.posix.AT.FDCWD, script_path, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o755)) |fd| {
            defer _ = std.posix.system.close(fd);
            var written: usize = 0;
            while (written < script_content.len) {
                const sub = script_content[written..];
                const rc = std.posix.system.write(fd, sub.ptr, sub.len);
                switch (std.posix.errno(rc)) {
                    .SUCCESS => written += @as(usize, @intCast(rc)),
                    .INTR => continue,
                    else => break,
                }
            }
        } else |_| {}
    }

    const session_path = try std.fs.path.join(alloc, &[_][]const u8{ home, ".local", "share", "vide", "vide_session.vim" });
    defer alloc.free(session_path);
    const handoff_path = try std.fs.path.join(alloc, &[_][]const u8{ home, ".local", "share", "vide", "vide_handoff_init.lua" });
    defer alloc.free(handoff_path);

    var term = try Terminal.init();
    defer term.deinit();
    global_term = &term;

    var sa = std.posix.Sigaction{
        .handler = .{ .handler = input.handleSigwinch },
        .mask = std.mem.zeroes(std.posix.sigset_t),
        .flags = 0,
    };
    std.posix.sigaction(std.posix.SIG.WINCH, &sa, null);

    var sigwinch_pipe = try std.posix.pipe();
    const flags_0 = std.posix.fcntl(sigwinch_pipe[0], std.posix.F.GETFL, 0) catch 0;
    _ = std.posix.fcntl(sigwinch_pipe[0], std.posix.F.SETFL, flags_0 | @as(usize, @as(u32, @bitCast(std.posix.O{ .NONBLOCK = true })))) catch 0;
    input.sigwinch_pipe_write_fd = sigwinch_pipe[1];

    const size = try term.getSize();
    var renderer = try Renderer.init(alloc, size[0], size[1], term.writer());
    defer renderer.deinit(alloc);

    var is_resuming = false;
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

        if (is_resuming) {
            const src_cmd_str = try std.fmt.allocPrint(alloc, "silent! source {s}", .{session_path});
            defer alloc.free(src_cmd_str);
            var src_cmd = [_]Value{.{ .string = src_cmd_str }};
            rpc.notify("nvim_command", &src_cmd) catch |err| {
                std.log.err("Failed to restore session: {}", .{err});
            };
            // Optional: wait a moment for the session to load
        }

        runNvimSession(if (is_resuming) null else initial_file, init, alloc, &term, &renderer, &rpc, &ui_state, &rpc_term, &ui_term, sigwinch_pipe[0], session_path, handoff_path) catch |err| {
            if (err == error.EndOfStream) continue :app_loop;
            if (err == error.QuitApplication) break :app_loop;
            if (err == error.ReloadApplication) {
                var wa_cmd = [_]Value{.{ .string = "silent! wa" }};
                _ = rpc.call("nvim_command", &wa_cmd) catch {};
                
                const mks_cmd_str = std.fmt.allocPrint(alloc, "mksession! {s}", .{session_path}) catch "/tmp/vide_session.vim";
                defer if (!std.mem.eql(u8, mks_cmd_str, "/tmp/vide_session.vim")) alloc.free(mks_cmd_str);
                var mks_cmd = [_]Value{.{ .string = mks_cmd_str }};
                _ = rpc.call("nvim_command", &mks_cmd) catch {};

                for (renderer.prev) |*cell| {
                    cell.char[0] = ' ';
                    cell.len = 1;
                    cell.fg = .none;
                    cell.bg = .none;
                }
                is_resuming = true;
                continue :app_loop;
            }
            if (err == error.ZenModeHandoff) {
                term.deinit();
                // Launch nvim with --clean + our handoff init (same plugins as vide)
                // and restore the saved session
                const cmd_arg = try std.fmt.allocPrint(alloc, "luafile {s}", .{handoff_path});
                defer alloc.free(cmd_arg);
                const argv = [_][]const u8{
                    "nvim",
                    "--clean",
                    "--cmd", cmd_arg,
                    "-S", session_path,
                };
                if (std.process.spawn(init.io, .{ .argv = &argv, .stdin = .inherit, .stdout = .inherit, .stderr = .inherit })) |c| {
                    var child = c;
                    _ = child.wait(init.io) catch |wait_err| {
                        std.log.err("Failed to wait for zen mode nvim process: {}", .{wait_err});
                    };
                } else |spawn_err| {
                    std.log.err("Failed to spawn zen mode nvim: {}", .{spawn_err});
                }
                
                term = try Terminal.init();
                renderer.writer = term.writer();
                for (renderer.prev) |*cell| {
                    cell.char[0] = ' ';
                    cell.len = 1;
                    cell.fg = .none;
                    cell.bg = .none;
                }
                is_resuming = true;
                continue :app_loop;
            }
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
    session_path: []const u8,
    handoff_path: []const u8,
) !void {
    var app = App.init(alloc, term, ren, rpc, rpc_term, ui_state, ui_term);
    defer {
        for (app.tabs.items) |t| {
            alloc.free(t.name);
            if (t.path) |p| alloc.free(p);
        }
        app.tabs.deinit();
        app.deinit();
    }

    var rpc_ctx_main = RpcContext{ .app = &app, .ui_state = ui_state };
    var rpc_ctx_term = RpcContext{ .app = &app, .ui_state = ui_term };

    rpc.on_notification = nvim_helpers.handleNotification;
    rpc.on_notification_ctx = &rpc_ctx_main;

    rpc_term.on_notification = nvim_helpers.handleNotification;
    rpc_term.on_notification_ctx = &rpc_ctx_term;

    var explorer = Explorer.init(alloc, init.io);
    defer explorer.deinit();
    explorer.refresh() catch |err| {
        std.log.err("Explorer initial refresh failed: {}", .{err});
    };
    app.explorer = &explorer;

    var git_panel = GitPanel.init(alloc, init.io);
    defer git_panel.deinit();
    git_panel.refresh() catch |err| {
        std.log.err("Git panel initial refresh failed: {}", .{err});
    };
    app.git_panel = &git_panel;

    var search_panel = SearchPanel.init(alloc);
    defer search_panel.deinit();
    app.search_panel = &search_panel;

    const home = init.environ_map.get("HOME") orelse "";
    var extension_shop = ExtensionShop.init(alloc, init.io, home);
    defer extension_shop.deinit();
    app.extension_shop = &extension_shop;

    var ai_panel = @import("tui/widgets/ai_panel.zig").AiPanel.init(alloc);
    defer ai_panel.deinit();
    app.ai_panel = &ai_panel;

    var output_panel = OutputPanel.init(alloc);
    defer output_panel.deinit();
    app.output_panel = &output_panel;

    var debug_console = DebugConsole.init(alloc);
    defer debug_console.deinit();
    app.debug_console = &debug_console;

    const settings_path = try std.fs.path.join(alloc, &[_][]const u8{ home, ".local", "share", "vide", "settings.json" });
    const preview_path = try std.fs.path.join(alloc, &[_][]const u8{ home, ".local", "share", "vide", "preview.json" });
    defer alloc.free(settings_path);
    defer alloc.free(preview_path);
    var settings_widget = SettingsWidget.init(alloc, settings_path, init.io, home);
    const term_env = init.environ_map.get("TERM") orelse "";
    const is_linux_console = std.mem.eql(u8, term_env, "linux");
    if (is_linux_console) {
        settings_widget.config.nerd_fonts = false;
    }
    settings_widget.refreshThemes(rpc);
    defer settings_widget.deinit();
    app.settings_widget = &settings_widget;
    
    if (std.mem.eql(u8, settings_widget.config.mode, "zen")) {
        app.mode = .zen;
    } else if (std.mem.eql(u8, settings_widget.config.mode, "ide")) {
        app.mode = .ide;
    } else {
        app.mode = .normal;
    }
    app.prev_mode = if (app.mode == .zen) .normal else app.mode;
    
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

    var opt_kvs = try alloc.alloc(Value.KV, 4);
    defer alloc.free(opt_kvs);
    opt_kvs[0] = .{ .key = .{ .string = "rgb" }, .value = .{ .bool = true } };
    opt_kvs[1] = .{ .key = .{ .string = "ext_linegrid" }, .value = .{ .bool = true } };
    opt_kvs[2] = .{ .key = .{ .string = "ext_multigrid" }, .value = .{ .bool = true } };
    opt_kvs[3] = .{ .key = .{ .string = "ext_hlstate" }, .value = .{ .bool = true } };

    var attach_params = try alloc.alloc(Value, 3);
    defer alloc.free(attach_params);
    attach_params[0] = .{ .integer = initial_layout.editor.w };
    attach_params[1] = .{ .integer = initial_layout.editor.h };
    attach_params[2] = .{ .map = opt_kvs };

    const attach_result = try rpc.call("nvim_ui_attach", attach_params);
    msgpack.freeValue(attach_result, alloc);

    var term_opt_kvs = try alloc.alloc(Value.KV, 3);
    defer alloc.free(term_opt_kvs);
    term_opt_kvs[0] = .{ .key = .{ .string = "rgb" }, .value = .{ .bool = true } };
    term_opt_kvs[1] = .{ .key = .{ .string = "ext_linegrid" }, .value = .{ .bool = true } };
    term_opt_kvs[2] = .{ .key = .{ .string = "ext_multigrid" }, .value = .{ .bool = false } };

    var term_attach_params = try alloc.alloc(Value, 3);
    defer alloc.free(term_attach_params);
    term_attach_params[0] = .{ .integer = if (initial_layout.panel) |p| p.w else 80 };
    term_attach_params[1] = .{ .integer = if (initial_layout.panel) |p| (if (p.h > 0) @max(1, p.h - 1) else 1) else 7 };
    term_attach_params[2] = .{ .map = term_opt_kvs };
    const term_attach_result = try rpc_term.call("nvim_ui_attach", term_attach_params);
    msgpack.freeValue(term_attach_result, alloc);

    {
        var cp = try alloc.alloc(Value, 1);
        defer alloc.free(cp);
        
        cp[0] = .{ .string = "set laststatus=0" };
        const r1 = try rpc_term.call("nvim_command", cp);
        msgpack.freeValue(r1, alloc);

        // Set editor laststatus based on mode: show in zen/normal, hide in IDE
        cp[0] = .{ .string = if (app.mode == .ide) "set laststatus=0" else "set laststatus=2" };
        const r_ls = try rpc.call("nvim_command", cp);
        msgpack.freeValue(r_ls, alloc);

        cp[0] = .{ .string = "autocmd BufEnter * call rpcnotify(1, 'vide_buf_enter', expand('%:p'))" };
        const r_au = try rpc.call("nvim_command", cp);
        msgpack.freeValue(r_au, alloc);

        cp[0] = .{ .string = "autocmd BufWritePost * let b:vide_session_saved = 1" };
        const r_au2 = try rpc.call("nvim_command", cp);
        msgpack.freeValue(r_au2, alloc);

        cp[0] = .{ .string = "set shortmess+=I" };
        const r_sm = try rpc.call("nvim_command", cp);
        msgpack.freeValue(r_sm, alloc);
    }

    var seq_buf: [4096]u8 = undefined;

    // Load vide_init.lua always on both editor and terminal instances
    {
        var params = try alloc.alloc(Value, 2);
        params[0] = .{ .string = @embedFile("nvim/vide_init.lua") };
        params[1] = .{ .array = &[_]Value{} };
        if (rpc.call("nvim_exec_lua", params)) |res| {
            msgpack.freeValue(res, alloc);
        } else |_| {}
        alloc.free(params);
    }
    {
        var params = try alloc.alloc(Value, 2);
        params[0] = .{ .string = "vim.g.vide_is_terminal = true" };
        params[1] = .{ .array = &[_]Value{} };
        if (rpc_term.call("nvim_exec_lua", params)) |res| {
            msgpack.freeValue(res, alloc);
        } else |_| {}
        alloc.free(params);
    }
    {
        var params = try alloc.alloc(Value, 2);
        params[0] = .{ .string = @embedFile("nvim/vide_init.lua") };
        params[1] = .{ .array = &[_]Value{} };
        if (rpc_term.call("nvim_exec_lua", params)) |res| {
            msgpack.freeValue(res, alloc);
        } else |_| {}
        alloc.free(params);
    }

    {
        var cp = try alloc.alloc(Value, 1);
        defer alloc.free(cp);
        cp[0] = .{ .string = "terminal" };
        try rpc_term.notify("nvim_command", cp);

        cp[0] = .{ .string = "startinsert" };
        try rpc_term.notify("nvim_command", cp);
    }

    if (initial_file) |f| {
        try app.tabs.append(.{
            .name = try alloc.dupe(u8, std.fs.path.basename(f)),
            .path = try alloc.dupe(u8, f),
        });
        nvim_helpers.openFile(rpc, alloc, f) catch {};
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
        if (!nvim_alive) {
            return error.QuitApplication;
        }
        _ = try nvim_helpers.processNvimEvents(rpc_term);

        views.drawWorkspace(&app, layout);

        if (!app.settings_widget.is_open and app.was_settings_open) {
            if (alloc.dupeZ(u8, preview_path)) |p| {
                std.posix.unlinkatZ(std.posix.AT.FDCWD, p, 0) catch {};
                alloc.free(p);
            } else |_| {}
        }
        app.was_settings_open = app.settings_widget.is_open;

        try ren.flush();
        const cursor_pos = ui_state.cursorScreenPos();
        const final_cursor_x = if (app.terminal_focus and app.active_terminal_panel_idx == 0 and layout.panel != null) panel_info: {
            const panel = layout.panel.?;
            break :panel_info panel.x + ui_term.cursor_x;
        } else @as(u16, @intCast(@max(0, @as(i32, @intCast(layout.editor.x)) + cursor_pos.x)));
        const final_cursor_y = if (app.terminal_focus and app.active_terminal_panel_idx == 0 and layout.panel != null) panel_info: {
            const panel = layout.panel.?;
            break :panel_info panel.y + 1 + ui_term.cursor_y;
        } else @as(u16, @intCast(@max(0, @as(i32, @intCast(layout.editor.y)) + cursor_pos.y)));
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
                if (!alive) {
                    return error.QuitApplication;
                }
            }
            if ((fds[2].revents & (std.posix.POLL.IN | std.posix.POLL.HUP | std.posix.POLL.ERR)) != 0) {
                const alive_term = try nvim_helpers.processNvimEvents(rpc_term);
                if (!alive_term) {
                    if (app.quit_requested) return error.QuitApplication;
                    return;
                }
            }
            
            if (ui_state.toggle_zen_requested) {
                ui_state.toggle_zen_requested = false;
                if (app.settings_widget.config.zen_handoff) {
                    var wa_cmd = [_]Value{.{ .string = "silent! wa" }};
                    _ = rpc.call("nvim_command", &wa_cmd) catch {};

                    const mks_cmd_str = try std.fmt.allocPrint(alloc, "mksession! {s}", .{session_path});
                    defer alloc.free(mks_cmd_str);
                    var mks_cmd = [_]Value{.{ .string = mks_cmd_str }};
                    _ = rpc.call("nvim_command", &mks_cmd) catch {};

                    // Write handoff init with same plugins + retoggle keybind
                    const zen_key = app.settings_widget.config.keybindings.toggle_zen;
                    const vide_init_lua = @embedFile("nvim/vide_init.lua");
                    const handoff_buf = try alloc.alloc(u8, vide_init_lua.len + session_path.len + 512);
                    defer alloc.free(handoff_buf);
                    const handoff_script = std.fmt.bufPrint(handoff_buf,
                        "-- vide handoff\n{s}\nvim.schedule(function()\n" ++
                        "  local function back() vim.cmd('silent! wa') vim.cmd('mksession! {s}') vim.cmd('qa') end\n" ++
                        "  vim.keymap.set({{'n','v','i','t'}}, '{s}', back, {{silent=true}})\nend)\n",
                        .{ vide_init_lua, session_path, zen_key }) catch vide_init_lua;
                    const path = handoff_path;
                    if (std.posix.openat(std.posix.AT.FDCWD, path, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o600)) |fd| {
                        defer _ = std.posix.system.close(fd);

                        var written: usize = 0;
                        while (written < handoff_script.len) {
                            const sub = handoff_script[written..];
                            const rc = std.posix.system.write(fd, sub.ptr, sub.len);
                            switch (std.posix.errno(rc)) {
                                .SUCCESS => written += @as(usize, @intCast(rc)),
                                .INTR => continue,
                                else => break,
                            }
                        }
                    } else |_| {}

                    return error.ZenModeHandoff;
                } else {
                    app.mode = .zen;
                    app.prev_mode = .zen;
                    app.settings_widget.config.zen = true;
                    app.settings_widget.config.ide = false;
                    app.settings_widget.allocator.free(app.settings_widget.config.mode);
                    app.settings_widget.config.mode = try app.settings_widget.allocator.dupe(u8, "zen");
                    
                    var cmd_p = [_]Value{.{ .string = "set laststatus=3" }};
                    _ = rpc.call("nvim_command", &cmd_p) catch {};
                    cmd_p[0] = .{ .string = "lua vim.g.vide_zen_mode = true; vim.g.vide_ide_mode = false; _G.vide_disable_ide_mode(); if _G.vide_update_dashboard_keys then _G.vide_update_dashboard_keys() end; pcall(function() require('alpha').redraw() end)" };
                    _ = rpc.call("nvim_command", &cmd_p) catch {};
                }
            }
            if (ui_state.toggle_ide_requested) {
                ui_state.toggle_ide_requested = false;
                app.mode = .ide;
                app.prev_mode = .ide;
                app.settings_widget.config.zen = false;
                app.settings_widget.config.ide = true;
                app.settings_widget.allocator.free(app.settings_widget.config.mode);
                app.settings_widget.config.mode = try app.settings_widget.allocator.dupe(u8, "ide");
                // Hide Neovim statusline in IDE mode
                {
                    var ls_p = try alloc.alloc(Value, 1);
                    ls_p[0] = .{ .string = "set laststatus=0" };
                    rpc.notify("nvim_command", ls_p) catch {};
                    alloc.free(ls_p);
                }
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
                
                if (std.mem.eql(u8, app.settings_widget.config.mode, "zen")) {
                    app.mode = .zen;
                } else if (std.mem.eql(u8, app.settings_widget.config.mode, "ide")) {
                    app.mode = .ide;
                } else {
                    app.mode = .normal;
                }
                if (app.mode != .zen) {
                    app.prev_mode = app.mode;
                }
                
                var cmd_p = try alloc.alloc(Value, 1);
                
                if (app.mode == .zen) {
                    cmd_p[0] = .{ .string = "lua vim.g.vide_zen_mode = true; vim.g.vide_ide_mode = false; _G.vide_disable_ide_mode(); if _G.vide_update_dashboard_keys then _G.vide_update_dashboard_keys() end; pcall(function() require('alpha').redraw() end)" };
                } else if (app.mode == .ide) {
                    cmd_p[0] = .{ .string = "lua vim.g.vide_zen_mode = false; vim.g.vide_ide_mode = true; _G.vide_enable_ide_mode(); if _G.vide_update_dashboard_keys then _G.vide_update_dashboard_keys() end; pcall(function() require('alpha').redraw() end)" };
                } else {
                    cmd_p[0] = .{ .string = "lua vim.g.vide_zen_mode = false; vim.g.vide_ide_mode = false; _G.vide_disable_ide_mode(); if _G.vide_update_dashboard_keys then _G.vide_update_dashboard_keys() end; pcall(function() require('alpha').redraw() end)" };
                }
                rpc.notify("nvim_command", cmd_p) catch {};

                // Toggle Neovim statusline: show in zen/normal, hide in IDE
                cmd_p[0] = .{ .string = if (app.mode == .ide) "set laststatus=0" else "set laststatus=2" };
                rpc.notify("nvim_command", cmd_p) catch {};

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

                if (std.fmt.bufPrint(&cmd_buf, "lua vim.g.vide_autocomplete_enabled = {s}", .{if (app.settings_widget.config.autocomplete) @as([]const u8, "true") else @as([]const u8, "false")})) |cmd_str| {
                    cmd_p[0] = .{ .string = cmd_str };
                    rpc.notify("nvim_command", cmd_p) catch {};
                } else |_| {}

                if (std.fmt.bufPrint(&cmd_buf, "lua vim.g.vide_nerd_fonts = {s}", .{if (app.settings_widget.config.nerd_fonts) @as([]const u8, "true") else @as([]const u8, "false")})) |cmd_str| {
                    cmd_p[0] = .{ .string = cmd_str };
                    rpc.notify("nvim_command", cmd_p) catch {};
                } else |_| {}

                if (app.settings_widget.config.autoindent) {
                    cmd_p[0] = .{ .string = "setglobal autoindent" };
                } else {
                    cmd_p[0] = .{ .string = "setglobal noautoindent" };
                }
                rpc.notify("nvim_command", cmd_p) catch {};

                alloc.free(cmd_p);
            }

            if ((fds[0].revents & posix.POLL.IN) != 0 or input.sigwinch_received.load(.monotonic)) {
                const event = try input.readEvent(term.tty_fd, &seq_buf, alloc);
                switch (event) {
                    .key => |k| {
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
