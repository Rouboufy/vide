const std = @import("std");
const renderer = @import("../renderer.zig");
const Color = renderer.Color;

pub const Keybindings = struct {
    toggle_explorer: []const u8 = "<C-e>", // Ctrl-e
    toggle_terminal: []const u8 = "<C-t>", // Ctrl-t
    toggle_zen: []const u8 = "<C-z>", // Ctrl-z
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
    ide: bool = true,
    autocomplete: bool = true,
    autoindent: bool = true,
    theme: []const u8 = "kanagawa",
    indent_size: u8 = 4,
    use_tabs: bool = false,
    wrap: bool = false,
    line_numbers: []const u8 = "relative",
    split_separator: []const u8 = "│",
    keybindings: Keybindings = .{},
    nerd_fonts: bool = true,
    mode: []const u8 = "normal",

    pub fn load(allocator: std.mem.Allocator, path: []const u8) !SettingsConfig {
        const path_z = try allocator.dupeZ(u8, path);
        defer allocator.free(path_z);
        
        const fd = std.posix.openatZ(std.posix.AT.FDCWD, path_z, .{ .ACCMODE = .RDONLY }, 0) catch |err| {
            if (err == error.FileNotFound) {
                var config = SettingsConfig{};
                config.theme = try allocator.dupe(u8, config.theme);
                config.line_numbers = try allocator.dupe(u8, config.line_numbers);
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
        defer _ = std.os.linux.close(fd);

        var buf: [4096]u8 = undefined;
        const len = std.os.linux.read(fd, &buf, buf.len);

        const parsed = try std.json.parseFromSlice(SettingsConfig, allocator, buf[0..len], .{ .ignore_unknown_fields = true });
        defer parsed.deinit();

        var config = parsed.value;
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
        
        const path_z = try alloc.dupeZ(u8, path);
        const fd = try std.posix.openatZ(std.posix.AT.FDCWD, path_z, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o644);
        defer _ = std.os.linux.close(fd);

        var buf: std.ArrayList(u8) = .empty;
        defer buf.deinit(alloc);

        var aw: std.Io.Writer.Allocating = .fromArrayList(alloc, &buf);
        try std.json.Stringify.value(self.*, .{}, &aw.writer);
        var out_buf = aw.toArrayList();
        defer out_buf.deinit(alloc);
        _ = std.os.linux.write(fd, out_buf.items.ptr, out_buf.items.len);
    }
};

pub const SettingsWidget = struct {
    is_open: bool = false,
    active_tab: usize = 0,
    allocator: std.mem.Allocator,
    config: SettingsConfig,
    needs_apply: bool = false,
    settings_path: []const u8,

    active_dropdown: DropdownType = .none,

    has_unsaved_changes: bool = false,
    popup_active: bool = false,

    active_binding: ?usize = null,
    duplicate_warning: bool = false,

    open_mason: bool = false,
    open_lazy: bool = false,

    pub const DropdownType = enum { none, theme, indent_size, indent_type, line_numbers, split_separator, mode };

    pub const supported_modes = [_][]const u8{ "normal", "ide", "zen" };

    pub const supported_themes = [_][]const u8{
        "vscode", "kanagawa", "tokyonight-night", "tokyonight-storm", "tokyonight-day", 
        "catppuccin-latte", "catppuccin-frappe", "catppuccin-macchiato", "catppuccin-mocha",
        "gruvbox", "rose-pine", "rose-pine-moon", "rose-pine-dawn", "nord", "cyberdream"
    };

    pub const supported_indents = [_]u8{ 2, 4, 8 };
    pub const supported_indent_types = [_][]const u8{ "spaces", "tabs" };
    pub const supported_line_nums = [_][]const u8{ "relative", "normal", "off" };
    pub const supported_split_seps = [_][]const u8{ "│", "┃", "║", "┊", " " };

    pub const tabs = [_][]const u8{
        "General",
        "Appearance",
        "Editor",
        "Plugins",
        "Keybindings",
    };

    pub fn init(allocator: std.mem.Allocator, settings_path: []const u8) SettingsWidget {
        const config = SettingsConfig.load(allocator, settings_path) catch blk: {
            var cfg = SettingsConfig{};
            cfg.theme = allocator.dupe(u8, cfg.theme) catch cfg.theme;
            cfg.line_numbers = allocator.dupe(u8, cfg.line_numbers) catch cfg.line_numbers;
            cfg.split_separator = allocator.dupe(u8, cfg.split_separator) catch cfg.split_separator;
            cfg.keybindings.toggle_terminal = allocator.dupe(u8, cfg.keybindings.toggle_terminal) catch cfg.keybindings.toggle_terminal;
            cfg.keybindings.toggle_explorer = allocator.dupe(u8, cfg.keybindings.toggle_explorer) catch cfg.keybindings.toggle_explorer;
            cfg.keybindings.toggle_zen = allocator.dupe(u8, cfg.keybindings.toggle_zen) catch cfg.keybindings.toggle_zen;
            cfg.keybindings.new_file = allocator.dupe(u8, cfg.keybindings.new_file) catch cfg.keybindings.new_file;
            cfg.keybindings.find_file = allocator.dupe(u8, cfg.keybindings.find_file) catch cfg.keybindings.find_file;
            cfg.keybindings.quit = allocator.dupe(u8, cfg.keybindings.quit) catch cfg.keybindings.quit;
            break :blk cfg;
        };
        return .{
            .is_open = false,
            .active_tab = 0,
            .allocator = allocator,
            .config = config,
            .needs_apply = true,
            .settings_path = settings_path,
        };
    }

    pub fn deinit(self: *SettingsWidget) void {
        self.allocator.free(self.config.theme);
        self.allocator.free(self.config.line_numbers);
        self.allocator.free(self.config.split_separator);
        self.allocator.free(self.config.mode);
        self.allocator.free(self.config.keybindings.toggle_terminal);
        self.allocator.free(self.config.keybindings.toggle_explorer);
        self.allocator.free(self.config.keybindings.toggle_zen);
        self.allocator.free(self.config.keybindings.new_file);
        self.allocator.free(self.config.keybindings.find_file);
        self.allocator.free(self.config.keybindings.quit);
    }

    pub fn draw(self: *const SettingsWidget, ren: *renderer.Renderer, screen_w: u16, screen_h: u16, theme: anytype) void {
        if (!self.is_open) return;

        const w: u16 = @min(80, screen_w -| 10);
        const h: u16 = @min(24, screen_h -| 10);
        const x: u16 = (screen_w -| w) / 2;
        const y: u16 = (screen_h -| h) / 2;

        // Drop shadow
        for (y + 1..y + h + 1) |by| {
            for (x + 2..x + w + 2) |bx| {
                if (bx >= screen_w or by >= screen_h) continue;
                ren.drawText(@intCast(bx), @intCast(by), " ", theme.bg_editor, theme.bg_editor, false, false);
            }
        }

        // Background
        for (y..y + h) |by| {
            for (x..x + w) |bx| {
                ren.drawText(@intCast(bx), @intCast(by), " ", theme.fg_primary, theme.bg_sidebar, false, false);
            }
        }

        // Border
        for (x..x + w) |bx| {
            ren.drawText(@intCast(bx), y, "─", theme.border_color, theme.bg_sidebar, false, false);
            ren.drawText(@intCast(bx), y + h - 1, "─", theme.border_color, theme.bg_sidebar, false, false);
        }
        for (y..y + h) |by| {
            ren.drawText(x, @intCast(by), "│", theme.border_color, theme.bg_sidebar, false, false);
            ren.drawText(x + w - 1, @intCast(by), "│", theme.border_color, theme.bg_sidebar, false, false);
        }
        ren.drawText(x, y, "╭", theme.border_color, theme.bg_sidebar, false, false);
        ren.drawText(x + w - 1, y, "╮", theme.border_color, theme.bg_sidebar, false, false);
        ren.drawText(x, y + h - 1, "╰", theme.border_color, theme.bg_sidebar, false, false);
        ren.drawText(x + w - 1, y + h - 1, "╯", theme.border_color, theme.bg_sidebar, false, false);

        // Title
        ren.drawText(x + 2, y, " Vide Settings ", theme.fg_accent, theme.bg_sidebar, true, false);

        // Close button
        ren.drawText(x + w - 4, y, if (self.config.nerd_fonts) " 󰅖 " else " x ", .{ .rgb = .{ .r = 255, .g = 85, .b = 85 } }, theme.bg_sidebar, false, false);

        // Save button
        const save_color = if (self.has_unsaved_changes) theme.fg_accent else theme.fg_secondary;
        ren.drawText(x + w - 11, y + h - 2, "[ Save ]", save_color, theme.bg_sidebar, false, false);

        // Tabs
        var tab_y: u16 = y + 2;
        for (tabs, 0..) |tab, idx| {
            const is_active = (idx == self.active_tab);
            const fg = if (is_active) theme.fg_primary else theme.fg_secondary;
            if (is_active) {
                ren.drawText(x + 1, tab_y, " ┃ ", theme.fg_accent, theme.bg_sidebar, true, false);
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
            },
            3 => {
                ren.drawText(content_x, content_y, "Plugins", theme.fg_primary, theme.bg_sidebar, true, false);
                
                // Mason Button
                const mason_btn = " [ Mason Settings... ] ";
                ren.drawText(content_x, content_y + 2, mason_btn, theme.bg_sidebar, theme.fg_accent, true, false);
                
                // Plugin Manager Button
                const lazy_btn = " [ Plugin Manager... ] ";
                ren.drawText(content_x, content_y + 4, lazy_btn, theme.bg_sidebar, theme.fg_accent, true, false);
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
                    
                    const draw_str = std.fmt.bufPrint(&buf, "{s}:  [ {s} ]", .{action, key_str}) catch action;
                    const color = if (self.active_binding == i) theme.fg_accent else theme.fg_primary;
                    ren.drawText(content_x, content_y + 2 + @as(u16, @intCast(i * 2)), draw_str, color, theme.bg_sidebar, false, false);
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
                
                ren.drawText(content_x, content_y + 14, "Window Splits & Layout (Static):", theme.fg_primary, theme.bg_sidebar, true, false);
                for (static_actions, 0..) |sa, sa_idx| {
                    ren.drawText(content_x, content_y + 15 + @as(u16, @intCast(sa_idx)), sa, theme.fg_secondary, theme.bg_sidebar, false, false);
                }
            },
            else => {},
        }

        // Draw active dropdown if any
        if (self.active_dropdown != .none) {
            const drop_x = content_x + 10;
            var drop_y = content_y + 3; // roughly below the selector
            var items_len: usize = 0;
            var drop_w: u16 = 20;

            if (self.active_dropdown == .theme) {
                items_len = supported_themes.len;
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
            } else if (self.active_dropdown == .mode) {
                items_len = supported_modes.len;
                drop_w = 16;
                drop_y = content_y + 5;
            }

            // clamp drop height to screen_h if it's too tall, or just draw
            const drop_h = @as(u16, @intCast(items_len)) + 2;
            
            // Draw drop shadow for dropdown
            for (drop_y + 1..drop_y + drop_h + 1) |by| {
                for (drop_x + 1..drop_x + drop_w + 1) |bx| {
                    if (bx >= screen_w or by >= screen_h) continue;
                    ren.drawText(@intCast(bx), @intCast(by), " ", theme.bg_editor, theme.bg_editor, false, false);
                }
            }
            
            // Background & Border
            for (drop_y..drop_y + drop_h) |by| {
                for (drop_x..drop_x + drop_w) |bx| {
                    if (bx >= screen_w or by >= screen_h) continue;
                    if (by == drop_y or by == drop_y + drop_h - 1) {
                        ren.drawText(@intCast(bx), @intCast(by), "─", theme.border_color, theme.bg_sidebar, false, false);
                    } else if (bx == drop_x or bx == drop_x + drop_w - 1) {
                        ren.drawText(@intCast(bx), @intCast(by), "│", theme.border_color, theme.bg_sidebar, false, false);
                    } else {
                        ren.drawText(@intCast(bx), @intCast(by), " ", theme.fg_primary, theme.bg_sidebar, false, false);
                    }
                }
            }
            ren.drawText(drop_x, drop_y, "╭", theme.border_color, theme.bg_sidebar, false, false);
            ren.drawText(drop_x + drop_w - 1, drop_y, "╮", theme.border_color, theme.bg_sidebar, false, false);
            ren.drawText(drop_x, drop_y + drop_h - 1, "╰", theme.border_color, theme.bg_sidebar, false, false);
            ren.drawText(drop_x + drop_w - 1, drop_y + drop_h - 1, "╯", theme.border_color, theme.bg_sidebar, false, false);

            // Items
            var item_y = drop_y + 1;
            if (self.active_dropdown == .theme) {
                for (supported_themes) |t| {
                    if (item_y >= screen_h) break;
                    const is_sel = std.mem.eql(u8, self.config.theme, t);
                    const prefix = if (is_sel) " * " else "   ";
                    const str = std.fmt.bufPrint(&buf, "{s}{s}", .{prefix, t}) catch " error";
                    ren.drawText(drop_x + 1, item_y, str, if (is_sel) theme.fg_accent else theme.fg_primary, theme.bg_sidebar, false, false);
                    item_y += 1;
                }
            } else if (self.active_dropdown == .split_separator) {
                for (supported_split_seps) |s| {
                    if (item_y >= screen_h) break;
                    const is_sel = std.mem.eql(u8, self.config.split_separator, s);
                    const prefix = if (is_sel) " * " else "   ";
                    const str = std.fmt.bufPrint(&buf, "{s}{s}", .{prefix, s}) catch " error";
                    ren.drawText(drop_x + 1, item_y, str, if (is_sel) theme.fg_accent else theme.fg_primary, theme.bg_sidebar, false, false);
                    item_y += 1;
                }
            } else if (self.active_dropdown == .indent_size) {
                for (supported_indents) |i| {
                    if (item_y >= screen_h) break;
                    const is_sel = (self.config.indent_size == i);
                    const prefix = if (is_sel) " * " else "   ";
                    const str = std.fmt.bufPrint(&buf, "{s}{d}", .{prefix, i}) catch " error";
                    ren.drawText(drop_x + 1, item_y, str, if (is_sel) theme.fg_accent else theme.fg_primary, theme.bg_sidebar, false, false);
                    item_y += 1;
                }
            } else if (self.active_dropdown == .indent_type) {
                for (supported_indent_types) |t| {
                    if (item_y >= screen_h) break;
                    const is_sel = if (std.mem.eql(u8, t, "tabs")) self.config.use_tabs else !self.config.use_tabs;
                    const prefix = if (is_sel) " * " else "   ";
                    const str = std.fmt.bufPrint(&buf, "{s}{s}", .{prefix, t}) catch " error";
                    ren.drawText(drop_x + 1, item_y, str, if (is_sel) theme.fg_accent else theme.fg_primary, theme.bg_sidebar, false, false);
                    item_y += 1;
                }
            } else if (self.active_dropdown == .line_numbers) {
                for (supported_line_nums) |ln| {
                    if (item_y >= screen_h) break;
                    const is_sel = std.mem.eql(u8, self.config.line_numbers, ln);
                    const prefix = if (is_sel) " * " else "   ";
                    const str = std.fmt.bufPrint(&buf, "{s}{s}", .{prefix, ln}) catch " error";
                    ren.drawText(drop_x + 1, item_y, str, if (is_sel) theme.fg_accent else theme.fg_primary, theme.bg_sidebar, false, false);
                    item_y += 1;
                }
            } else if (self.active_dropdown == .mode) {
                for (supported_modes) |m| {
                    if (item_y >= screen_h) break;
                    const is_sel = std.mem.eql(u8, self.config.mode, m);
                    const prefix = if (is_sel) " * " else "   ";
                    const str = std.fmt.bufPrint(&buf, "{s}{s}", .{prefix, m}) catch " error";
                    ren.drawText(drop_x + 1, item_y, str, if (is_sel) theme.fg_accent else theme.fg_primary, theme.bg_sidebar, false, false);
                    item_y += 1;
                }
            }
        }

        if (self.popup_active) {
            const pw: u16 = 30;
            const ph: u16 = 7;
            const px: u16 = (screen_w -| pw) / 2;
            const py: u16 = (screen_h -| ph) / 2;

            // Drop shadow for popup
            for (py + 1..py + ph + 1) |by| {
                for (px + 1..px + pw + 1) |bx| {
                    if (bx >= screen_w or by >= screen_h) continue;
                    ren.drawText(@intCast(bx), @intCast(by), " ", theme.bg_editor, theme.bg_editor, false, false);
                }
            }

            for (py..py + ph) |by| {
                for (px..px + pw) |bx| {
                    if (bx >= screen_w or by >= screen_h) continue;
                    if (by == py or by == py + ph - 1) {
                        ren.drawText(@intCast(bx), @intCast(by), "─", theme.border_color, theme.bg_sidebar, false, false);
                    } else if (bx == px or bx == px + pw - 1) {
                        ren.drawText(@intCast(bx), @intCast(by), "│", theme.border_color, theme.bg_sidebar, false, false);
                    } else {
                        ren.drawText(@intCast(bx), @intCast(by), " ", theme.fg_primary, theme.bg_sidebar, false, false);
                    }
                }
            }
            ren.drawText(px, py, "╭", theme.border_color, theme.bg_sidebar, false, false);
            ren.drawText(px + pw - 1, py, "╮", theme.border_color, theme.bg_sidebar, false, false);
            ren.drawText(px, py + ph - 1, "╰", theme.border_color, theme.bg_sidebar, false, false);
            ren.drawText(px + pw - 1, py + ph - 1, "╯", theme.border_color, theme.bg_sidebar, false, false);

            ren.drawText(px + 2, py + 1, " Unsaved Changes ", theme.fg_accent, theme.bg_sidebar, true, false);
            ren.drawText(px + 2, py + 3, "Quit without saving?", theme.fg_primary, theme.bg_sidebar, false, false);

            ren.drawText(px + 4, py + 5, "[ Yes ]", theme.fg_secondary, theme.bg_sidebar, false, false);
            ren.drawText(px + 16, py + 5, "[ No ]", theme.fg_accent, theme.bg_sidebar, false, false);
        } else if (self.duplicate_warning) {
            const pw: u16 = 40;
            const ph: u16 = 7;
            const px: u16 = (screen_w -| pw) / 2;
            const py: u16 = (screen_h -| ph) / 2;

            for (py + 1..py + ph + 1) |by| {
                for (px + 1..px + pw + 1) |bx| {
                    if (bx >= screen_w or by >= screen_h) continue;
                    ren.drawText(@intCast(bx), @intCast(by), " ", theme.bg_editor, theme.bg_editor, false, false);
                }
            }

            for (py..py + ph) |by| {
                for (px..px + pw) |bx| {
                    if (bx >= screen_w or by >= screen_h) continue;
                    if (by == py or by == py + ph - 1) {
                        ren.drawText(@intCast(bx), @intCast(by), "─", theme.border_color, theme.bg_sidebar, false, false);
                    } else if (bx == px or bx == px + pw - 1) {
                        ren.drawText(@intCast(bx), @intCast(by), "│", theme.border_color, theme.bg_sidebar, false, false);
                    } else {
                        ren.drawText(@intCast(bx), @intCast(by), " ", theme.fg_primary, theme.bg_sidebar, false, false);
                    }
                }
            }
            ren.drawText(px, py, "╭", theme.border_color, theme.bg_sidebar, false, false);
            ren.drawText(px + pw - 1, py, "╮", theme.border_color, theme.bg_sidebar, false, false);
            ren.drawText(px, py + ph - 1, "╰", theme.border_color, theme.bg_sidebar, false, false);
            ren.drawText(px + pw - 1, py + ph - 1, "╯", theme.border_color, theme.bg_sidebar, false, false);

            ren.drawText(px + 2, py + 1, " Duplicate Keybinding ", theme.fg_secondary, theme.bg_sidebar, true, false);
            ren.drawText(px + 2, py + 3, "This key is already in use!", theme.fg_primary, theme.bg_sidebar, false, false);
            ren.drawText(px + 14, py + 5, "[ OK ]", theme.fg_accent, theme.bg_sidebar, false, false);
        }
    }

    pub fn handleKey(self: *SettingsWidget, key: []const u8) bool {
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
            return false;
        }
        if (self.duplicate_warning) {
            if (std.mem.eql(u8, key, "<CR>") or std.mem.eql(u8, key, "<Esc>")) {
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
                // Not freeing strings to keep it simple unless we know they are dynamically allocated, but in this setup they are.
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

        if (self.duplicate_warning) {
            self.duplicate_warning = false;
            return true;
        }

        if (self.active_binding != null) {
            self.active_binding = null;
            return true;
        }

        if (self.popup_active) {
            const pw: u16 = 30;
            const ph: u16 = 7;
            const px: u16 = (screen_w -| pw) / 2;
            const py: u16 = (screen_h -| ph) / 2;
            
            if (mx >= px and mx < px + pw and my >= py and my < py + ph) {
                if (my == py + 5) {
                    if (mx >= px + 4 and mx <= px + 10) { // [ Yes ]
                        const old_cfg = self.config;
                        if (SettingsConfig.load(self.allocator, self.settings_path)) |new_cfg| {
                            self.config = new_cfg;
                            self.allocator.free(old_cfg.theme);
                            self.allocator.free(old_cfg.line_numbers);
                            self.allocator.free(old_cfg.split_separator);
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
                    } else if (mx >= px + 16 and mx <= px + 21) { // [ No ]
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
                items_len = supported_themes.len;
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
            } else if (self.active_dropdown == .mode) {
                items_len = supported_modes.len;
                drop_w = 16;
                drop_y = content_y + 5;
            }

            const drop_h = @as(u16, @intCast(items_len)) + 2;
            
            if (mx >= drop_x and mx < drop_x + drop_w and my > drop_y and my < drop_y + drop_h - 1) {
                const idx = my - drop_y - 1;
                var changed = false;
                if (self.active_dropdown == .theme) {
                    if (idx < supported_themes.len) {
                        const new_theme = self.allocator.dupe(u8, supported_themes[idx]) catch return true;
                        self.allocator.free(self.config.theme);
                        self.config.theme = new_theme;
                        changed = true;
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



        const w: u16 = @min(80, screen_w -| 10);
        const h: u16 = @min(24, screen_h -| 10);
        const x: u16 = (screen_w -| w) / 2;
        const y: u16 = (screen_h -| h) / 2;

        if (mx >= x and mx < x + w and my >= y and my < y + h) {
            // Close button
            if (my == y and mx >= x + w - 4 and mx <= x + w - 2) {
                if (self.has_unsaved_changes) {
                    self.popup_active = true;
                } else {
                    self.is_open = false;
                }
                return true;
            }

            // Save button
            if (my == y + h - 2 and mx >= x + w - 11 and mx <= x + w - 3) {
                if (self.has_unsaved_changes) {
                    self.config.save(self.settings_path) catch {};
                    self.has_unsaved_changes = false;
                    self.needs_apply = true;
                }
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
                            self.active_dropdown = .theme;
                        } else if (my == content_y + 4) {
                            self.active_dropdown = .split_separator;
                        } else if (my == content_y + 6) {
                            self.config.nerd_fonts = !self.config.nerd_fonts;
                            changed = true;
                        }
                    },
                    2 => {
                        if (my == content_y + 2) {
                            self.active_dropdown = .indent_type;
                        } else if (my == content_y + 4) {
                            self.active_dropdown = .indent_size;
                        } else if (my == content_y + 6) {
                            self.config.wrap = !self.config.wrap;
                            changed = true;
                        } else if (my == content_y + 8) {
                            self.active_dropdown = .line_numbers;
                        }
                    },
                    3 => {
                        if (my == content_y + 2) {
                            self.open_mason = true;
                        } else if (my == content_y + 4) {
                            self.open_lazy = true;
                        }
                    },
                    4 => {
                        for (0..6) |i| {
                            if (my == content_y + 2 + @as(u16, @intCast(i * 2))) {
                                self.active_binding = i;
                                changed = true;
                            }
                        }
                    },
                    else => {}
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
