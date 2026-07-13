const std = @import("std");
const build_options = @import("build_options");
const renderer = @import("../renderer.zig");
const Color = renderer.Color;
const primitives = @import("primitives.zig");

pub const Keybindings = struct {
    toggle_explorer: []const u8 = "<C-e>", // Ctrl-e
    toggle_terminal: []const u8 = "<C-t>", // Ctrl-t
    toggle_zen: []const u8 = "<F11>",
    new_file: []const u8 = "<C-n>", // Ctrl-n
    find_file: []const u8 = "<C-f>", // Ctrl-f
    quit: []const u8 = "<C-q>", // Ctrl-q
};

pub fn formatKeyName(raw: []const u8, out: []u8) []const u8 {
    if (raw.len == 0) return "None";
    if (raw[0] == '<') return raw;
    if (raw.len == 1) {
        if (raw[0] >= 1 and raw[0] <= 26) {
            return std.fmt.bufPrint(out, "Ctrl+{c}", .{raw[0] - 1 + 'A'}) catch raw;
        } else if (raw[0] == 27) {
            return "Esc";
        }
        out[0] = raw[0];
        return out[0..1];
    }

    if (std.mem.eql(u8, raw, "\x1b[A")) return "Up";
    if (std.mem.eql(u8, raw, "\x1b[B")) return "Down";
    if (std.mem.eql(u8, raw, "\x1b[C")) return "Right";
    if (std.mem.eql(u8, raw, "\x1b[D")) return "Left";
    if (std.mem.eql(u8, raw, "\x1b[23~")) return "F11";

    if (raw.len == 2 and raw[0] == 27) {
        return std.fmt.bufPrint(out, "Alt+{c}", .{raw[1]}) catch raw;
    }
    return "Unknown";
}

pub const SettingsConfig = struct {
    clip: bool = true,
    zen: bool = false,
    zen_handoff: bool = false,
    ide: bool = false,
    autocomplete: bool = true,
    autoindent: bool = true,
    theme: []const u8 = "kanagawa",
    indent_size: u8 = 4,
    use_tabs: bool = false,
    wrap: bool = false,
    line_numbers: []const u8 = "relative",
    colorcolumn: []const u8 = "",
    split_separator: []const u8 = "│",
    keybindings: Keybindings = .{},
    nerd_fonts: bool = false,
    mode: []const u8 = "normal",

    pub fn deinit(self: *SettingsConfig, allocator: std.mem.Allocator) void {
        allocator.free(self.theme);
        allocator.free(self.line_numbers);
        allocator.free(self.colorcolumn);
        allocator.free(self.split_separator);
        allocator.free(self.mode);
        allocator.free(self.keybindings.toggle_terminal);
        allocator.free(self.keybindings.toggle_explorer);
        allocator.free(self.keybindings.toggle_zen);
        allocator.free(self.keybindings.new_file);
        allocator.free(self.keybindings.find_file);
        allocator.free(self.keybindings.quit);
        self.* = undefined;
    }

    pub fn load(allocator: std.mem.Allocator, path: []const u8) !SettingsConfig {
        const path_z = try allocator.dupeSentinel(u8, path, 0);
        defer allocator.free(path_z);

        const fd = std.posix.openatZ(std.posix.AT.FDCWD, path_z, .{ .ACCMODE = .RDONLY }, 0) catch |err| {
            if (err == error.FileNotFound) {
                var config = SettingsConfig{};
                config.theme = try allocator.dupe(u8, config.theme);
                config.line_numbers = try allocator.dupe(u8, config.line_numbers);
                config.colorcolumn = try allocator.dupe(u8, config.colorcolumn);
                config.split_separator = try allocator.dupe(u8, config.split_separator);
                config.keybindings.toggle_terminal = try allocator.dupe(u8, config.keybindings.toggle_terminal);
                config.keybindings.toggle_explorer = try allocator.dupe(u8, config.keybindings.toggle_explorer);
                config.keybindings.toggle_zen = try allocator.dupe(u8, config.keybindings.toggle_zen);
                config.keybindings.new_file = try allocator.dupe(u8, config.keybindings.new_file);
                config.keybindings.find_file = try allocator.dupe(u8, config.keybindings.find_file);
                config.keybindings.quit = try allocator.dupe(u8, config.keybindings.quit);
                config.mode = try allocator.dupe(u8, config.mode);
                return config;
            }
            return err;
        };
        defer _ = std.posix.system.close(fd);

        var buf: [4096]u8 = undefined;
        const read_rc = std.posix.system.read(fd, &buf, buf.len);
        if (std.posix.errno(read_rc) != .SUCCESS) return error.ReadFailed;
        const len: usize = @intCast(read_rc);

        const parsed = try std.json.parseFromSlice(SettingsConfig, allocator, buf[0..len], .{ .ignore_unknown_fields = true });
        defer parsed.deinit();

        var config = parsed.value;
        const valid_colorcolumn = config.colorcolumn.len == 0 or
            std.mem.eql(u8, config.colorcolumn, "80") or
            std.mem.eql(u8, config.colorcolumn, "100") or
            std.mem.eql(u8, config.colorcolumn, "120") or
            std.mem.eql(u8, config.colorcolumn, "80,120");
        if (!valid_colorcolumn) config.colorcolumn = "";
        // Backward compatibility mapping
        if (config.zen) {
            config.mode = "zen";
        } else if (config.ide) {
            config.mode = "ide";
        } else if (std.mem.eql(u8, config.mode, "normal")) {
            config.zen = false;
            config.ide = false;
        } else if (std.mem.eql(u8, config.mode, "zen")) {
            config.zen = true;
            config.ide = false;
        } else if (std.mem.eql(u8, config.mode, "ide")) {
            config.zen = false;
            config.ide = true;
        }

        config.theme = try allocator.dupe(u8, config.theme);
        config.line_numbers = try allocator.dupe(u8, config.line_numbers);
        config.colorcolumn = try allocator.dupe(u8, config.colorcolumn);
        config.split_separator = try allocator.dupe(u8, config.split_separator);
        config.keybindings.toggle_terminal = try allocator.dupe(u8, config.keybindings.toggle_terminal);
        config.keybindings.toggle_explorer = try allocator.dupe(u8, config.keybindings.toggle_explorer);
        config.keybindings.toggle_zen = try allocator.dupe(u8, config.keybindings.toggle_zen);
        config.keybindings.new_file = try allocator.dupe(u8, config.keybindings.new_file);
        config.keybindings.find_file = try allocator.dupe(u8, config.keybindings.find_file);
        config.keybindings.quit = try allocator.dupe(u8, config.keybindings.quit);
        config.mode = try allocator.dupe(u8, config.mode);
        return config;
    }

    pub fn save(self: *const SettingsConfig, path: []const u8) !void {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const alloc = arena.allocator();

        const path_z = try alloc.dupeSentinel(u8, path, 0);
        const fd = try std.posix.openatZ(std.posix.AT.FDCWD, path_z, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o644);
        defer _ = std.posix.system.close(fd);

        var buf: std.ArrayList(u8) = .empty;
        defer buf.deinit(alloc);

        var aw: std.Io.Writer.Allocating = .fromArrayList(alloc, &buf);
        try std.json.Stringify.value(self.*, .{}, &aw.writer);
        var out_buf = aw.toArrayList();
        defer out_buf.deinit(alloc);
        var written: usize = 0;
        while (written < out_buf.items.len) {
            const write_rc = std.posix.system.write(fd, out_buf.items.ptr + written, out_buf.items.len - written);
            switch (std.posix.errno(write_rc)) {
                .SUCCESS => written += @intCast(write_rc),
                .INTR => continue,
                else => return error.WriteFailed,
            }
        }
    }
};

pub const SettingsWidget = struct {
    is_open: bool = false,
    active_tab: usize = 0,
    allocator: std.mem.Allocator,
    config: SettingsConfig,
    needs_apply: bool = false,
    load_failed: bool = false,
    save_failed: bool = false,
    settings_path: []const u8,
    themes: std.array_list.Managed([]const u8),
    dropdown_scroll_offset: usize = 0,

    active_dropdown: DropdownType = .none,

    has_unsaved_changes: bool = false,
    popup_active: bool = false,

    active_binding: ?usize = null,
    duplicate_warning: bool = false,

    open_mason: bool = false,
    open_lazy: bool = false,
    software_update_requested: bool = false,
    software_update_status: SoftwareUpdateStatus = .idle,

    keyboard_focus: FocusMode = .tabs,
    hover_row: usize = 0,
    hover_dropdown_idx: usize = 0,

    io: std.Io,
    data_dir: []const u8,
    installed_plugins: std.array_list.Managed(InstalledPlugin),
    selected_plugin: ?InstalledPlugin = null,
    edit_config_path: ?[]const u8 = null,
    plugin_scroll_offset: usize = 0,
    popup_btn_idx: usize = 0,
    nvim_version: [32]u8 = [_]u8{0} ** 32,
    nvim_version_len: usize = 0,

    pub const InstalledPlugin = struct {
        full_name: []const u8,
        name: []const u8,
        stars: usize = 0,
        description: []const u8 = "",
    };

    pub const FocusMode = enum { tabs, content, dropdown };

    pub const SoftwareUpdateStatus = enum { idle, running, success, failure };

    pub const DropdownType = enum { none, theme, indent_size, indent_type, line_numbers, colorcolumn, split_separator, mode };

    pub const supported_modes = [_][]const u8{ "normal", "ide", "zen" };

    pub const supported_themes = [_][]const u8{ "vscode", "matteblack", "kanagawa", "tokyonight-night", "tokyonight-storm", "tokyonight-day", "catppuccin-latte", "catppuccin-frappe", "catppuccin-macchiato", "catppuccin-mocha", "gruvbox", "rose-pine", "rose-pine-moon", "rose-pine-dawn", "nord", "cyberdream" };

    pub const supported_indents = [_]u8{ 2, 4, 8 };
    pub const supported_indent_types = [_][]const u8{ "spaces", "tabs" };
    pub const supported_line_nums = [_][]const u8{ "relative", "normal", "off" };
    pub const supported_colorcolumns = [_][]const u8{ "", "80", "100", "120", "80,120" };
    pub const supported_split_seps = [_][]const u8{ "│", "▏", "▍", "", "┃", "║", "┊", " " };

    pub const tabs = [_][]const u8{
        "General",
        "Appearance",
        "Editor",
        "Plugins",
        "Keybindings",
        "About",
    };

    const software_updater =
        \\#!/bin/sh
        \\status_file=$1
        \\log_file=$2
        \\exec >"$log_file" 2>&1
        \\result=failure
        \\tmp_dir=
        \\cleanup() {
        \\    printf '%s\\n' "$result" >"$status_file"
        \\    [ -z "$tmp_dir" ] || rm -rf "$tmp_dir"
        \\}
        \\trap cleanup EXIT INT TERM
        \\tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/vide-software-update.XXXXXX") || exit 1
        \\if curl -fsSL --retry 3 -o "$tmp_dir/setup.sh" "https://raw.githubusercontent.com/Rouboufy/vide/main/setup.sh" &&
        \\   bash "$tmp_dir/setup.sh" --no-plugins; then
        \\    result=success
        \\fi
    ;

    pub fn init(allocator: std.mem.Allocator, settings_path: []const u8, io: std.Io, data_dir: []const u8) SettingsWidget {
        var load_failed = false;
        const config = SettingsConfig.load(allocator, settings_path) catch blk: {
            load_failed = true;
            var cfg = SettingsConfig{};
            cfg.theme = allocator.dupe(u8, cfg.theme) catch cfg.theme;
            cfg.line_numbers = allocator.dupe(u8, cfg.line_numbers) catch cfg.line_numbers;
            cfg.colorcolumn = allocator.dupe(u8, cfg.colorcolumn) catch cfg.colorcolumn;
            cfg.split_separator = allocator.dupe(u8, cfg.split_separator) catch cfg.split_separator;
            cfg.keybindings.toggle_terminal = allocator.dupe(u8, cfg.keybindings.toggle_terminal) catch cfg.keybindings.toggle_terminal;
            cfg.keybindings.toggle_explorer = allocator.dupe(u8, cfg.keybindings.toggle_explorer) catch cfg.keybindings.toggle_explorer;
            cfg.keybindings.toggle_zen = allocator.dupe(u8, cfg.keybindings.toggle_zen) catch cfg.keybindings.toggle_zen;
            cfg.keybindings.new_file = allocator.dupe(u8, cfg.keybindings.new_file) catch cfg.keybindings.new_file;
            cfg.keybindings.find_file = allocator.dupe(u8, cfg.keybindings.find_file) catch cfg.keybindings.find_file;
            cfg.keybindings.quit = allocator.dupe(u8, cfg.keybindings.quit) catch cfg.keybindings.quit;
            cfg.mode = allocator.dupe(u8, cfg.mode) catch cfg.mode;
            break :blk cfg;
        };
        var widget = SettingsWidget{
            .is_open = false,
            .active_tab = 0,
            .allocator = allocator,
            .config = config,
            .needs_apply = true,
            .load_failed = load_failed,
            .save_failed = false,
            .settings_path = settings_path,
            .themes = std.array_list.Managed([]const u8).init(allocator),
            .dropdown_scroll_offset = 0,
            .io = io,
            .data_dir = data_dir,
            .installed_plugins = std.array_list.Managed(InstalledPlugin).init(allocator),
            .selected_plugin = null,
            .edit_config_path = null,
            .plugin_scroll_offset = 0,
            .popup_btn_idx = 0,
        };
        widget.setThemesAndGroup(&supported_themes) catch {};
        return widget;
    }

    fn updatePath(self: *const SettingsWidget, file_name: []const u8) ![]u8 {
        return std.fs.path.join(self.allocator, &.{ self.data_dir, file_name });
    }

    pub fn startSoftwareUpdate(self: *SettingsWidget) !void {
        if (self.software_update_status == .running) return;
        const script_path = try self.updatePath("software-update.sh");
        defer self.allocator.free(script_path);
        const status_path = try self.updatePath("software-update.status");
        defer self.allocator.free(status_path);
        const log_path = try self.updatePath("software-update.log");
        defer self.allocator.free(log_path);

        std.Io.Dir.cwd().deleteFile(self.io, status_path) catch {};
        try std.Io.Dir.cwd().writeFile(self.io, .{ .sub_path = script_path, .data = software_updater });

        // The outer shell exits immediately after detaching the updater. Vide
        // remains responsive and the updater can finish if the app is closed.
        const argv = &[_][]const u8{
            "sh",
            "-c",
            "sh \"$1\" \"$2\" \"$3\" >/dev/null 2>&1 &",
            "vide-software-update",
            script_path,
            status_path,
            log_path,
        };
        var child = try std.process.spawn(self.io, .{
            .argv = argv,
            .stdin = .ignore,
            .stdout = .ignore,
            .stderr = .ignore,
        });
        const term = try child.wait(self.io);
        if (term != .exited or term.exited != 0) return error.UpdateLaunchFailed;
        self.software_update_status = .running;
    }

    pub fn pollSoftwareUpdate(self: *SettingsWidget) ?SoftwareUpdateStatus {
        if (self.software_update_status != .running) return null;
        const status_path = self.updatePath("software-update.status") catch return null;
        defer self.allocator.free(status_path);
        const status_path_z = self.allocator.dupeSentinel(u8, status_path, 0) catch return null;
        defer self.allocator.free(status_path_z);
        const fd = std.posix.openatZ(std.posix.AT.FDCWD, status_path_z, .{ .ACCMODE = .RDONLY }, 0) catch return null;
        defer _ = std.posix.system.close(fd);
        var buf: [16]u8 = undefined;
        const rc = std.posix.system.read(fd, &buf, buf.len);
        if (std.posix.errno(rc) != .SUCCESS) return null;
        const result = std.mem.trim(u8, buf[0..@intCast(rc)], " \r\n\t");
        if (std.mem.eql(u8, result, "success")) {
            self.software_update_status = .success;
        } else if (std.mem.eql(u8, result, "failure")) {
            self.software_update_status = .failure;
        } else {
            return null;
        }
        return self.software_update_status;
    }

    pub fn deinit(self: *SettingsWidget) void {
        self.config.deinit(self.allocator);
        for (self.themes.items) |t| {
            self.allocator.free(t);
        }
        self.themes.deinit();

        for (self.installed_plugins.items) |p| {
            self.allocator.free(p.full_name);
            self.allocator.free(p.name);
            self.allocator.free(p.description);
        }
        self.installed_plugins.deinit();
        if (self.edit_config_path) |path| {
            self.allocator.free(path);
        }
    }

    fn setThemesAndGroup(self: *SettingsWidget, raw_list: []const []const u8) !void {
        // Clear old themes
        for (self.themes.items) |t| {
            self.allocator.free(t);
        }
        self.themes.clearRetainingCapacity();

        var vide_list = std.array_list.Managed([]const u8).init(self.allocator);
        defer vide_list.deinit();
        var vim_list = std.array_list.Managed([]const u8).init(self.allocator);
        defer vim_list.deinit();
        var user_list = std.array_list.Managed([]const u8).init(self.allocator);
        defer user_list.deinit();

        const vim_defaults = [_][]const u8{ "default", "blue", "darkblue", "desert", "elflord", "habamax", "industry", "koehler", "lunaperche", "minischeme", "morning", "murphy", "peachpuff", "quiet", "randomhue", "retrobox", "ron", "shine", "slate", "sorbet", "torte", "wildcharm", "zaibatsu" };

        for (raw_list) |t| {
            var is_vide = false;
            for (supported_themes) |st| {
                if (std.mem.eql(u8, t, st)) {
                    is_vide = true;
                    break;
                }
            }
            if (is_vide) {
                try vide_list.append(t);
                continue;
            }

            var is_vim = false;
            for (vim_defaults) |vd| {
                if (std.mem.eql(u8, t, vd)) {
                    is_vim = true;
                    break;
                }
            }
            if (is_vim) {
                try vim_list.append(t);
                continue;
            }

            try user_list.append(t);
        }

        if (vide_list.items.len > 0) {
            try self.themes.append(try self.allocator.dupe(u8, "--- Vide Themes ---"));
            for (vide_list.items) |t| {
                try self.themes.append(try self.allocator.dupe(u8, t));
            }
        }
        if (vim_list.items.len > 0) {
            try self.themes.append(try self.allocator.dupe(u8, "--- Vim Defaults ---"));
            for (vim_list.items) |t| {
                try self.themes.append(try self.allocator.dupe(u8, t));
            }
        }
        if (user_list.items.len > 0) {
            try self.themes.append(try self.allocator.dupe(u8, "--- Installed ---"));
            for (user_list.items) |t| {
                try self.themes.append(try self.allocator.dupe(u8, t));
            }
        }
    }

    fn openThemeDropdown(self: *SettingsWidget) void {
        self.active_dropdown = .theme;
        self.hover_dropdown_idx = 1;
        self.dropdown_scroll_offset = 0;
        for (self.themes.items, 0..) |t, idx| {
            if (std.mem.eql(u8, t, self.config.theme)) {
                self.hover_dropdown_idx = idx;
                const max_visible_themes = 8;
                if (idx >= max_visible_themes) {
                    self.dropdown_scroll_offset = idx - (max_visible_themes / 2);
                    if (self.dropdown_scroll_offset + max_visible_themes > self.themes.items.len) {
                        self.dropdown_scroll_offset = self.themes.items.len - max_visible_themes;
                    }
                } else {
                    self.dropdown_scroll_offset = 0;
                }
                break;
            }
        }
    }

    pub fn refreshThemes(self: *SettingsWidget, rpc: *@import("../../nvim/rpc.zig").RpcClient) void {
        const Value = @import("../../nvim/msgpack.zig").Value;
        const msgpack = @import("../../nvim/msgpack.zig");

        var params = self.allocator.alloc(Value, 2) catch return;
        defer self.allocator.free(params);
        params[0] = .{ .string = "return vim.fn.getcompletion('', 'color')" };
        params[1] = .{ .array = &[_]Value{} };

        if (rpc.call("nvim_exec_lua", params) catch null) |res| {
            defer msgpack.freeValue(res, self.allocator);
            if (res == .array and res.array.len > 0) {
                var raw_list = std.array_list.Managed([]const u8).init(self.allocator);
                defer raw_list.deinit();
                for (res.array) |item| {
                    if (item == .string) {
                        raw_list.append(item.string) catch {};
                    }
                }
                self.setThemesAndGroup(raw_list.items) catch {};
            }
        }
    }

    fn readFileAlloc(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
        const path_z = try allocator.dupeSentinel(u8, path, 0);
        defer allocator.free(path_z);

        const fd = try std.posix.openatZ(std.posix.AT.FDCWD, path_z, .{ .ACCMODE = .RDONLY }, 0);
        defer _ = std.posix.system.close(fd);

        var list: std.ArrayList(u8) = .empty;
        errdefer list.deinit(allocator);

        var chunk: [4096]u8 = undefined;
        while (true) {
            const read_len = try std.posix.read(fd, &chunk);
            if (read_len == 0) break;
            try list.appendSlice(allocator, chunk[0..read_len]);
        }
        return try list.toOwnedSlice(allocator);
    }

    pub fn refreshPlugins(self: *SettingsWidget) void {
        for (self.installed_plugins.items) |p| {
            self.allocator.free(p.full_name);
            self.allocator.free(p.name);
            self.allocator.free(p.description);
        }
        self.installed_plugins.clearRetainingCapacity();

        const user_plugins_path = std.fs.path.join(self.allocator, &[_][]const u8{ self.data_dir, "user_plugins.json" }) catch return;
        defer self.allocator.free(user_plugins_path);

        const user_plugins_data = readFileAlloc(self.allocator, user_plugins_path) catch |err| {
            std.log.err("Failed to read user_plugins.json: {}", .{err});
            return;
        };
        defer self.allocator.free(user_plugins_data);

        const parsed_plugins = std.json.parseFromSlice([]const []const u8, self.allocator, user_plugins_data, .{ .ignore_unknown_fields = true }) catch |err| {
            std.log.err("Failed to parse user_plugins.json: {}", .{err});
            return;
        };
        defer parsed_plugins.deinit();

        if (parsed_plugins.value.len == 0) return;

        const store_db_path = std.fs.path.join(self.allocator, &[_][]const u8{ self.data_dir, "store_db.json" }) catch return;
        defer self.allocator.free(store_db_path);

        const DBItem = struct {
            name: []const u8,
            full_name: []const u8,
            stars: struct {
                curr: usize = 0,
            } = .{},
            description: ?[]const u8 = null,
        };
        const DB = struct {
            items: []DBItem,
        };

        const store_db_data = readFileAlloc(self.allocator, store_db_path) catch null;
        defer {
            if (store_db_data) |data| self.allocator.free(data);
        }

        var db_items: ?std.json.Parsed(DB) = null;
        if (store_db_data) |data| {
            db_items = std.json.parseFromSlice(DB, self.allocator, data, .{ .ignore_unknown_fields = true }) catch null;
        }
        defer {
            if (db_items) |db| db.deinit();
        }

        for (parsed_plugins.value) |repo_name| {
            var stars: usize = 0;
            var description: []const u8 = "";
            var name: []const u8 = "";

            if (std.mem.lastIndexOfScalar(u8, repo_name, '/')) |idx| {
                name = repo_name[idx + 1 ..];
            } else {
                name = repo_name;
            }

            if (db_items) |db| {
                for (db.value.items) |item| {
                    if (std.mem.eql(u8, item.full_name, repo_name)) {
                        stars = item.stars.curr;
                        description = item.description orelse "";
                        name = item.name;
                        break;
                    }
                }
            }

            self.installed_plugins.append(.{
                .full_name = self.allocator.dupe(u8, repo_name) catch continue,
                .name = self.allocator.dupe(u8, name) catch continue,
                .stars = stars,
                .description = self.allocator.dupe(u8, description) catch continue,
            }) catch {};
        }
    }

    fn editConfig(self: *SettingsWidget, p: InstalledPlugin) !void {
        const configs_dir = try std.fs.path.join(self.allocator, &[_][]const u8{ self.data_dir, "plugin_configs" });
        defer self.allocator.free(configs_dir);

        const file_name = try self.allocator.dupe(u8, p.full_name);
        defer self.allocator.free(file_name);
        for (file_name) |*c| {
            if (c.* == '/') {
                c.* = '_';
            }
        }

        const suffix = ".lua";
        const full_file_name = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ file_name, suffix });
        defer self.allocator.free(full_file_name);

        const config_file_path = try std.fs.path.join(self.allocator, &[_][]const u8{ configs_dir, full_file_name });
        errdefer self.allocator.free(config_file_path);

        std.Io.Dir.cwd().createDir(self.io, configs_dir, .default_dir) catch {};

        if (std.Io.Dir.openFileAbsolute(self.io, config_file_path, .{})) |file_value| {
            var file = file_value;
            file.close(self.io);
        } else |err| switch (err) {
            error.FileNotFound => {
                var template_buf: [512]u8 = undefined;
                const template = try std.fmt.bufPrint(
                    &template_buf,
                    "-- Configuration for {s}\n" ++
                        "-- This file is loaded automatically by lazy.nvim\n\n" ++
                        "return {{\n" ++
                        "  -- Add your custom plugin configuration here\n" ++
                        "}}\n",
                    .{p.name},
                );
                try std.Io.Dir.cwd().writeFile(self.io, .{ .sub_path = config_file_path, .data = template });
            },
            else => return err,
        }

        self.edit_config_path = config_file_path;
        self.is_open = false;
        self.selected_plugin = null;
    }

    pub fn draw(self: *const SettingsWidget, ren: *renderer.Renderer, screen_w: u16, screen_h: u16, theme: anytype) void {
        if (!self.is_open) return;

        const modal = primitives.Modal.centered(screen_w, screen_h, 80, 24, 5);
        const x = modal.rect.x;
        const y = modal.rect.y;
        const w = modal.rect.w;
        const h = modal.rect.h;

        if (!primitives.usable(modal, 50, 18)) {
            primitives.drawSizeWarning(ren, "Vide Settings", theme.fg_primary, theme.bg_sidebar);
            return;
        }

        primitives.drawModalFrame(ren, modal, .rounded, theme.fg_primary, theme.bg_sidebar, theme.border_color, theme.bg_editor);

        // Title
        var settings_title_buf: [64]u8 = undefined;
        const title = std.fmt.bufPrint(&settings_title_buf, " Vide Settings v{s} ", .{build_options.version}) catch " Vide Settings ";
        ren.drawText(x + 2, y, title, theme.fg_accent, theme.bg_sidebar, true, false);

        // Close button
        ren.drawText(x + w - 4, y, if (self.config.nerd_fonts) " 󰅖 " else " x ", .{ .rgb = .{ .r = 255, .g = 85, .b = 85 } }, theme.bg_sidebar, false, false);

        // Save button
        const save_button = primitives.Button{
            .rect = .{ .x = x + w - 18, .y = y + h - 2, .w = 16, .h = 1 },
            .state = if (self.has_unsaved_changes) .selected else .normal,
        };
        save_button.draw(ren, "Save & Close", .{
            .fg = theme.fg_secondary,
            .bg = theme.bg_sidebar,
            .accent_fg = theme.fg_primary,
            .accent_bg = theme.bg_accent,
            .muted_fg = theme.fg_secondary,
        });

        // Tabs
        var tab_y: u16 = y + 2;
        for (tabs, 0..) |tab, idx| {
            const is_active = (idx == self.active_tab);
            const fg = if (is_active) theme.fg_primary else theme.fg_secondary;
            if (is_active) {
                ren.drawText(x + 1, tab_y, " ┃ ", theme.fg_accent, theme.bg_sidebar, true, false);
                if (self.keyboard_focus == .tabs) {
                    ren.drawText(x + 1, tab_y, "▋", theme.fg_accent, theme.bg_sidebar, true, false);
                }
            }
            ren.drawText(x + 4, tab_y, tab, fg, theme.bg_sidebar, is_active, false);
            tab_y += 2;
        }

        // Separator between tabs and content
        for (y + 1..y + h - 1) |by| {
            ren.drawText(x + 20, @intCast(by), "│", theme.border_color, theme.bg_sidebar, false, false);
        }

        // Tab Content
        const content_x = x + 22;
        const content_y = y + 2;
        var buf: [128]u8 = undefined;

        switch (self.active_tab) {
            0 => {
                ren.drawText(content_x, content_y, "General Settings", theme.fg_primary, theme.bg_sidebar, true, false);

                const clip_t = if (self.config.clip) "[x]" else "[ ]";
                const clip_str = std.fmt.bufPrint(&buf, "{s} System Clipboard", .{clip_t}) catch "System Clipboard";
                ren.drawText(content_x, content_y + 2, clip_str, theme.fg_primary, theme.bg_sidebar, false, false);

                const mode_str = if (self.config.nerd_fonts)
                    std.fmt.bufPrint(&buf, "Mode:  [ {s} ▾ ]", .{self.config.mode}) catch "Mode: normal"
                else
                    std.fmt.bufPrint(&buf, "Mode:  [ {s} v ]", .{self.config.mode}) catch "Mode: normal";
                ren.drawText(content_x, content_y + 4, mode_str, theme.fg_primary, theme.bg_sidebar, false, false);

                const auto_t = if (self.config.autocomplete) "[x]" else "[ ]";
                const auto_str = std.fmt.bufPrint(&buf, "{s} Autocomplete", .{auto_t}) catch "Autocomplete";
                ren.drawText(content_x, content_y + 6, auto_str, theme.fg_primary, theme.bg_sidebar, false, false);

                const indent_t = if (self.config.autoindent) "[x]" else "[ ]";
                const indent_str = std.fmt.bufPrint(&buf, "{s} Autoindent", .{indent_t}) catch "Autoindent";
                ren.drawText(content_x, content_y + 8, indent_str, theme.fg_primary, theme.bg_sidebar, false, false);

                ren.drawText(content_x, content_y + 11, "Normal: full Vim-style editing and modes", theme.fg_secondary, theme.bg_sidebar, false, false);
                ren.drawText(content_x, content_y + 12, "IDE: familiar modeless text editing", theme.fg_secondary, theme.bg_sidebar, false, false);
                ren.drawText(content_x, content_y + 13, "Zen: fullscreen editor; F11 returns here", theme.fg_secondary, theme.bg_sidebar, false, false);
            },
            1 => {
                ren.drawText(content_x, content_y, "Appearance", theme.fg_primary, theme.bg_sidebar, true, false);

                const theme_str = if (self.config.nerd_fonts)
                    std.fmt.bufPrint(&buf, "Theme:  [ {s} ▾ ]", .{self.config.theme}) catch "Theme: kanagawa"
                else
                    std.fmt.bufPrint(&buf, "Theme:  [ {s} v ]", .{self.config.theme}) catch "Theme: kanagawa";
                ren.drawText(content_x, content_y + 2, theme_str, theme.fg_primary, theme.bg_sidebar, false, false);

                const sep_str = if (self.config.nerd_fonts)
                    std.fmt.bufPrint(&buf, "Split Separator:  [ {s} ▾ ]", .{self.config.split_separator}) catch "Split Separator: │"
                else
                    std.fmt.bufPrint(&buf, "Split Separator:  [ {s} v ]", .{self.config.split_separator}) catch "Split Separator: │";
                ren.drawText(content_x, content_y + 4, sep_str, theme.fg_primary, theme.bg_sidebar, false, false);

                const nf_t = if (self.config.nerd_fonts) "[x]" else "[ ]";
                const nf_str = std.fmt.bufPrint(&buf, "{s} Use Nerd Fonts (Icons)", .{nf_t}) catch "Use Nerd Fonts (Icons)";
                ren.drawText(content_x, content_y + 6, nf_str, theme.fg_primary, theme.bg_sidebar, false, false);
            },
            2 => {
                ren.drawText(content_x, content_y, "Editor", theme.fg_primary, theme.bg_sidebar, true, false);

                const type_str = if (self.config.nerd_fonts)
                    std.fmt.bufPrint(&buf, "Indent Type:  [ {s} ▾ ]", .{if (self.config.use_tabs) "tabs" else "spaces"}) catch "Indent Type: spaces"
                else
                    std.fmt.bufPrint(&buf, "Indent Type:  [ {s} v ]", .{if (self.config.use_tabs) "tabs" else "spaces"}) catch "Indent Type: spaces";
                ren.drawText(content_x, content_y + 2, type_str, theme.fg_primary, theme.bg_sidebar, false, false);

                const indent_str = if (self.config.nerd_fonts)
                    std.fmt.bufPrint(&buf, "Indent Size:  [ {d} ▾ ]", .{self.config.indent_size}) catch "Indent Size: 4"
                else
                    std.fmt.bufPrint(&buf, "Indent Size:  [ {d} v ]", .{self.config.indent_size}) catch "Indent Size: 4";
                ren.drawText(content_x, content_y + 4, indent_str, theme.fg_primary, theme.bg_sidebar, false, false);

                const wrap_t = if (self.config.wrap) "[x]" else "[ ]";
                const wrap_str = std.fmt.bufPrint(&buf, "{s} Text Wrap", .{wrap_t}) catch "Text Wrap";
                ren.drawText(content_x, content_y + 6, wrap_str, theme.fg_primary, theme.bg_sidebar, false, false);

                const line_str = if (self.config.nerd_fonts)
                    std.fmt.bufPrint(&buf, "Line Numbers:  [ {s} ▾ ]", .{self.config.line_numbers}) catch "Line Numbers: relative"
                else
                    std.fmt.bufPrint(&buf, "Line Numbers:  [ {s} v ]", .{self.config.line_numbers}) catch "Line Numbers: relative";
                ren.drawText(content_x, content_y + 8, line_str, theme.fg_primary, theme.bg_sidebar, false, false);

                const ruler_value = if (self.config.colorcolumn.len == 0) "off" else self.config.colorcolumn;
                const ruler_str = if (self.config.nerd_fonts)
                    std.fmt.bufPrint(&buf, "Column Ruler:  [ {s} ▾ ]", .{ruler_value}) catch "Column Ruler: off"
                else
                    std.fmt.bufPrint(&buf, "Column Ruler:  [ {s} v ]", .{ruler_value}) catch "Column Ruler: off";
                ren.drawText(content_x, content_y + 10, ruler_str, theme.fg_primary, theme.bg_sidebar, false, false);
            },
            3 => {
                ren.drawText(content_x, content_y, "Plugins", theme.fg_primary, theme.bg_sidebar, true, false);

                // Mason Button
                const mason_btn = " [ Mason Settings... ] ";
                const is_mason_hover = (self.keyboard_focus == .content and self.hover_row == 0);
                ren.drawText(content_x, content_y + 2, mason_btn, if (is_mason_hover) theme.fg_primary else theme.bg_sidebar, if (is_mason_hover) theme.fg_accent else theme.fg_accent, true, false);

                // Plugin Manager Button
                const lazy_btn = " [ Plugin Manager... ] ";
                const is_lazy_hover = (self.keyboard_focus == .content and self.hover_row == 1);
                ren.drawText(content_x, content_y + 4, lazy_btn, if (is_lazy_hover) theme.fg_primary else theme.bg_sidebar, if (is_lazy_hover) theme.fg_accent else theme.fg_accent, true, false);

                // Installed Plugins Title
                ren.drawText(content_x, content_y + 6, "Installed Plugins:", theme.fg_primary, theme.bg_sidebar, true, false);

                const max_visible_plugins = 6;
                const start_idx = self.plugin_scroll_offset;
                const end_idx = @min(self.installed_plugins.items.len, start_idx + max_visible_plugins);

                var idx = start_idx;
                var py_offset: u16 = 8;
                while (idx < end_idx) : (idx += 1) {
                    const p = self.installed_plugins.items[idx];
                    const is_hovered = (self.keyboard_focus == .content and self.hover_row == 2 + idx);

                    var plugin_line_buf: [128]u8 = undefined;
                    const plugin_line = std.fmt.bufPrint(&plugin_line_buf, "  • {s}", .{p.full_name}) catch p.full_name;

                    ren.drawText(content_x, content_y + py_offset, plugin_line, if (is_hovered) theme.fg_accent else theme.fg_secondary, theme.bg_sidebar, is_hovered, false);
                    py_offset += 1;
                }

                if (self.installed_plugins.items.len == 0) {
                    ren.drawText(content_x + 2, content_y + 8, "No installed plugins found.", theme.fg_secondary, theme.bg_sidebar, false, false);
                }

                if (self.plugin_scroll_offset > 0) {
                    ren.drawText(content_x + 35, content_y + 8, "▲", theme.fg_accent, theme.bg_sidebar, false, false);
                }
                if (self.plugin_scroll_offset + max_visible_plugins < self.installed_plugins.items.len) {
                    ren.drawText(content_x + 35, content_y + 8 + @as(u16, @intCast(max_visible_plugins)) - 1, "▼", theme.fg_accent, theme.bg_sidebar, false, false);
                }
            },
            4 => {
                ren.drawText(content_x, content_y, "Keybindings (Click to edit)", theme.fg_primary, theme.bg_sidebar, true, false);

                const actions = [_][]const u8{ "Toggle Terminal", "Toggle Explorer", "Toggle Zen Mode", "New File", "Find File", "Quit" };
                const current_keys = [_][]const u8{
                    self.config.keybindings.toggle_terminal,
                    self.config.keybindings.toggle_explorer,
                    self.config.keybindings.toggle_zen,
                    self.config.keybindings.new_file,
                    self.config.keybindings.find_file,
                    self.config.keybindings.quit,
                };

                for (actions, 0..) |action, i| {
                    var key_buf: [32]u8 = undefined;
                    const key_str = if (self.active_binding == i)
                        "Press any key... (Esc to cancel)"
                    else
                        formatKeyName(current_keys[i], &key_buf);

                    const draw_str = std.fmt.bufPrint(&buf, "{s}:  [ {s} ]", .{ action, key_str }) catch action;
                    const color = if (self.active_binding == i) theme.fg_accent else theme.fg_primary;
                    ren.drawText(content_x, content_y + 2 + @as(u16, @intCast(i)), draw_str, color, theme.bg_sidebar, false, false);
                }

                const static_actions = [_][]const u8{
                    "Split Vertically:        [ Alt+V ]",
                    "Split Horizontally:      [ Alt+S ]",
                    "Close Split Window:      [ Alt+C ]",
                    "Move Focus Left/Right:   [ Alt+H / Alt+L ]",
                    "Move Focus Up/Down:      [ Alt+K / Alt+J ]",
                    "Cycle Window Focus:      [ Alt+O ]",
                    "Resize Sidebar/Panel:    [ Alt+Arrow ]",
                    "Toggle Panel Bottom/Right:[ Alt+P ]",
                };

                ren.drawText(content_x, content_y + 9, "Window Splits & Layout (Static):", theme.fg_primary, theme.bg_sidebar, true, false);
                for (static_actions, 0..) |sa, sa_idx| {
                    ren.drawText(content_x, content_y + 10 + @as(u16, @intCast(sa_idx)), sa, theme.fg_secondary, theme.bg_sidebar, false, false);
                }
            },
            5 => {
                ren.drawText(content_x, content_y, "About Vide", theme.fg_primary, theme.bg_sidebar, true, false);

                const vide_line = std.fmt.bufPrint(&buf, "Vide version: {s}", .{build_options.version}) catch "Vide version: unknown";
                ren.drawText(content_x, content_y + 2, vide_line, theme.fg_primary, theme.bg_sidebar, false, false);
                const nvim_version = if (self.nvim_version_len > 0) self.nvim_version[0..self.nvim_version_len] else "unknown";
                const nvim_line = std.fmt.bufPrint(&buf, "Neovim version: {s}", .{nvim_version}) catch "Neovim version: unknown";
                ren.drawText(content_x, content_y + 4, nvim_line, theme.fg_primary, theme.bg_sidebar, false, false);

                const update_label = switch (self.software_update_status) {
                    .idle => "Update to Latest Version",
                    .running => "Updating Vide...",
                    .success => "Updated - Restart Vide",
                    .failure => "Update Failed - Retry",
                };
                const update_state: primitives.ControlState = if (self.software_update_status == .running)
                    .disabled
                else if (self.keyboard_focus == .content)
                    .focused
                else
                    .normal;
                (primitives.Button{ .rect = .{ .x = content_x, .y = content_y + 6, .w = 28, .h = 1 }, .state = update_state }).draw(ren, update_label, .{
                    .fg = theme.fg_secondary,
                    .bg = theme.bg_sidebar,
                    .accent_fg = theme.fg_primary,
                    .accent_bg = theme.bg_accent,
                    .muted_fg = theme.fg_secondary,
                });

                ren.drawText(content_x, content_y + 8, "Runtime paths", theme.fg_primary, theme.bg_sidebar, true, false);
                a: {
                    const available = if (w > 26) w - 26 else 1;
                    ren.drawText(content_x, content_y + 10, "Data:", theme.fg_secondary, theme.bg_sidebar, false, false);
                    ren.drawTextClipped(content_x + 10, content_y + 10, available, self.data_dir, theme.fg_primary, theme.bg_sidebar, false, false);
                    ren.drawText(content_x, content_y + 12, "Settings:", theme.fg_secondary, theme.bg_sidebar, false, false);
                    ren.drawTextClipped(content_x + 10, content_y + 12, available, self.settings_path, theme.fg_primary, theme.bg_sidebar, false, false);
                    const log_path = std.fmt.bufPrint(&buf, "{s}/vide.log", .{self.data_dir}) catch self.data_dir;
                    ren.drawText(content_x, content_y + 14, "Log:", theme.fg_secondary, theme.bg_sidebar, false, false);
                    ren.drawTextClipped(content_x + 10, content_y + 14, available, log_path, theme.fg_primary, theme.bg_sidebar, false, false);
                    break :a;
                }
            },
            else => {},
        }

        if (self.keyboard_focus == .content) {
            var row_y: ?u16 = null;
            if (self.active_tab == 3) {
                if (self.hover_row == 0) {
                    row_y = content_y + 2;
                } else if (self.hover_row == 1) {
                    row_y = content_y + 4;
                } else {
                    const plugin_idx = self.hover_row - 2;
                    if (plugin_idx >= self.plugin_scroll_offset and plugin_idx < self.plugin_scroll_offset + 6) {
                        row_y = content_y + 8 + @as(u16, @intCast(plugin_idx - self.plugin_scroll_offset));
                    }
                }
            } else {
                const step = if (self.active_tab == 4) @as(u16, 1) else @as(u16, 2);
                row_y = content_y + 2 + @as(u16, @intCast(self.hover_row)) * step;
            }
            if (row_y) |ry| {
                ren.drawText(content_x - 2, ry, "▋", theme.fg_accent, theme.bg_sidebar, true, false);
            }
        }

        // Draw active dropdown if any
        if (self.active_dropdown != .none) {
            const drop_x = content_x + 10;
            var drop_y = content_y + 3; // roughly below the selector
            var items_len: usize = 0;
            var drop_w: u16 = 20;

            if (self.active_dropdown == .theme) {
                items_len = self.themes.items.len;
                drop_w = 22;
                drop_y = content_y + 3;
            } else if (self.active_dropdown == .split_separator) {
                items_len = supported_split_seps.len;
                drop_y = content_y + 5;
            } else if (self.active_dropdown == .indent_size) {
                items_len = supported_indents.len;
                drop_y = content_y + 5;
            } else if (self.active_dropdown == .indent_type) {
                items_len = supported_indent_types.len;
                drop_y = content_y + 3;
            } else if (self.active_dropdown == .line_numbers) {
                items_len = supported_line_nums.len;
                drop_y = content_y + 9;
            } else if (self.active_dropdown == .colorcolumn) {
                items_len = supported_colorcolumns.len;
                drop_y = content_y + 11;
            } else if (self.active_dropdown == .mode) {
                items_len = supported_modes.len;
                drop_w = 16;
                drop_y = content_y + 5;
            }

            // clamp drop height to screen_h if it's too tall, or just draw
            const max_visible = if (self.active_dropdown == .theme) @min(items_len, 8) else items_len;
            const drop_h = @as(u16, @intCast(max_visible)) + 2;

            const dropdown = primitives.Modal{ .rect = .{ .x = drop_x, .y = drop_y, .w = drop_w, .h = drop_h } };
            primitives.drawModalFrame(ren, dropdown, .rounded, theme.fg_primary, theme.bg_sidebar, theme.border_color, theme.bg_editor);

            // Items
            var item_y = drop_y + 1;
            if (self.active_dropdown == .theme) {
                const max_visible_themes = 8;
                var i: usize = self.dropdown_scroll_offset;
                const end_idx = @min(self.themes.items.len, self.dropdown_scroll_offset + max_visible_themes);
                while (i < end_idx) : (i += 1) {
                    if (item_y >= screen_h) break;
                    const t = self.themes.items[i];
                    if (std.mem.startsWith(u8, t, "---")) {
                        ren.drawText(drop_x + 1, item_y, t, theme.fg_secondary, theme.bg_sidebar, false, false);
                    } else {
                        const is_sel = std.mem.eql(u8, self.config.theme, t);
                        const prefix = if (is_sel) " * " else "   ";
                        const str = std.fmt.bufPrint(&buf, "{s}{s}", .{ prefix, t }) catch " error";
                        ren.drawText(drop_x + 1, item_y, str, if (is_sel) theme.fg_accent else theme.fg_primary, theme.bg_sidebar, false, false);
                        if (i == self.hover_dropdown_idx) ren.drawText(drop_x + 1, item_y, "▋", theme.fg_accent, theme.bg_sidebar, true, false);
                    }
                    item_y += 1;
                }

                // Draw indicators for scrollability
                if (self.dropdown_scroll_offset > 0) {
                    ren.drawText(drop_x + drop_w - 2, drop_y, "▲", theme.fg_accent, theme.bg_sidebar, false, false);
                }
                if (self.dropdown_scroll_offset + max_visible_themes < self.themes.items.len) {
                    ren.drawText(drop_x + drop_w - 2, drop_y + drop_h - 1, "▼", theme.fg_accent, theme.bg_sidebar, false, false);
                }
            } else if (self.active_dropdown == .split_separator) {
                for (supported_split_seps, 0..) |s, idx| {
                    if (item_y >= screen_h) break;
                    const is_sel = std.mem.eql(u8, self.config.split_separator, s);
                    const prefix = if (is_sel) " * " else "   ";
                    const str = std.fmt.bufPrint(&buf, "{s}{s}", .{ prefix, s }) catch " error";
                    ren.drawText(drop_x + 1, item_y, str, if (is_sel) theme.fg_accent else theme.fg_primary, theme.bg_sidebar, false, false);
                    if (idx == self.hover_dropdown_idx) ren.drawText(drop_x + 1, item_y, "▋", theme.fg_accent, theme.bg_sidebar, true, false);
                    item_y += 1;
                }
            } else if (self.active_dropdown == .indent_size) {
                for (supported_indents, 0..) |i, idx| {
                    if (item_y >= screen_h) break;
                    const is_sel = (self.config.indent_size == i);
                    const prefix = if (is_sel) " * " else "   ";
                    const str = std.fmt.bufPrint(&buf, "{s}{d}", .{ prefix, i }) catch " error";
                    ren.drawText(drop_x + 1, item_y, str, if (is_sel) theme.fg_accent else theme.fg_primary, theme.bg_sidebar, false, false);
                    if (idx == self.hover_dropdown_idx) ren.drawText(drop_x + 1, item_y, "▋", theme.fg_accent, theme.bg_sidebar, true, false);
                    item_y += 1;
                }
            } else if (self.active_dropdown == .indent_type) {
                for (supported_indent_types, 0..) |t, idx| {
                    if (item_y >= screen_h) break;
                    const is_sel = if (std.mem.eql(u8, t, "tabs")) self.config.use_tabs else !self.config.use_tabs;
                    const prefix = if (is_sel) " * " else "   ";
                    const str = std.fmt.bufPrint(&buf, "{s}{s}", .{ prefix, t }) catch " error";
                    ren.drawText(drop_x + 1, item_y, str, if (is_sel) theme.fg_accent else theme.fg_primary, theme.bg_sidebar, false, false);
                    if (idx == self.hover_dropdown_idx) ren.drawText(drop_x + 1, item_y, "▋", theme.fg_accent, theme.bg_sidebar, true, false);
                    item_y += 1;
                }
            } else if (self.active_dropdown == .line_numbers) {
                for (supported_line_nums, 0..) |ln, idx| {
                    if (item_y >= screen_h) break;
                    const is_sel = std.mem.eql(u8, self.config.line_numbers, ln);
                    const prefix = if (is_sel) " * " else "   ";
                    const str = std.fmt.bufPrint(&buf, "{s}{s}", .{ prefix, ln }) catch " error";
                    ren.drawText(drop_x + 1, item_y, str, if (is_sel) theme.fg_accent else theme.fg_primary, theme.bg_sidebar, false, false);
                    if (idx == self.hover_dropdown_idx) ren.drawText(drop_x + 1, item_y, "▋", theme.fg_accent, theme.bg_sidebar, true, false);
                    item_y += 1;
                }
            } else if (self.active_dropdown == .colorcolumn) {
                for (supported_colorcolumns, 0..) |column, idx| {
                    if (item_y >= screen_h) break;
                    const is_sel = std.mem.eql(u8, self.config.colorcolumn, column);
                    const prefix = if (is_sel) " * " else "   ";
                    const label = if (column.len == 0) "off (default)" else column;
                    const str = std.fmt.bufPrint(&buf, "{s}{s}", .{ prefix, label }) catch " error";
                    ren.drawText(drop_x + 1, item_y, str, if (is_sel) theme.fg_accent else theme.fg_primary, theme.bg_sidebar, false, false);
                    if (idx == self.hover_dropdown_idx) ren.drawText(drop_x + 1, item_y, "▋", theme.fg_accent, theme.bg_sidebar, true, false);
                    item_y += 1;
                }
            } else if (self.active_dropdown == .mode) {
                for (supported_modes, 0..) |m, idx| {
                    if (item_y >= screen_h) break;
                    const is_sel = std.mem.eql(u8, self.config.mode, m);
                    const prefix = if (is_sel) " * " else "   ";
                    const str = std.fmt.bufPrint(&buf, "{s}{s}", .{ prefix, m }) catch " error";
                    ren.drawText(drop_x + 1, item_y, str, if (is_sel) theme.fg_accent else theme.fg_primary, theme.bg_sidebar, false, false);
                    if (idx == self.hover_dropdown_idx) ren.drawText(drop_x + 1, item_y, "▋", theme.fg_accent, theme.bg_sidebar, true, false);
                    item_y += 1;
                }
            }
        }

        if (self.popup_active) {
            const popup = primitives.Modal.centered(screen_w, screen_h, 30, 7, 0);
            const px = popup.rect.x;
            const py = popup.rect.y;
            primitives.drawModalFrame(ren, popup, .rounded, theme.fg_primary, theme.bg_sidebar, theme.border_color, theme.bg_editor);

            ren.drawText(px + 2, py + 1, " Unsaved Changes ", theme.fg_accent, theme.bg_sidebar, true, false);
            ren.drawText(px + 2, py + 3, "Quit without saving?", theme.fg_primary, theme.bg_sidebar, false, false);

            const palette = primitives.Palette{ .fg = theme.fg_secondary, .bg = theme.bg_sidebar, .accent_fg = theme.fg_primary, .accent_bg = theme.bg_accent, .muted_fg = theme.fg_secondary };
            (primitives.Button{ .rect = .{ .x = px + 3, .y = py + 5, .w = 8, .h = 1 }, .state = if (self.popup_btn_idx == 0) .focused else .normal }).draw(ren, "Yes", palette);
            (primitives.Button{ .rect = .{ .x = px + 15, .y = py + 5, .w = 8, .h = 1 }, .state = if (self.popup_btn_idx == 1) .focused else .normal }).draw(ren, "No", palette);
        } else if (self.duplicate_warning) {
            const warning = primitives.Modal.centered(screen_w, screen_h, 40, 7, 0);
            const px = warning.rect.x;
            const py = warning.rect.y;
            primitives.drawModalFrame(ren, warning, .rounded, theme.fg_primary, theme.bg_sidebar, theme.border_color, theme.bg_editor);

            ren.drawText(px + 2, py + 1, " Duplicate Keybinding ", theme.fg_secondary, theme.bg_sidebar, true, false);
            ren.drawText(px + 2, py + 3, "This key is already in use!", theme.fg_primary, theme.bg_sidebar, false, false);
            (primitives.Button{ .rect = .{ .x = px + 14, .y = py + 5, .w = 8, .h = 1 }, .state = .focused }).draw(ren, "OK", .{ .fg = theme.fg_secondary, .bg = theme.bg_sidebar, .accent_fg = theme.fg_primary, .accent_bg = theme.bg_accent, .muted_fg = theme.fg_secondary });
        }

        if (self.selected_plugin) |p| {
            const plugin_modal = primitives.Modal.centered(screen_w, screen_h, 50, 12, 0);
            const px = plugin_modal.rect.x;
            const py = plugin_modal.rect.y;
            const pw = plugin_modal.rect.w;
            const ph = plugin_modal.rect.h;
            primitives.drawModalFrame(ren, plugin_modal, .rounded, theme.fg_primary, theme.bg_sidebar, theme.border_color, theme.bg_editor);

            var title_buf: [64]u8 = undefined;
            const title_str = std.fmt.bufPrint(&title_buf, " {s} ", .{p.name}) catch " Plugin Info ";
            ren.drawText(px + 2, py, title_str, theme.fg_accent, theme.bg_sidebar, true, false);

            ren.drawText(px + 2, py + 2, p.full_name, theme.fg_primary, theme.bg_sidebar, true, false);

            var stars_buf: [32]u8 = undefined;
            const stars_str = if (self.config.nerd_fonts)
                std.fmt.bufPrint(&stars_buf, "󰓎 {d} stars", .{p.stars}) catch "Stars"
            else
                std.fmt.bufPrint(&stars_buf, "★ {d} stars", .{p.stars}) catch "Stars";
            ren.drawText(px + 2, py + 3, stars_str, .{ .rgb = .{ .r = 250, .g = 200, .b = 20 } }, theme.bg_sidebar, false, false);

            var desc_y = py + 5;
            var start_char: usize = 0;
            while (start_char < p.description.len and desc_y < py + ph - 3) {
                const end_char = @min(p.description.len, start_char + 44);
                ren.drawText(px + 2, desc_y, p.description[start_char..end_char], theme.fg_secondary, theme.bg_sidebar, false, false);
                start_char = end_char;
                desc_y += 1;
            }

            const palette = primitives.Palette{ .fg = theme.fg_secondary, .bg = theme.bg_sidebar, .accent_fg = theme.fg_primary, .accent_bg = theme.bg_accent, .muted_fg = theme.fg_secondary };
            (primitives.Button{ .rect = .{ .x = px + 3, .y = py + ph - 2, .w = 22, .h = 1 }, .state = if (self.popup_btn_idx == 0) .focused else .normal }).draw(ren, "Edit Configuration", palette);
            (primitives.Button{ .rect = .{ .x = px + pw - 14, .y = py + ph - 2, .w = 10, .h = 1 }, .state = if (self.popup_btn_idx == 1) .focused else .normal }).draw(ren, "Close", palette);
        }
    }

    pub fn handleKey(self: *SettingsWidget, key: []const u8) bool {
        if (self.selected_plugin) |p| {
            if (std.mem.eql(u8, key, "<Esc>") or std.mem.eql(u8, key, "q")) {
                self.selected_plugin = null;
                return true;
            }
            if (std.mem.eql(u8, key, "h") or std.mem.eql(u8, key, "<Left>") or std.mem.eql(u8, key, "l") or std.mem.eql(u8, key, "<Right>") or std.mem.eql(u8, key, "<Tab>")) {
                self.popup_btn_idx = (self.popup_btn_idx + 1) % 2;
                return true;
            }
            if (std.mem.eql(u8, key, "<Enter>") or std.mem.eql(u8, key, "<CR>") or std.mem.eql(u8, key, "<Space>")) {
                if (self.popup_btn_idx == 0) {
                    self.editConfig(p) catch {};
                } else {
                    self.selected_plugin = null;
                }
                return true;
            }
            return true;
        }

        if (self.popup_active) {
            if (std.mem.eql(u8, key, "<Esc>")) {
                self.popup_active = false;
                return true;
            }
            return false;
        }

        if (self.active_dropdown != .none) {
            if (std.mem.eql(u8, key, "<Esc>")) {
                self.active_dropdown = .none;
                return true;
            }
            const items_len = switch (self.active_dropdown) {
                .theme => self.themes.items.len,
                .indent_size => supported_indents.len,
                .indent_type => supported_indent_types.len,
                .line_numbers => supported_line_nums.len,
                .colorcolumn => supported_colorcolumns.len,
                .split_separator => supported_split_seps.len,
                .mode => supported_modes.len,
                .none => 0,
            };
            if (std.mem.eql(u8, key, "j") or std.mem.eql(u8, key, "<Down>")) {
                if (self.hover_dropdown_idx < items_len - 1) {
                    var next_idx = self.hover_dropdown_idx + 1;
                    if (self.active_dropdown == .theme) {
                        while (next_idx < items_len and std.mem.startsWith(u8, self.themes.items[next_idx], "---")) : (next_idx += 1) {}
                    }
                    if (next_idx < items_len) {
                        self.hover_dropdown_idx = next_idx;
                        if (self.active_dropdown == .theme) {
                            const max_visible_themes = 8;
                            if (self.hover_dropdown_idx >= self.dropdown_scroll_offset + max_visible_themes) {
                                self.dropdown_scroll_offset = self.hover_dropdown_idx - (max_visible_themes - 1);
                            }
                        }
                    }
                }
                return true;
            } else if (std.mem.eql(u8, key, "k") or std.mem.eql(u8, key, "<Up>")) {
                if (self.hover_dropdown_idx > 0) {
                    var prev_idx = self.hover_dropdown_idx - 1;
                    if (self.active_dropdown == .theme) {
                        while (prev_idx > 0 and std.mem.startsWith(u8, self.themes.items[prev_idx], "---")) : (prev_idx -= 1) {}
                        if (std.mem.startsWith(u8, self.themes.items[prev_idx], "---")) {
                            return true;
                        }
                    }
                    self.hover_dropdown_idx = prev_idx;
                    if (self.active_dropdown == .theme) {
                        if (self.hover_dropdown_idx < self.dropdown_scroll_offset) {
                            self.dropdown_scroll_offset = self.hover_dropdown_idx;
                        }
                    }
                }
                return true;
            } else if (std.mem.eql(u8, key, "<Enter>") or std.mem.eql(u8, key, "<CR>") or std.mem.eql(u8, key, "o") or std.mem.eql(u8, key, "<Space>")) {
                const idx = self.hover_dropdown_idx;
                if (self.active_dropdown == .theme) {
                    const t = self.themes.items[idx];
                    if (!std.mem.startsWith(u8, t, "---")) {
                        self.allocator.free(self.config.theme);
                        self.config.theme = self.allocator.dupe(u8, t) catch self.config.theme;
                        self.has_unsaved_changes = true;
                        self.active_dropdown = .none;
                    }
                    return true;
                } else if (self.active_dropdown == .split_separator) {
                    self.allocator.free(self.config.split_separator);
                    self.config.split_separator = self.allocator.dupe(u8, supported_split_seps[idx]) catch self.config.split_separator;
                } else if (self.active_dropdown == .indent_size) {
                    self.config.indent_size = supported_indents[idx];
                } else if (self.active_dropdown == .indent_type) {
                    self.config.use_tabs = std.mem.eql(u8, supported_indent_types[idx], "tabs");
                } else if (self.active_dropdown == .line_numbers) {
                    self.allocator.free(self.config.line_numbers);
                    self.config.line_numbers = self.allocator.dupe(u8, supported_line_nums[idx]) catch self.config.line_numbers;
                } else if (self.active_dropdown == .colorcolumn) {
                    self.allocator.free(self.config.colorcolumn);
                    self.config.colorcolumn = self.allocator.dupe(u8, supported_colorcolumns[idx]) catch self.config.colorcolumn;
                } else if (self.active_dropdown == .mode) {
                    self.allocator.free(self.config.mode);
                    self.config.mode = self.allocator.dupe(u8, supported_modes[idx]) catch self.config.mode;
                }
                self.has_unsaved_changes = true;
                self.active_dropdown = .none;
                return true;
            }
            return false;
        }

        if (self.duplicate_warning) {
            if (std.mem.eql(u8, key, "<Enter>") or std.mem.eql(u8, key, "<CR>") or std.mem.eql(u8, key, "<Esc>")) {
                self.duplicate_warning = false;
                return true;
            }
            return true;
        }

        if (self.active_binding) |idx| {
            if (std.mem.eql(u8, key, "<Esc>")) {
                self.active_binding = null;
                return true;
            }

            const is_duplicate =
                (idx != 0 and std.mem.eql(u8, self.config.keybindings.toggle_terminal, key)) or
                (idx != 1 and std.mem.eql(u8, self.config.keybindings.toggle_explorer, key)) or
                (idx != 2 and std.mem.eql(u8, self.config.keybindings.toggle_zen, key)) or
                (idx != 3 and std.mem.eql(u8, self.config.keybindings.new_file, key)) or
                (idx != 4 and std.mem.eql(u8, self.config.keybindings.find_file, key)) or
                (idx != 5 and std.mem.eql(u8, self.config.keybindings.quit, key));

            if (is_duplicate) {
                self.duplicate_warning = true;
                self.active_binding = null;
                return true;
            }

            const duped = self.allocator.dupe(u8, key) catch key;
            if (idx == 0) {
                self.allocator.free(self.config.keybindings.toggle_terminal);
                self.config.keybindings.toggle_terminal = duped;
            } else if (idx == 1) {
                self.allocator.free(self.config.keybindings.toggle_explorer);
                self.config.keybindings.toggle_explorer = duped;
            } else if (idx == 2) {
                self.allocator.free(self.config.keybindings.toggle_zen);
                self.config.keybindings.toggle_zen = duped;
            } else if (idx == 3) {
                self.allocator.free(self.config.keybindings.new_file);
                self.config.keybindings.new_file = duped;
            } else if (idx == 4) {
                self.allocator.free(self.config.keybindings.find_file);
                self.config.keybindings.find_file = duped;
            } else if (idx == 5) {
                self.allocator.free(self.config.keybindings.quit);
                self.config.keybindings.quit = duped;
            }

            self.active_binding = null;
            self.has_unsaved_changes = true;
            return true;
        }

        if (self.keyboard_focus == .tabs) {
            if (std.mem.eql(u8, key, "j") or std.mem.eql(u8, key, "<Down>")) {
                if (self.active_tab + 1 < tabs.len) {
                    self.active_tab += 1;
                    self.hover_row = 0;
                }
                return true;
            } else if (std.mem.eql(u8, key, "k") or std.mem.eql(u8, key, "<Up>")) {
                if (self.active_tab > 0) {
                    self.active_tab -= 1;
                    self.hover_row = 0;
                }
                return true;
            } else if (std.mem.eql(u8, key, "l") or std.mem.eql(u8, key, "<Right>") or std.mem.eql(u8, key, "<Enter>") or std.mem.eql(u8, key, "<CR>")) {
                self.keyboard_focus = .content;
                self.hover_row = 0;
                return true;
            }
        } else if (self.keyboard_focus == .content) {
            if (std.mem.eql(u8, key, "h") or std.mem.eql(u8, key, "<Left>") or std.mem.eql(u8, key, "<Esc>")) {
                self.keyboard_focus = .tabs;
                return true;
            }

            const max_items: usize = switch (self.active_tab) {
                0 => 4,
                1 => 3,
                2 => 5,
                3 => 2 + self.installed_plugins.items.len,
                4 => 6,
                5 => 1,
                else => 0,
            };

            if (std.mem.eql(u8, key, "j") or std.mem.eql(u8, key, "<Down>")) {
                if (self.hover_row < max_items - 1) {
                    self.hover_row += 1;
                    if (self.active_tab == 3 and self.hover_row >= 2) {
                        const plugin_idx = self.hover_row - 2;
                        if (plugin_idx >= self.plugin_scroll_offset + 6) {
                            self.plugin_scroll_offset = plugin_idx - 5;
                        }
                    }
                }
                return true;
            } else if (std.mem.eql(u8, key, "k") or std.mem.eql(u8, key, "<Up>")) {
                if (self.hover_row > 0) {
                    self.hover_row -= 1;
                    if (self.active_tab == 3 and self.hover_row >= 2) {
                        const plugin_idx = self.hover_row - 2;
                        if (plugin_idx < self.plugin_scroll_offset) {
                            self.plugin_scroll_offset = plugin_idx;
                        }
                    }
                }
                return true;
            } else if (std.mem.eql(u8, key, "<Enter>") or std.mem.eql(u8, key, "<CR>") or std.mem.eql(u8, key, "o") or std.mem.eql(u8, key, "<Space>")) {
                if (self.active_tab == 0) {
                    if (self.hover_row == 0) self.config.clip = !self.config.clip;
                    if (self.hover_row == 1) {
                        self.active_dropdown = .mode;
                        self.hover_dropdown_idx = 0;
                        self.dropdown_scroll_offset = 0;
                    }
                    if (self.hover_row == 2) self.config.autocomplete = !self.config.autocomplete;
                    if (self.hover_row == 3) self.config.autoindent = !self.config.autoindent;
                } else if (self.active_tab == 1) {
                    if (self.hover_row == 0) {
                        self.openThemeDropdown();
                    }
                    if (self.hover_row == 1) {
                        self.active_dropdown = .split_separator;
                        self.hover_dropdown_idx = 0;
                        self.dropdown_scroll_offset = 0;
                    }
                    if (self.hover_row == 2) self.config.nerd_fonts = !self.config.nerd_fonts;
                } else if (self.active_tab == 2) {
                    if (self.hover_row == 0) {
                        self.active_dropdown = .indent_type;
                        self.hover_dropdown_idx = 0;
                        self.dropdown_scroll_offset = 0;
                    }
                    if (self.hover_row == 1) {
                        self.active_dropdown = .indent_size;
                        self.hover_dropdown_idx = 0;
                        self.dropdown_scroll_offset = 0;
                    }
                    if (self.hover_row == 2) self.config.wrap = !self.config.wrap;
                    if (self.hover_row == 3) {
                        self.active_dropdown = .line_numbers;
                        self.hover_dropdown_idx = 0;
                        self.dropdown_scroll_offset = 0;
                    }
                    if (self.hover_row == 4) {
                        self.active_dropdown = .colorcolumn;
                        self.hover_dropdown_idx = 0;
                        self.dropdown_scroll_offset = 0;
                    }
                } else if (self.active_tab == 3) {
                    if (self.hover_row == 0) self.open_mason = true;
                    if (self.hover_row == 1) self.open_lazy = true;
                    if (self.hover_row >= 2) {
                        const plugin_idx = self.hover_row - 2;
                        if (plugin_idx < self.installed_plugins.items.len) {
                            self.selected_plugin = self.installed_plugins.items[plugin_idx];
                            self.popup_btn_idx = 0;
                        }
                    }
                } else if (self.active_tab == 4) {
                    self.active_binding = self.hover_row;
                } else if (self.active_tab == 5) {
                    if (self.software_update_status != .running) self.software_update_requested = true;
                    return true;
                }
                self.has_unsaved_changes = true;
                return true;
            }
        }

        if (std.mem.eql(u8, key, "<Esc>")) {
            if (self.has_unsaved_changes) {
                self.popup_active = true;
            } else {
                self.is_open = false;
            }
            return true;
        }
        return false;
    }

    pub fn handleMouse(self: *SettingsWidget, mx: u16, my: u16, screen_w: u16, screen_h: u16) bool {
        if (!self.is_open) return false;

        if (self.selected_plugin) |p| {
            const plugin_modal = primitives.Modal.centered(screen_w, screen_h, 50, 12, 0);
            const px = plugin_modal.rect.x;
            const py = plugin_modal.rect.y;
            const pw = plugin_modal.rect.w;
            const ph = plugin_modal.rect.h;

            if (plugin_modal.contains(mx, my)) {
                if (my == py + ph - 2) {
                    if ((primitives.Button{ .rect = .{ .x = px + 3, .y = py + ph - 2, .w = 22, .h = 1 } }).hit(mx, my)) {
                        self.editConfig(p) catch {};
                    } else if ((primitives.Button{ .rect = .{ .x = px + pw - 14, .y = py + ph - 2, .w = 10, .h = 1 } }).hit(mx, my)) {
                        self.selected_plugin = null;
                    }
                }
            } else {
                self.selected_plugin = null;
            }
            return true;
        }

        if (self.duplicate_warning) {
            self.duplicate_warning = false;
            return true;
        }

        if (self.active_binding != null) {
            self.active_binding = null;
            return true;
        }

        if (self.popup_active) {
            const popup = primitives.Modal.centered(screen_w, screen_h, 30, 7, 0);
            const px = popup.rect.x;
            const py = popup.rect.y;

            if (popup.contains(mx, my)) {
                if (my == py + 5) {
                    if ((primitives.Button{ .rect = .{ .x = px + 3, .y = py + 5, .w = 8, .h = 1 } }).hit(mx, my)) {
                        const old_cfg = self.config;
                        if (SettingsConfig.load(self.allocator, self.settings_path)) |new_cfg| {
                            self.config = new_cfg;
                            self.allocator.free(old_cfg.theme);
                            self.allocator.free(old_cfg.line_numbers);
                            self.allocator.free(old_cfg.colorcolumn);
                            self.allocator.free(old_cfg.split_separator);
                            self.allocator.free(old_cfg.mode);
                            self.allocator.free(old_cfg.keybindings.toggle_terminal);
                            self.allocator.free(old_cfg.keybindings.toggle_explorer);
                            self.allocator.free(old_cfg.keybindings.toggle_zen);
                            self.allocator.free(old_cfg.keybindings.new_file);
                            self.allocator.free(old_cfg.keybindings.find_file);
                            self.allocator.free(old_cfg.keybindings.quit);
                        } else |_| {}
                        self.has_unsaved_changes = false;
                        self.popup_active = false;
                        self.is_open = false;
                    } else if ((primitives.Button{ .rect = .{ .x = px + 15, .y = py + 5, .w = 8, .h = 1 } }).hit(mx, my)) {
                        self.popup_active = false;
                    }
                }
                return true;
            }
            // Consume clicks outside the popup so they don't hit settings
            return true;
        }

        const content_x = (screen_w -| @min(80, screen_w -| 10)) / 2 + 22;
        const content_y = (screen_h -| @min(24, screen_h -| 10)) / 2 + 2;

        if (self.active_dropdown != .none) {
            const drop_x = content_x + 10;
            var drop_y = content_y + 3;
            var items_len: usize = 0;
            var drop_w: u16 = 20;

            if (self.active_dropdown == .theme) {
                items_len = self.themes.items.len;
                drop_w = 22;
                drop_y = content_y + 3;
            } else if (self.active_dropdown == .split_separator) {
                items_len = supported_split_seps.len;
                drop_y = content_y + 5;
            } else if (self.active_dropdown == .indent_size) {
                items_len = supported_indents.len;
                drop_y = content_y + 5;
            } else if (self.active_dropdown == .indent_type) {
                items_len = supported_indent_types.len;
                drop_y = content_y + 3;
            } else if (self.active_dropdown == .line_numbers) {
                items_len = supported_line_nums.len;
                drop_y = content_y + 9;
            } else if (self.active_dropdown == .colorcolumn) {
                items_len = supported_colorcolumns.len;
                drop_y = content_y + 11;
            } else if (self.active_dropdown == .mode) {
                items_len = supported_modes.len;
                drop_w = 16;
                drop_y = content_y + 5;
            }

            const max_visible = if (self.active_dropdown == .theme) @min(items_len, 8) else items_len;
            const drop_h = @as(u16, @intCast(max_visible)) + 2;

            if (mx >= drop_x and mx < drop_x + drop_w and my > drop_y and my < drop_y + drop_h - 1) {
                const click_offset = my - drop_y - 1;
                const idx = if (self.active_dropdown == .theme) self.dropdown_scroll_offset + click_offset else click_offset;
                var changed = false;
                if (self.active_dropdown == .theme) {
                    if (idx < self.themes.items.len) {
                        const t = self.themes.items[idx];
                        if (!std.mem.startsWith(u8, t, "---")) {
                            const new_theme = self.allocator.dupe(u8, t) catch return true;
                            self.allocator.free(self.config.theme);
                            self.config.theme = new_theme;
                            changed = true;
                        }
                    }
                } else if (self.active_dropdown == .split_separator) {
                    if (idx < supported_split_seps.len) {
                        const new_sep = self.allocator.dupe(u8, supported_split_seps[idx]) catch return true;
                        self.allocator.free(self.config.split_separator);
                        self.config.split_separator = new_sep;
                        changed = true;
                    }
                } else if (self.active_dropdown == .indent_size) {
                    if (idx < supported_indents.len) {
                        self.config.indent_size = supported_indents[idx];
                        changed = true;
                    }
                } else if (self.active_dropdown == .indent_type) {
                    if (idx < supported_indent_types.len) {
                        self.config.use_tabs = std.mem.eql(u8, supported_indent_types[idx], "tabs");
                        changed = true;
                    }
                } else if (self.active_dropdown == .line_numbers) {
                    if (idx < supported_line_nums.len) {
                        const new_ln = self.allocator.dupe(u8, supported_line_nums[idx]) catch return true;
                        self.allocator.free(self.config.line_numbers);
                        self.config.line_numbers = new_ln;
                        changed = true;
                    }
                } else if (self.active_dropdown == .colorcolumn) {
                    if (idx < supported_colorcolumns.len) {
                        const new_column = self.allocator.dupe(u8, supported_colorcolumns[idx]) catch return true;
                        self.allocator.free(self.config.colorcolumn);
                        self.config.colorcolumn = new_column;
                        changed = true;
                    }
                } else if (self.active_dropdown == .mode) {
                    if (idx < supported_modes.len) {
                        const new_mode = self.allocator.dupe(u8, supported_modes[idx]) catch return true;
                        self.allocator.free(self.config.mode);
                        self.config.mode = new_mode;
                        self.config.zen = std.mem.eql(u8, self.config.mode, "zen");
                        self.config.ide = std.mem.eql(u8, self.config.mode, "ide");
                        changed = true;
                    }
                }

                if (changed) {
                    self.has_unsaved_changes = true;
                }
            }
            // Any click while dropdown is open closes the dropdown (and consumes the click)
            self.active_dropdown = .none;
            return true;
        }

        const modal = primitives.Modal.centered(screen_w, screen_h, 80, 24, 5);
        const x = modal.rect.x;
        const y = modal.rect.y;
        const w = modal.rect.w;
        const h = modal.rect.h;

        if (!primitives.usable(modal, 50, 18)) {
            self.is_open = false;
            return true;
        }

        if (modal.contains(mx, my)) {
            // Close button
            if (primitives.containsRect(modal.closeButton(), mx, my)) {
                if (self.has_unsaved_changes) {
                    self.popup_active = true;
                } else {
                    self.is_open = false;
                }
                return true;
            }

            // Save button
            const save_button = primitives.Button{ .rect = .{ .x = x + w - 18, .y = y + h - 2, .w = 16, .h = 1 } };
            if (save_button.hit(mx, my)) {
                if (self.has_unsaved_changes) {
                    self.config.save(self.settings_path) catch {
                        self.save_failed = true;
                        return true;
                    };
                    self.save_failed = false;
                    self.has_unsaved_changes = false;
                    self.needs_apply = true;
                }
                self.is_open = false; // Save & Close
                return true;
            }

            // Tabs
            if (mx >= x + 1 and mx < x + 20) {
                var tab_y: u16 = y + 2;
                for (tabs, 0..) |_, idx| {
                    if (my >= tab_y and my < tab_y + 2) {
                        self.active_tab = idx;
                        return true;
                    }
                    tab_y += 2;
                }
            }

            // Interactive toggles
            if (mx >= content_x) {
                var changed = false;
                switch (self.active_tab) {
                    0 => {
                        if (my == content_y + 2) {
                            self.config.clip = !self.config.clip;
                            changed = true;
                        } else if (my == content_y + 4) {
                            self.active_dropdown = .mode;
                            self.hover_dropdown_idx = 0;
                            self.dropdown_scroll_offset = 0;
                        } else if (my == content_y + 6) {
                            self.config.autocomplete = !self.config.autocomplete;
                            changed = true;
                        } else if (my == content_y + 8) {
                            self.config.autoindent = !self.config.autoindent;
                            changed = true;
                        }
                    },
                    1 => {
                        if (my == content_y + 2) {
                            self.openThemeDropdown();
                        } else if (my == content_y + 4) {
                            self.active_dropdown = .split_separator;
                            self.hover_dropdown_idx = 0;
                            self.dropdown_scroll_offset = 0;
                        } else if (my == content_y + 10) {
                            self.active_dropdown = .colorcolumn;
                            self.hover_dropdown_idx = 0;
                            self.dropdown_scroll_offset = 0;
                        } else if (my == content_y + 6) {
                            self.config.nerd_fonts = !self.config.nerd_fonts;
                            changed = true;
                        }
                    },
                    2 => {
                        if (my == content_y + 2) {
                            self.active_dropdown = .indent_type;
                            self.hover_dropdown_idx = 0;
                            self.dropdown_scroll_offset = 0;
                        } else if (my == content_y + 4) {
                            self.active_dropdown = .indent_size;
                            self.hover_dropdown_idx = 0;
                            self.dropdown_scroll_offset = 0;
                        } else if (my == content_y + 6) {
                            self.config.wrap = !self.config.wrap;
                            changed = true;
                        } else if (my == content_y + 8) {
                            self.active_dropdown = .line_numbers;
                            self.hover_dropdown_idx = 0;
                            self.dropdown_scroll_offset = 0;
                        }
                    },
                    3 => {
                        if (my == content_y + 2) {
                            self.open_mason = true;
                        } else if (my == content_y + 4) {
                            self.open_lazy = true;
                        } else if (my >= content_y + 8 and my < content_y + 14) {
                            const click_idx = self.plugin_scroll_offset + (my - (content_y + 8));
                            if (click_idx < self.installed_plugins.items.len) {
                                self.selected_plugin = self.installed_plugins.items[click_idx];
                                self.popup_btn_idx = 0;
                            }
                        }
                    },
                    4 => {
                        for (0..6) |i| {
                            if (my == content_y + 2 + @as(u16, @intCast(i))) {
                                self.active_binding = i;
                                changed = true;
                            }
                        }
                    },
                    5 => {
                        const update_button = primitives.Button{ .rect = .{ .x = content_x, .y = content_y + 6, .w = 28, .h = 1 } };
                        if (update_button.hit(mx, my) and self.software_update_status != .running) {
                            self.software_update_requested = true;
                        }
                    },
                    else => {},
                }
                if (changed) {
                    self.has_unsaved_changes = true;
                }
            }
            return true; // ALWAYS consume the click if it's inside the window!
        }
        return false;
    }
};

test "settings roundtrip preserves canonical mode defaults" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/settings.json", .{tmp.sub_path});
    defer std.testing.allocator.free(path);

    var config = SettingsConfig{};
    try config.save(path);
    var loaded = try SettingsConfig.load(std.testing.allocator, path);
    defer loaded.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("normal", loaded.mode);
    try std.testing.expect(!loaded.ide);
    try std.testing.expect(!loaded.zen);
    try std.testing.expect(!loaded.zen_handoff);
    try std.testing.expect(!loaded.nerd_fonts);
    try std.testing.expectEqualStrings("", loaded.colorcolumn);
}

test "software updater uses the official release installer" {
    try std.testing.expect(std.mem.indexOf(u8, SettingsWidget.software_updater, "https://raw.githubusercontent.com/Rouboufy/vide/main/setup.sh") != null);
    try std.testing.expect(std.mem.indexOf(u8, SettingsWidget.software_updater, "--no-plugins") != null);
    try std.testing.expect(std.mem.indexOf(u8, SettingsWidget.software_updater, "success") != null);
    try std.testing.expect(std.mem.indexOf(u8, SettingsWidget.software_updater, "failure") != null);
}
