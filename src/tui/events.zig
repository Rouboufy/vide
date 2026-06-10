const std = @import("std");
const app = @import("app.zig");
const App = app.App;
const input = @import("input.zig");
const nvim_helpers = @import("../nvim/helpers.zig");
const Value = @import("../nvim/msgpack.zig").Value;
const Layout = @import("layout.zig").Layout;
const settings = @import("widgets/settings.zig");

pub fn handleKey(a: *App, k: input.KeyEvent, layout: Layout) !bool {
    if (a.terminal_focus) {
        if (std.mem.eql(u8, k.raw, "\x1bv") or std.mem.eql(u8, k.raw, "\x1c")) { // Alt+v or Ctrl+\ -> Vertical Split
            var cmd_p = try a.allocator.alloc(Value, 1);
            defer a.allocator.free(cmd_p);
            cmd_p[0] = .{ .string = "vnew | terminal" };
            var res = try a.rpc_term.call("nvim_command", cmd_p);
            @import("../nvim/msgpack.zig").freeValue(res, a.allocator);
            cmd_p[0] = .{ .string = "startinsert" };
            res = try a.rpc_term.call("nvim_command", cmd_p);
            @import("../nvim/msgpack.zig").freeValue(res, a.allocator);
            a.terminal_win_count += 1;
            a.needs_resize = true;
            return true;
        }
        if (std.mem.eql(u8, k.raw, "\x1bs")) { // Alt+s -> Horizontal Split
            var cmd_p = try a.allocator.alloc(Value, 1);
            defer a.allocator.free(cmd_p);
            cmd_p[0] = .{ .string = "new | terminal" };
            var res = try a.rpc_term.call("nvim_command", cmd_p);
            @import("../nvim/msgpack.zig").freeValue(res, a.allocator);
            cmd_p[0] = .{ .string = "startinsert" };
            res = try a.rpc_term.call("nvim_command", cmd_p);
            @import("../nvim/msgpack.zig").freeValue(res, a.allocator);
            a.terminal_win_count += 1;
            a.needs_resize = true;
            return true;
        }
        if (std.mem.eql(u8, k.raw, "\x1bc")) { // Alt+c -> Close Split
            const win_list = try a.rpc_term.call("nvim_list_wins", &[_]Value{});
            defer @import("../nvim/msgpack.zig").freeValue(win_list, a.allocator);
            if (win_list == .array and win_list.array.len > 1) {
                var cmd_p = try a.allocator.alloc(Value, 1);
                defer a.allocator.free(cmd_p);
                cmd_p[0] = .{ .string = "close" };
                const res = try a.rpc_term.call("nvim_command", cmd_p);
                @import("../nvim/msgpack.zig").freeValue(res, a.allocator);
                a.terminal_win_count = win_list.array.len - 1;
            } else {
                a.show_terminal_panel = false;
                a.terminal_focus = false;
                a.terminal_win_count = 1;
                a.updateLayoutTree();
                a.needs_resize = true;
            }
            return true;
        }
        if (std.mem.eql(u8, k.raw, "\x1bo")) { // Alt+o -> Cycle Focus
            var cmd_p = try a.allocator.alloc(Value, 1);
            defer a.allocator.free(cmd_p);
            cmd_p[0] = .{ .string = "wincmd w" };
            var res = try a.rpc_term.call("nvim_command", cmd_p);
            @import("../nvim/msgpack.zig").freeValue(res, a.allocator);
            cmd_p[0] = .{ .string = "startinsert" };
            res = try a.rpc_term.call("nvim_command", cmd_p);
            @import("../nvim/msgpack.zig").freeValue(res, a.allocator);
            return true;
        }
        if (std.mem.eql(u8, k.raw, "\x1bk")) { // Alt+k -> Focus Up (to Editor)
            if (a.panel_position == .bottom) {
                a.terminal_focus = false;
                a.needs_resize = true;
                return true;
            }
        }
        if (std.mem.eql(u8, k.raw, "\x1bh")) { // Alt+h -> Focus Left (to Editor if on right)
            if (a.panel_position == .right) {
                a.terminal_focus = false;
                a.needs_resize = true;
                return true;
            } else {
                var cmd_p = try a.allocator.alloc(Value, 1);
                defer a.allocator.free(cmd_p);
                cmd_p[0] = .{ .string = "wincmd h" };
                var res = try a.rpc_term.call("nvim_command", cmd_p);
                @import("../nvim/msgpack.zig").freeValue(res, a.allocator);
                cmd_p[0] = .{ .string = "startinsert" };
                res = try a.rpc_term.call("nvim_command", cmd_p);
                @import("../nvim/msgpack.zig").freeValue(res, a.allocator);
                return true;
            }
        }
        if (std.mem.eql(u8, k.raw, "\x1bl")) { // Alt+l -> Focus Right
            if (a.panel_position != .right) {
                var cmd_p = try a.allocator.alloc(Value, 1);
                defer a.allocator.free(cmd_p);
                cmd_p[0] = .{ .string = "wincmd l" };
                var res = try a.rpc_term.call("nvim_command", cmd_p);
                @import("../nvim/msgpack.zig").freeValue(res, a.allocator);
                cmd_p[0] = .{ .string = "startinsert" };
                res = try a.rpc_term.call("nvim_command", cmd_p);
                @import("../nvim/msgpack.zig").freeValue(res, a.allocator);
                return true;
            }
        }
        if (std.mem.eql(u8, k.raw, "\x1bj")) { // Alt+j -> Focus Down
            if (a.panel_position != .bottom) {
                var cmd_p = try a.allocator.alloc(Value, 1);
                defer a.allocator.free(cmd_p);
                cmd_p[0] = .{ .string = "wincmd j" };
                var res = try a.rpc_term.call("nvim_command", cmd_p);
                @import("../nvim/msgpack.zig").freeValue(res, a.allocator);
                cmd_p[0] = .{ .string = "startinsert" };
                res = try a.rpc_term.call("nvim_command", cmd_p);
                @import("../nvim/msgpack.zig").freeValue(res, a.allocator);
                return true;
            }
        }
    }

    var alt_buf: [10]u8 = undefined;
    const nk = get_key: {
        if (k.raw.len == 1) {
            const b = k.raw[0];
            if (b == 0x0d or b == 0x0a) break :get_key "<Enter>";
            if (b == 0x1b) break :get_key "<Esc>";
            if (b == 0x7f or b == 0x08) break :get_key "<BS>";
            if (b == 0x09) break :get_key "<Tab>";
            if (b >= 1 and b <= 26) {
                const ctrl_keys = [_][]const u8{
                    "<C-a>", "<C-b>", "<C-c>", "<C-d>", "<C-e>", "<C-f>", "<C-g>", "<C-h>",
                    "<C-i>", "<C-j>", "<C-k>", "<C-l>", "<C-m>", "<C-n>", "<C-o>", "<C-p>",
                    "<C-q>", "<C-r>", "<C-s>", "<C-t>", "<C-u>", "<C-v>", "<C-w>", "<C-x>",
                    "<C-y>", "<C-z>",
                };
                const ctrl_name = ctrl_keys[b - 1];
                const is_editing_keys = a.settings_widget.is_open and a.settings_widget.active_binding != null;
                const kb = &a.settings_widget.config.keybindings;
                if (is_editing_keys or
                    std.mem.eql(u8, ctrl_name, kb.toggle_terminal) or
                    std.mem.eql(u8, ctrl_name, kb.toggle_explorer) or
                    std.mem.eql(u8, ctrl_name, kb.toggle_zen) or
                    std.mem.eql(u8, ctrl_name, kb.new_file) or
                    std.mem.eql(u8, ctrl_name, kb.find_file) or
                    std.mem.eql(u8, ctrl_name, kb.quit))
                {
                    break :get_key ctrl_name;
                }
            }
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
        if (std.mem.eql(u8, k.raw, "\x1b[Z")) break :get_key "<S-Tab>";
        if (std.mem.eql(u8, k.raw, "\x09")) break :get_key "<Tab>";
        if (k.raw.len == 2 and k.raw[0] == 0x1b) {
            const b = k.raw[1];
            const key_str = switch (b) {
                0x0d, 0x0a => "CR",
                0x7f, 0x08 => "BS",
                0x1b => "Esc",
                0x09 => "Tab",
                else => null,
            };
            if (key_str) |ks| {
                const alt_key = std.fmt.bufPrint(&alt_buf, "<M-{s}>", .{ks}) catch k.raw;
                break :get_key alt_key;
            } else {
                const alt_key = std.fmt.bufPrint(&alt_buf, "<M-{c}>", .{b}) catch k.raw;
                break :get_key alt_key;
            }
        }
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
    var find_file = false;
    var quit = false;
    
    const kb = &a.settings_widget.config.keybindings;
    if (std.mem.eql(u8, nk, kb.toggle_terminal) or std.mem.eql(u8, k.raw, kb.toggle_terminal)) toggle_terminal_panel = true;
    if (std.mem.eql(u8, nk, kb.toggle_explorer) or std.mem.eql(u8, k.raw, kb.toggle_explorer)) toggle_explorer = true;
    if (std.mem.eql(u8, nk, kb.toggle_zen) or std.mem.eql(u8, k.raw, kb.toggle_zen)) toggle_zen = true;
    if (std.mem.eql(u8, nk, kb.new_file) or std.mem.eql(u8, k.raw, kb.new_file)) new_file = true;
    if (std.mem.eql(u8, nk, kb.find_file) or std.mem.eql(u8, k.raw, kb.find_file)) find_file = true;
    if (std.mem.eql(u8, nk, kb.quit) or std.mem.eql(u8, k.raw, kb.quit)) quit = true;

    if (toggle_zen) {
        if (a.settings_widget.config.zen_handoff) {
            // Handoff to native nvim: save session
            var wa_cmd = [_]Value{.{ .string = "wa" }};
            _ = a.rpc.call("nvim_command", &wa_cmd) catch {};
            
            var mks_cmd = [_]Value{.{ .string = "mksession! /tmp/vide_session.vim" }};
            _ = a.rpc.call("nvim_command", &mks_cmd) catch {};
            
            return error.ZenModeHandoff;
        } else {
            if (a.mode != .zen) {
                a.mode = .zen;
                a.prev_mode = .zen;
                a.settings_widget.config.zen = true;
                a.settings_widget.config.ide = false;
                a.settings_widget.allocator.free(a.settings_widget.config.mode);
                a.settings_widget.config.mode = a.settings_widget.allocator.dupe(u8, "zen") catch a.settings_widget.config.mode;
                
                var cmd_p = [_]Value{.{ .string = "set laststatus=3" }};
                _ = a.rpc.call("nvim_command", &cmd_p) catch {};
                cmd_p[0] = .{ .string = "lua vim.g.vide_zen_mode = true; vim.g.vide_ide_mode = false; _G.vide_disable_ide_mode(); if _G.vide_update_dashboard_keys then _G.vide_update_dashboard_keys() end; pcall(function() require('alpha').redraw() end)" };
                _ = a.rpc.call("nvim_command", &cmd_p) catch {};
            } else {
                a.mode = .normal;
                a.prev_mode = .normal;
                a.settings_widget.config.zen = false;
                a.settings_widget.config.ide = false;
                a.settings_widget.allocator.free(a.settings_widget.config.mode);
                a.settings_widget.config.mode = a.settings_widget.allocator.dupe(u8, "normal") catch a.settings_widget.config.mode;
                
                var cmd_p = [_]Value{.{ .string = "set laststatus=3" }};
                _ = a.rpc.call("nvim_command", &cmd_p) catch {};
                cmd_p[0] = .{ .string = "lua vim.g.vide_zen_mode = false; vim.g.vide_ide_mode = false; _G.vide_disable_ide_mode(); if _G.vide_update_dashboard_keys then _G.vide_update_dashboard_keys() end; pcall(function() require('alpha').redraw() end)" };
                _ = a.rpc.call("nvim_command", &cmd_p) catch {};
            }
            a.needs_resize = true;
            return true;
        }
    } else if (toggle_explorer) {
        a.show_file_tree = !a.show_file_tree;
        if (a.show_file_tree) {
            a.sidebar_focus = true;
            a.terminal_focus = false;
        } else {
            a.sidebar_focus = false;
        }
        a.needs_resize = true;
        return true;
    } else if (toggle_terminal_panel) {
        a.show_terminal_panel = !a.show_terminal_panel;
        if (a.show_terminal_panel) {
            a.terminal_focus = true;
            a.sidebar_focus = false;
        } else {
            a.terminal_focus = false;
        }
        a.updateLayoutTree();
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
    } else if (find_file) {
        var cmd_p = try a.allocator.alloc(Value, 1);
        cmd_p[0] = .{ .string = "while #vim.api.nvim_win_get_config(0).relative > 0 do vim.cmd('close') end; vim.cmd('Telescope find_files')" };
        var params = try a.allocator.alloc(Value, 2);
        defer a.allocator.free(params);
        params[0] = cmd_p[0];
        params[1] = .{ .array = &[_]Value{} };
        if (a.rpc.call("nvim_exec_lua", params) catch null) |res| {
            @import("../nvim/msgpack.zig").freeValue(res, a.allocator);
        }
        a.allocator.free(cmd_p);
        return true;
    } else if (quit) {
        a.quit_requested = true;
        var cmd_p = try a.allocator.alloc(Value, 1);
        cmd_p[0] = .{ .string = "vim.cmd('qa')" };
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
        if (a.sidebar_focus) {
            if (std.mem.eql(u8, nk, "<Tab>")) {
                a.activity_bar.active_idx = (a.activity_bar.active_idx + 1) % 4;
                a.needs_resize = true;
                return true;
            }
            if (std.mem.eql(u8, nk, "<S-Tab>")) {
                a.activity_bar.active_idx = if (a.activity_bar.active_idx == 0) 3 else a.activity_bar.active_idx - 1;
                a.needs_resize = true;
                return true;
            }
            if (std.mem.eql(u8, nk, "<C-s>")) {
                const old_cfg = a.settings_widget.config;
                if (settings.SettingsConfig.load(a.settings_widget.allocator, a.settings_widget.settings_path)) |new_cfg| {
                    a.settings_widget.config = new_cfg;
                    a.settings_widget.allocator.free(old_cfg.theme);
                    a.settings_widget.allocator.free(old_cfg.line_numbers);
                    a.settings_widget.allocator.free(old_cfg.split_separator);
                    a.settings_widget.allocator.free(old_cfg.keybindings.toggle_terminal);
                    a.settings_widget.allocator.free(old_cfg.keybindings.toggle_explorer);
                    a.settings_widget.allocator.free(old_cfg.keybindings.toggle_zen);
                    a.settings_widget.allocator.free(old_cfg.keybindings.new_file);
                    a.settings_widget.allocator.free(old_cfg.keybindings.find_file);
                    a.settings_widget.allocator.free(old_cfg.keybindings.quit);
                } else |_| {}
                a.settings_widget.is_open = true;
                a.needs_resize = true;
                return true;
            }
            if (std.mem.eql(u8, nk, "<Esc>") or std.mem.eql(u8, nk, "<M-l>")) {
                a.sidebar_focus = false;
                a.needs_resize = true;
                return true;
            }
            if (a.show_file_tree and a.activity_bar.active_idx == 0) {
                if (a.explorer.handleKey(nk, a.rpc) catch false) {
                    a.needs_resize = true;
                    return true;
                }
            } else if (a.show_file_tree and a.activity_bar.active_idx == 1) {
                if (a.search_panel.handleKey(nk)) |cmd| {
                    if (std.mem.startsWith(u8, cmd, "__CMD__:Telescope")) {
                        var cmd_p = try a.allocator.alloc(Value, 1);
                        defer a.allocator.free(cmd_p);
                        cmd_p[0] = .{ .string = cmd[8..] };
                        a.rpc.notify("nvim_command", cmd_p) catch {};
                        a.sidebar_focus = false;
                    }
                    a.needs_resize = true;
                    return true;
                } else if (std.mem.eql(u8, nk, "j") or std.mem.eql(u8, nk, "k") or std.mem.eql(u8, nk, "<Down>") or std.mem.eql(u8, nk, "<Up>")) {
                    a.needs_resize = true;
                    return true;
                }
            } else if (a.show_file_tree and a.activity_bar.active_idx == 2) {
                if (a.git_panel.handleKey(nk) catch false) {
                    a.needs_resize = true;
                    return true;
                }
            } else if (a.show_file_tree and a.activity_bar.active_idx == 3) {
                if (a.ai_panel.handleKey(nk)) |cmd| {
                    if (std.mem.startsWith(u8, cmd, "__CMD__:lua ")) {
                        var cmd_p = try a.allocator.alloc(Value, 1);
                        defer a.allocator.free(cmd_p);
                        cmd_p[0] = .{ .string = cmd[8..] };
                        a.rpc.notify("nvim_command", cmd_p) catch {};
                        a.sidebar_focus = false;
                    }
                    a.needs_resize = true;
                    return true;
                } else if (std.mem.eql(u8, nk, "j") or std.mem.eql(u8, nk, "k") or std.mem.eql(u8, nk, "<Down>") or std.mem.eql(u8, nk, "<Up>")) {
                    a.needs_resize = true;
                    return true;
                }
            }
        } else {
            if (a.show_file_tree and a.activity_bar.active_idx == 0 and a.explorer.action_state != .none) {
                if (a.explorer.handleKey(nk, a.rpc) catch false) {
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
        }
        
        const sent_key = if (std.mem.eql(u8, nk, "<")) @as([]const u8, "<lt>") else nk;
        var ip = try a.allocator.alloc(Value, 1);
        defer a.allocator.free(ip);
        ip[0] = .{ .string = sent_key };
        (if (a.terminal_focus) a.rpc_term else a.rpc).notify("nvim_input", ip) catch {};
    }
    return true;
}

pub fn handleMouse(a: *App, m: input.MouseEvent, layout: Layout) !void {
    a.last_click_x = m.col; a.last_click_y = m.row;

    // Handle split menu click if open
    if (a.show_split_menu and m.action == .press) {
        const mx = a.split_menu_x;
        const my = a.split_menu_y;
        const mw: u16 = 24;
        const mh: u16 = 6;
        if (m.col >= mx and m.col < mx + mw and m.row >= my and m.row < my + mh) {
            const row_offset = m.row - my;
            var cmd_p = try a.allocator.alloc(Value, 1);
            defer a.allocator.free(cmd_p);
            
            var run_term = false;
            var is_split = false;
            
            // Map row click to the action
            if (row_offset == 1) { // Terminal (Right/Bottom)
                run_term = true;
                cmd_p[0] = if (a.split_menu_dir == .right)
                    .{ .string = if (a.terminal_focus) "rightb vnew | terminal" else "rightb vsplit | terminal" }
                else
                    .{ .string = if (a.terminal_focus) "belowright new | terminal" else "belowright split | terminal" };
            } else if (row_offset == 2) { // Terminal (Left/Top)
                run_term = true;
                cmd_p[0] = if (a.split_menu_dir == .right)
                    .{ .string = if (a.terminal_focus) "lefta vnew | terminal" else "lefta vsplit | terminal" }
                else
                    .{ .string = if (a.terminal_focus) "aboveleft new | terminal" else "aboveleft split | terminal" };
            } else if (row_offset == 3) { // Editor (Right/Bottom)
                cmd_p[0] = if (a.split_menu_dir == .right)
                    .{ .string = if (a.terminal_focus) "rightb vnew" else "rightb vsplit" }
                else
                    .{ .string = if (a.terminal_focus) "belowright new" else "belowright split" };
            } else if (row_offset == 4) { // Editor (Left/Top)
                cmd_p[0] = if (a.split_menu_dir == .right)
                    .{ .string = if (a.terminal_focus) "lefta vnew" else "lefta vsplit" }
                else
                    .{ .string = if (a.terminal_focus) "aboveleft new" else "aboveleft split" };
            } else {
                is_split = false;
            }
            
            if (row_offset >= 1 and row_offset <= 4) {
                is_split = true;
            }
            
            if (is_split) {
                if (a.terminal_focus) {
                    var res = try a.rpc_term.call("nvim_command", cmd_p);
                    @import("../nvim/msgpack.zig").freeValue(res, a.allocator);
                    if (run_term) {
                        cmd_p[0] = .{ .string = "startinsert" };
                        res = try a.rpc_term.call("nvim_command", cmd_p);
                        @import("../nvim/msgpack.zig").freeValue(res, a.allocator);
                    }
                    a.terminal_win_count += 1;
                } else {
                    var res = try a.rpc.call("nvim_command", cmd_p);
                    @import("../nvim/msgpack.zig").freeValue(res, a.allocator);
                    if (run_term) {
                        cmd_p[0] = .{ .string = "startinsert" };
                        res = try a.rpc.call("nvim_command", cmd_p);
                        @import("../nvim/msgpack.zig").freeValue(res, a.allocator);
                    }
                }
            }
        }
        a.show_split_menu = false;
        a.needs_resize = true;
        return;
    }
    // Handle Telescope close click
    if (m.action == .press) {
        for (a.ui_state.telescope_rects) |rect_opt| {
            if (rect_opt) |rect| {
                const t_x = layout.editor.x + rect.x;
                const t_y = layout.editor.y + rect.y;
                const wx = if (t_x > 0) t_x - 1 else 0;
                const wy = if (t_y > 0) t_y - 1 else 0;
                if (m.row == wy and m.col >= wx + rect.w - 3 and m.col <= wx + rect.w + 1) {
                    var cmd_p = try a.allocator.alloc(Value, 1);
                    defer a.allocator.free(cmd_p);
                    cmd_p[0] = .{ .string = "lua for _, winid in ipairs(vim.api.nvim_list_wins()) do local ok, bufnr = pcall(vim.api.nvim_win_get_buf, winid); if ok then if vim.bo[bufnr].filetype == 'TelescopePrompt' then pcall(require('telescope.actions').close, bufnr) elseif vim.bo[bufnr].filetype == 'vimbindings' then pcall(vim.api.nvim_win_close, winid, true) end end end" };
                    a.rpc.notify("nvim_command", cmd_p) catch {};
                    a.ui_state.telescope_rects[0] = null;
                    a.ui_state.telescope_rects[1] = null;
                    a.needs_resize = true;
                    return;
                }
            }
        }
    }

    // Handle split window close button click
    if (m.action == .press) {
        if (a.terminal_focus) {
            if (layout.panel != null and a.terminal_wins.items.len > 1) {
                for (a.terminal_wins.items) |win| {
                    if (win.width > 4 and win.height > 1) {
                        const bx = layout.panel.?.x + win.col + win.width - 2;
                        const by = layout.panel.?.y + 1 + win.row;
                        if (m.col >= bx - 1 and m.col <= bx + 1 and m.row == by) {
                            var params = try a.allocator.alloc(Value, 2);
                            defer a.allocator.free(params);
                            params[0] = .{ .integer = win.id };
                            params[1] = .{ .bool = true };
                            const res = try a.rpc_term.call("nvim_win_close", params);
                            @import("../nvim/msgpack.zig").freeValue(res, a.allocator);
                            return;
                        }
                    }
                }
            }
        } else {
            if (a.editor_wins.items.len > 1) {
                for (a.editor_wins.items) |win| {
                    if (win.width > 4 and win.height > 1) {
                        const bx = layout.editor.x + win.col + win.width - 2;
                        const by = layout.editor.y + win.row;
                        if (m.col >= bx - 1 and m.col <= bx + 1 and m.row == by) {
                            var params = try a.allocator.alloc(Value, 2);
                            defer a.allocator.free(params);
                            params[0] = .{ .integer = win.id };
                            params[1] = .{ .bool = true };
                            const res = try a.rpc.call("nvim_win_close", params);
                            @import("../nvim/msgpack.zig").freeValue(res, a.allocator);
                            return;
                        }
                    }
                }
            }
        }
    }

    // Handle split button click
    if (m.action == .press and m.row == layout.tab_bar.y and layout.tab_bar.w > 15) {
        const right_edge = layout.tab_bar.x + layout.tab_bar.w;
        if (m.col >= right_edge - 12 and m.col <= right_edge - 8) { // Split Vertically
            a.show_split_menu = true;
            a.split_menu_dir = .right;
            a.split_menu_x = right_edge - 26;
            a.split_menu_y = layout.tab_bar.y + 1;
            a.needs_resize = true;
            return;
        } else if (m.col >= right_edge - 6 and m.col <= right_edge - 2) { // Split Horizontally
            a.show_split_menu = true;
            a.split_menu_dir = .bottom;
            a.split_menu_x = right_edge - 26;
            a.split_menu_y = layout.tab_bar.y + 1;
            a.needs_resize = true;
            return;
        }
    }
    
    if (a.explorer.show_menu and m.action == .press) {
        if (try a.explorer.handleMenuClick(m.col, m.row)) {
            a.needs_resize = true;
            return;
        }
        a.explorer.show_menu = false;
        a.needs_resize = true;
    }
    
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

    if (a.settings_widget.is_open) {
        if (m.action == .press) {
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
        }
        return;
    }

    if (a.mode != .zen) {
        if (m.action == .press) {
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
                a.sidebar_focus = true;
                if (a.activity_bar.active_idx == 0) {
                    if (m.button == .right) {
                        a.explorer.show_menu = true;
                        
                        const rel_y = m.row - layout.file_tree.y;
                        var is_dir = false;
                        if (rel_y > 0) {
                            const item_idx = rel_y - 1 + a.explorer.scroll_y;
                            if (item_idx < a.explorer.items.items.len) {
                                a.explorer.selected_idx = item_idx;
                                is_dir = a.explorer.items.items[item_idx].is_dir;
                            } else {
                                a.explorer.selected_idx = null;
                            }
                        } else {
                            a.explorer.selected_idx = null;
                        }
                        
                        const menu_h: u16 = if (a.explorer.selected_idx != null)
                            (if (is_dir) @as(u16, 5) else @as(u16, 3))
                        else
                            @as(u16, 3);
                            
                        a.explorer.menu_x = m.col;
                        var my = m.row;
                        if (layout.file_tree.h > 0 and my + menu_h >= layout.file_tree.y + layout.file_tree.h) {
                            const limit = layout.file_tree.y + layout.file_tree.h;
                            if (limit > menu_h + 1) {
                                my = limit - menu_h - 1;
                            } else {
                                my = layout.file_tree.y;
                            }
                        }
                        a.explorer.menu_y = my;
                        
                        a.needs_resize = true;
                    } else if (m.button == .left) {
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
                } else if (a.activity_bar.active_idx == 3) {
                    if (a.ai_panel.handleMouse(m.col, m.row, layout.file_tree)) |cmd| {
                        if (std.mem.startsWith(u8, cmd, "__CMD__:lua ")) {
                            const actual_cmd = cmd[8..];
                            var cmd_p = try a.allocator.alloc(Value, 1);
                            defer a.allocator.free(cmd_p);
                            cmd_p[0] = .{ .string = actual_cmd };
                            a.rpc.notify("nvim_command", cmd_p) catch {};
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
                    if (new_idx != 99) {
                        a.sidebar_focus = true;
                    }
                    if (prev_idx != new_idx) a.needs_resize = true;
                    if (new_idx == 99) {
                        const old_cfg = a.settings_widget.config;
                        if (settings.SettingsConfig.load(a.settings_widget.allocator, a.settings_widget.settings_path)) |new_cfg| {
                            a.settings_widget.config = new_cfg;
                            a.settings_widget.allocator.free(old_cfg.theme);
                            a.settings_widget.allocator.free(old_cfg.line_numbers);
                            a.settings_widget.allocator.free(old_cfg.split_separator);
                            a.settings_widget.allocator.free(old_cfg.keybindings.toggle_terminal);
                            a.settings_widget.allocator.free(old_cfg.keybindings.toggle_explorer);
                            a.settings_widget.allocator.free(old_cfg.keybindings.toggle_zen);
                            a.settings_widget.allocator.free(old_cfg.keybindings.new_file);
                            a.settings_widget.allocator.free(old_cfg.keybindings.find_file);
                            a.settings_widget.allocator.free(old_cfg.keybindings.quit);
                        } else |_| {}
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
                
                // Handle status bar clicks
                if (m.row == layout.status_bar.y) {
                    const help_btn_len: u16 = if (a.settings_widget.config.nerd_fonts) 8 else 10;
                    if (m.col >= layout.status_bar.x + layout.status_bar.w - help_btn_len) {
                        var cmd_p = try a.allocator.alloc(Value, 1);
                        cmd_p[0] = .{ .string = "HelpMenu" };
                        a.rpc.notify("nvim_command", cmd_p) catch {};
                        a.allocator.free(cmd_p);
                        return;
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
