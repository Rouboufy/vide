const std = @import("std");
const renderer = @import("../renderer.zig");
const Color = renderer.Color;
const Rect = @import("../layout.zig").Rect;
const input = @import("../input.zig");

pub const StorePlugin = struct {
    name: []const u8,
    full_name: []const u8,
    stars: usize,
    description: []const u8,
    installed: bool,
};

pub const Category = enum(u8) {
    all,
    colorscheme,
    lsp,
    git,
    ai,
    treesitter,
    telescope,
    installed,

    pub fn shortLabel(self: Category) []const u8 {
        return switch (self) {
            .all => "All",
            .colorscheme => "Theme",
            .lsp => "LSP",
            .git => "Git",
            .ai => "AI",
            .treesitter => "TS",
            .telescope => "Tele",
            .installed => "Inst",
        };
    }

    pub fn label(self: Category) []const u8 {
        return switch (self) {
            .all => "All Plugins",
            .colorscheme => "Themes & Colors",
            .lsp => "LSP Configuration",
            .git => "Git Integrations",
            .ai => "AI & LLM Assistants",
            .treesitter => "Treesitter Parsers",
            .telescope => "Telescope Extensions",
            .installed => "Installed Plugins",
        };
    }

    pub fn toTagName(self: Category) []const u8 {
        return switch (self) {
            .all => "all",
            .colorscheme => "colorscheme",
            .lsp => "lsp",
            .git => "git",
            .ai => "ai",
            .treesitter => "treesitter",
            .telescope => "telescope",
            .installed => "installed",
        };
    }
};

pub const ExtensionShop = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    home: []const u8,
    plugins: std.array_list.Managed(StorePlugin),
    search_query: std.array_list.Managed(u8),
    selected_idx: usize = 0,
    scroll_offset: usize = 0,
    is_searching: bool = false,
    message: ?[]const u8 = null,
    message_timer: i64 = 0,
    selected_category: Category = .all,
    is_popup_open: bool = false,
    sidebar_selected_idx: usize = 0,
    show_reload_confirm: bool = false,
    reload_confirm_yes: bool = true,
    is_detail_open: bool = false,
    detail_plugin_idx: usize = 0,
    edit_config_path: ?[]const u8 = null,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, home: []const u8) ExtensionShop {
        return .{
            .allocator = allocator,
            .io = io,
            .home = home,
            .plugins = std.array_list.Managed(StorePlugin).init(allocator),
            .search_query = std.array_list.Managed(u8).init(allocator),
            .selected_category = .all,
            .is_popup_open = false,
            .sidebar_selected_idx = 0,
            .show_reload_confirm = false,
            .reload_confirm_yes = true,
            .is_detail_open = false,
            .detail_plugin_idx = 0,
            .edit_config_path = null,
        };
    }

    pub fn deinit(self: *ExtensionShop) void {
        self.clearPlugins();
        self.plugins.deinit();
        self.search_query.deinit();
        if (self.message) |msg| self.allocator.free(msg);
        if (self.edit_config_path) |path| self.allocator.free(path);
    }

    fn clearPlugins(self: *ExtensionShop) void {
        for (self.plugins.items) |p| {
            self.allocator.free(p.name);
            self.allocator.free(p.full_name);
            self.allocator.free(p.description);
        }
        self.plugins.clearAndFree();
    }

    pub fn setMessage(self: *ExtensionShop, msg: []const u8) void {
        if (self.message) |m| self.allocator.free(m);
        self.message = self.allocator.dupe(u8, msg) catch null;
        var ts: std.posix.timespec = undefined;
        _ = std.posix.system.clock_gettime(std.posix.CLOCK.MONOTONIC, &ts);
        self.message_timer = ts.sec;
    }

    pub fn triggerSearch(self: *ExtensionShop) !void {
        self.clearPlugins();
        
        const script_path = try std.fs.path.join(self.allocator, &[_][]const u8{ self.home, ".local", "share", "vide", "store_search.py" });
        defer self.allocator.free(script_path);

        const query = self.search_query.items;
        const argv = &[_][]const u8{ "python3", script_path, "search", query, self.selected_category.toTagName() };

        var child = std.process.spawn(self.io, .{
            .argv = argv,
            .stdout = .pipe,
            .stderr = .ignore,
        }) catch {
            self.setMessage("Failed to run store_search.py");
            return;
        };
        errdefer {
            if (child.id != null) child.kill(self.io);
        }

        var stdout = std.array_list.Managed(u8).init(self.allocator);
        defer stdout.deinit();

        if (child.stdout) |out| {
            while (true) {
                var chunk: [1024]u8 = undefined;
                const len = std.posix.read(out.handle, &chunk) catch 0;
                if (len == 0) break;
                try stdout.appendSlice(chunk[0..len]);
            }
        }

        _ = try child.wait(self.io);

        const json_str = stdout.items;
        if (json_str.len == 0) return;

        // Parse JSON output into our ArrayList
        const parsed = std.json.parseFromSlice([]struct {
            name: []const u8,
            full_name: []const u8,
            stars: usize,
            description: []const u8,
            installed: bool,
        }, self.allocator, json_str, .{ .ignore_unknown_fields = true }) catch {
            self.setMessage("Failed to parse search results");
            return;
        };
        defer parsed.deinit();

        for (parsed.value) |p| {
            try self.plugins.append(.{
                .name = try self.allocator.dupe(u8, p.name),
                .full_name = try self.allocator.dupe(u8, p.full_name),
                .stars = p.stars,
                .description = try self.allocator.dupe(u8, p.description),
                .installed = p.installed,
            });
        }

        self.selected_idx = 0;
        self.scroll_offset = 0;
    }

    pub fn draw(self: *ExtensionShop, rend: *renderer.Renderer, rect: Rect, colors: anytype) void {
        // Clear background
        rend.drawRect(rect, " ", colors.fg_secondary, colors.bg_sidebar);

        // Header
        rend.drawText(rect.x + 1, rect.y, " EXTENSION SHOP ", colors.bg_sidebar, colors.fg_accent, true, false);

        // Render instruction hint
        rend.drawText(rect.x + 1, rect.y + 2, "Select category:", colors.fg_secondary, colors.bg_sidebar, false, false);

        const categories = [_]Category{ .all, .colorscheme, .lsp, .git, .ai, .treesitter, .telescope, .installed };
        const list_start_y = rect.y + 4;

        for (categories, 0..) |cat, i| {
            const cy = list_start_y + @as(u16, @intCast(i)) * 2;
            if (cy >= rect.y + rect.h) break;

            const is_selected = (i == self.sidebar_selected_idx);
            const row_bg = if (is_selected) colors.bg_editor else colors.bg_sidebar;
            const name_fg = if (is_selected) colors.fg_primary else colors.fg_secondary;

            // Highlight full selected block
            const highlight_rect = Rect{ .x = rect.x, .y = cy, .w = rect.w - 1, .h = 1 };
            rend.drawRect(highlight_rect, " ", colors.fg_secondary, row_bg);

            if (is_selected) {
                rend.drawText(rect.x, cy, "▋", colors.fg_accent, row_bg, true, false);
            }

            // Category Name/Label
            rend.drawText(rect.x + 2, cy, cat.label(), name_fg, row_bg, is_selected, false);
        }

        // Draw right border
        var by: u16 = 0;
        while (by < rect.h) : (by += 1) {
            var cell = renderer.Cell{
                .fg = colors.border_color,
                .bg = colors.bg_sidebar,
            };
            cell.setChar("│");
            rend.setCell(rect.x + rect.w - 1, rect.y + by, cell);
        }
    }

    pub fn drawPopup(self: *ExtensionShop, rend: *renderer.Renderer, screen_w: u16, screen_h: u16, colors: anytype) void {
        const w: u16 = @min(80, screen_w -| 10);
        const h: u16 = @min(24, screen_h -| 10);
        const x: u16 = (screen_w -| w) / 2;
        const y: u16 = (screen_h -| h) / 2;

        // Drop shadow
        for (y + 1..y + h + 1) |by| {
            for (x + 2..x + w + 2) |bx| {
                if (bx >= screen_w or by >= screen_h) continue;
                rend.drawText(@intCast(bx), @intCast(by), " ", colors.bg_editor, colors.bg_editor, false, false);
            }
        }

        // Background
        for (y..y + h) |by| {
            for (x..x + w) |bx| {
                rend.drawText(@intCast(bx), @intCast(by), " ", colors.fg_primary, colors.bg_sidebar, false, false);
            }
        }

        // Border
        for (x..x + w) |bx| {
            rend.drawText(@intCast(bx), y, "─", colors.border_color, colors.bg_sidebar, false, false);
            rend.drawText(@intCast(bx), y + h - 1, "─", colors.border_color, colors.bg_sidebar, false, false);
        }
        for (y..y + h) |by| {
            rend.drawText(x, @intCast(by), "│", colors.border_color, colors.bg_sidebar, false, false);
            rend.drawText(x + w - 1, @intCast(by), "│", colors.border_color, colors.bg_sidebar, false, false);
        }
        rend.drawText(x, y, "╭", colors.border_color, colors.bg_sidebar, false, false);
        rend.drawText(x + w - 1, y, "╮", colors.border_color, colors.bg_sidebar, false, false);
        rend.drawText(x, y + h - 1, "╰", colors.border_color, colors.bg_sidebar, false, false);
        rend.drawText(x + w - 1, y + h - 1, "╯", colors.border_color, colors.bg_sidebar, false, false);

        // Draw close cross (Top Right)
        rend.drawText(x + w - 4, y, " ✖ ", .{ .rgb = .{ .r = 255, .g = 80, .b = 80 } }, colors.bg_sidebar, true, false);

        // Title
        var title_buf: [128]u8 = undefined;
        const title = std.fmt.bufPrint(&title_buf, " Explore: {s} ", .{ self.selected_category.label() }) catch " Explore Plugins ";
        rend.drawText(x + 2, y, title, colors.fg_accent, colors.bg_sidebar, true, false);

        // Check for active message
        var ts: std.posix.timespec = undefined;
        _ = std.posix.system.clock_gettime(std.posix.CLOCK.MONOTONIC, &ts);
        const now = ts.sec;
        if (self.message) |msg| {
            if (now - self.message_timer < 5) {
                rend.drawText(x + 2, y + 1, msg, colors.fg_accent, colors.bg_sidebar, false, false);
            }
        }

        // Search Input Box inside popup
        const input_y = y + 2;
        rend.drawText(x + 2, input_y, "🔍", colors.fg_secondary, colors.bg_sidebar, false, false);
        
        var sx = x + 5;
        const box_w = if (w > 10) w - 10 else 10;
        while (sx < x + 5 + box_w) : (sx += 1) {
            rend.drawText(sx, input_y, "_", colors.border_color, colors.bg_sidebar, false, false);
        }

        if (self.search_query.items.len > 0) {
            const display_query = self.search_query.items;
            const truncated = if (display_query.len > box_w) display_query[display_query.len - box_w..] else display_query;
            rend.drawText(x + 5, input_y, truncated, colors.fg_primary, colors.bg_sidebar, false, false);
        } else if (!self.is_searching) {
            rend.drawText(x + 5, input_y, "Search in category...", colors.fg_secondary, colors.bg_sidebar, false, false);
        }

        if (self.is_searching) {
            const cursor_pos = if (self.search_query.items.len > box_w) box_w else self.search_query.items.len;
            rend.drawText(x + 5 + @as(u16, @intCast(cursor_pos)), input_y, "_", colors.fg_primary, colors.bg_sidebar, true, false);
        }

        // Instruction Hint
        rend.drawText(x + 2, input_y + 1, "[/] to type, <Esc> to list/close, <Enter> to toggle install", colors.fg_secondary, colors.bg_sidebar, false, false);

        // Separator
        const sep_y = y + 4;
        var sx_sep = x + 1;
        while (sx_sep < x + w - 1) : (sx_sep += 1) {
            rend.drawText(sx_sep, sep_y, "─", colors.border_color, colors.bg_sidebar, false, false);
        }

        const list_start_y = y + 5;
        if (self.plugins.items.len == 0) {
            rend.drawText(x + 2, list_start_y, "No plugins found.", colors.fg_secondary, colors.bg_sidebar, false, false);
            return;
        }

        const max_visible_items = (h - 6) / 3;
        var rendered_count: usize = 0;
        for (self.plugins.items, 0..) |p, i| {
            if (i < self.scroll_offset) continue;
            if (rendered_count >= max_visible_items) break;

            const py = list_start_y + @as(u16, @intCast(rendered_count)) * 3;
            const is_selected = (i == self.selected_idx);

            const row_bg = if (is_selected) colors.bg_editor else colors.bg_sidebar;
            const name_fg = colors.fg_primary;

            // Highlight full selected block
            const highlight_rect = Rect{ .x = x + 1, .y = py, .w = w - 2, .h = 3 };
            rend.drawRect(highlight_rect, " ", colors.fg_secondary, row_bg);
            if (is_selected) {
                rend.drawText(x + 1, py, "▋", colors.fg_accent, row_bg, true, false);
            }

            // Line 1: Name + Star + [Status]
            var title_buf2: [128]u8 = undefined;
            const star_char = if (colors.nerd_fonts) "⭐" else "*";
            const title2 = std.fmt.bufPrint(&title_buf2, "{s} {s}{d}", .{ p.name, star_char, p.stars }) catch p.name;
            rend.drawText(x + 3, py, title2, name_fg, row_bg, is_selected, false);

            if (p.installed) {
                rend.drawText(x + w - 15, py, "[Installed]", colors.fg_accent, row_bg, false, false);
            }

            // Line 2: Description (truncated to popup width)
            const desc = p.description;
            const max_desc_w = if (w > 6) w - 6 else 10;
            const display_desc = if (desc.len > max_desc_w) desc[0..max_desc_w] else desc;
            rend.drawText(x + 3, py + 1, display_desc, colors.fg_secondary, row_bg, false, false);

            // Line 3: Separator line between items
            var sx_item_sep = x + 3;
            while (sx_item_sep < x + w - 3) : (sx_item_sep += 1) {
                rend.drawText(sx_item_sep, py + 2, "─", colors.border_color, row_bg, false, false);
            }

            rendered_count += 1;
        }

        if (self.is_detail_open) {
            const dw: u16 = @min(60, screen_w -| 14);
            const dh: u16 = @min(14, screen_h -| 14);
            const dx: u16 = (screen_w -| dw) / 2;
            const dy: u16 = (screen_h -| dh) / 2;

            // Drop shadow
            for (dy + 1..dy + dh + 1) |by| {
                for (dx + 2..dx + dw + 2) |bx| {
                    if (bx >= screen_w or by >= screen_h) continue;
                    rend.drawText(@intCast(bx), @intCast(by), " ", colors.bg_editor, colors.bg_editor, false, false);
                }
            }

            // Background & Border
            for (dy..dy + dh) |by| {
                for (dx..dx + dw) |bx| {
                    if (bx >= screen_w or by >= screen_h) continue;
                    if (by == dy or by == dy + dh - 1) {
                        rend.drawText(@intCast(bx), @intCast(by), "─", colors.border_color, colors.bg_sidebar, false, false);
                    } else if (bx == dx or bx == dx + dw - 1) {
                        rend.drawText(@intCast(bx), @intCast(by), "│", colors.border_color, colors.bg_sidebar, false, false);
                    } else {
                        rend.drawText(@intCast(bx), @intCast(by), " ", colors.fg_primary, colors.bg_sidebar, false, false);
                    }
                }
            }
            rend.drawText(dx, dy, "╭", colors.border_color, colors.bg_sidebar, false, false);
            rend.drawText(dx + dw - 1, dy, "╮", colors.border_color, colors.bg_sidebar, false, false);
            rend.drawText(dx, dy + dh - 1, "╰", colors.border_color, colors.bg_sidebar, false, false);
            rend.drawText(dx + dw - 1, dy + dh - 1, "╯", colors.border_color, colors.bg_sidebar, false, false);

            // Red cross (Top Right)
            rend.drawText(dx + dw - 4, dy, " ✖ ", .{ .rgb = .{ .r = 255, .g = 80, .b = 80 } }, colors.bg_sidebar, true, false);

            const p = self.plugins.items[self.detail_plugin_idx];

            // Title (Plugin Name)
            var title_buf_det: [128]u8 = undefined;
            const title_det = std.fmt.bufPrint(&title_buf_det, " {s} ", .{ p.name }) catch " Plugin Details ";
            rend.drawText(dx + 2, dy, title_det, colors.fg_accent, colors.bg_sidebar, true, false);

            // Full Name / Repo
            rend.drawText(dx + 3, dy + 2, "Repository:", colors.fg_secondary, colors.bg_sidebar, false, false);
            rend.drawText(dx + 16, dy + 2, p.full_name, colors.fg_primary, colors.bg_sidebar, false, false);

            // Stars
            var stars_buf: [64]u8 = undefined;
            const star_char = if (colors.nerd_fonts) "⭐" else "*";
            const stars_str = std.fmt.bufPrint(&stars_buf, "{s} {d}", .{ star_char, p.stars }) catch "";
            rend.drawText(dx + 3, dy + 3, "Rating:", colors.fg_secondary, colors.bg_sidebar, false, false);
            rend.drawText(dx + 16, dy + 3, stars_str, colors.fg_primary, colors.bg_sidebar, false, false);

            // Description (wrap nicely)
            rend.drawText(dx + 3, dy + 5, "Description:", colors.fg_secondary, colors.bg_sidebar, false, false);

            // Simple line wrapping for description
            var desc_y = dy + 6;
            const max_desc_w = dw -| 8;
            var words = std.mem.tokenizeAny(u8, p.description, " \t\n\r");
            var line_buf = std.array_list.Managed(u8).init(self.allocator);
            defer line_buf.deinit();

            while (words.next()) |word| {
                if (desc_y >= dy + dh - 4) break; // Don't overflow the box

                if (line_buf.items.len + word.len + 1 > max_desc_w) {
                    if (line_buf.items.len > 0) {
                        rend.drawText(dx + 4, desc_y, line_buf.items, colors.fg_primary, colors.bg_sidebar, false, false);
                        line_buf.clearRetainingCapacity();
                        desc_y += 1;
                    }
                }
                if (line_buf.items.len > 0) {
                    line_buf.appendSlice(" ") catch {};
                }
                line_buf.appendSlice(word) catch {};
            }
            if (line_buf.items.len > 0 and desc_y < dy + dh - 4) {
                rend.drawText(dx + 4, desc_y, line_buf.items, colors.fg_primary, colors.bg_sidebar, false, false);
            }

            // Install/Uninstall/Edit Config Buttons at bottom
            if (p.installed) {
                const btn1_w: u16 = 17;
                const btn1_x: u16 = dx + (dw / 2) -| btn1_w -| 2;
                const btn_y: u16 = dy + dh - 3;
                for (btn1_x..btn1_x + btn1_w) |bx| {
                    rend.drawText(@intCast(bx), btn_y, " ", colors.fg_primary, colors.bg_editor, false, false);
                }
                rend.drawText(btn1_x + 1, btn_y, "[ Edit Config ]", colors.fg_accent, colors.bg_editor, true, false);

                const btn2_w: u16 = 22;
                const btn2_x: u16 = dx + (dw / 2) + 2;
                for (btn2_x..btn2_x + btn2_w) |bx| {
                    rend.drawText(@intCast(bx), btn_y, " ", colors.fg_primary, colors.bg_editor, false, false);
                }
                rend.drawText(btn2_x + 1, btn_y, "[ Uninstall Plugin ]", colors.fg_accent, colors.bg_editor, true, false);
            } else {
                const btn_w: u16 = 22;
                const btn_x: u16 = dx + (dw -| btn_w) / 2;
                const btn_y: u16 = dy + dh - 3;
                for (btn_x..btn_x + btn_w) |bx| {
                    rend.drawText(@intCast(bx), btn_y, " ", colors.fg_primary, colors.bg_editor, false, false);
                }
                rend.drawText(btn_x + 1, btn_y, "[ Install Plugin ]", colors.fg_accent, colors.bg_editor, true, false);
            }
        }

        if (self.show_reload_confirm) {
            const pw: u16 = 36;
            const ph: u16 = 7;
            const px: u16 = (screen_w -| pw) / 2;
            const py: u16 = (screen_h -| ph) / 2;

            // Draw drop shadow
            for (py + 1..py + ph + 1) |by| {
                for (px + 2..px + pw + 2) |bx| {
                    if (bx >= screen_w or by >= screen_h) continue;
                    rend.drawText(@intCast(bx), @intCast(by), " ", colors.bg_editor, colors.bg_editor, false, false);
                }
            }

            // Background & Border
            for (py..py + ph) |by| {
                for (px..px + pw) |bx| {
                    if (bx >= screen_w or by >= screen_h) continue;
                    if (by == py or by == py + ph - 1) {
                        rend.drawText(@intCast(bx), @intCast(by), "─", colors.border_color, colors.bg_sidebar, false, false);
                    } else if (bx == px or bx == px + pw - 1) {
                        rend.drawText(@intCast(bx), @intCast(by), "│", colors.border_color, colors.bg_sidebar, false, false);
                    } else {
                        rend.drawText(@intCast(bx), @intCast(by), " ", colors.fg_primary, colors.bg_sidebar, false, false);
                    }
                }
            }
            rend.drawText(px, py, "╭", colors.border_color, colors.bg_sidebar, false, false);
            rend.drawText(px + pw - 1, py, "╮", colors.border_color, colors.bg_sidebar, false, false);
            rend.drawText(px, py + ph - 1, "╰", colors.border_color, colors.bg_sidebar, false, false);
            rend.drawText(px + pw - 1, py + ph - 1, "╯", colors.border_color, colors.bg_sidebar, false, false);

            rend.drawText(px + 2, py + 1, " Reload Required ", colors.fg_accent, colors.bg_sidebar, true, false);
            rend.drawText(px + 4, py + 3, "Reload Vide to apply changes?", colors.fg_primary, colors.bg_sidebar, false, false);

            // Yes / No buttons
            const yes_fg = if (self.reload_confirm_yes) colors.fg_accent else colors.fg_secondary;
            const no_fg = if (!self.reload_confirm_yes) colors.fg_accent else colors.fg_secondary;

            rend.drawText(px + 8, py + 5, "[ Yes ]", yes_fg, colors.bg_sidebar, self.reload_confirm_yes, false);
            rend.drawText(px + 20, py + 5, "[ No ]", no_fg, colors.bg_sidebar, !self.reload_confirm_yes, false);
        }
    }

    pub fn handleKey(self: *ExtensionShop, key: []const u8) !bool {
        if (self.is_popup_open) return false;

        const categories = [_]Category{ .all, .colorscheme, .lsp, .git, .ai, .treesitter, .telescope, .installed };

        if (std.mem.eql(u8, key, "j") or std.mem.eql(u8, key, "<Down>")) {
            if (self.sidebar_selected_idx < categories.len - 1) {
                self.sidebar_selected_idx += 1;
            } else {
                self.sidebar_selected_idx = 0;
            }
            return true;
        } else if (std.mem.eql(u8, key, "k") or std.mem.eql(u8, key, "<Up>")) {
            if (self.sidebar_selected_idx > 0) {
                self.sidebar_selected_idx -= 1;
            } else {
                self.sidebar_selected_idx = categories.len - 1;
            }
            return true;
        } else if (std.mem.eql(u8, key, "<Enter>") or std.mem.eql(u8, key, "o")) {
            self.selected_category = categories[self.sidebar_selected_idx];
            self.search_query.clearRetainingCapacity();
            self.selected_idx = 0;
            self.scroll_offset = 0;
            self.is_searching = false;
            self.is_popup_open = true;
            try self.triggerSearch();
            return true;
        }

        return false;
    }

    pub fn handlePopupKey(self: *ExtensionShop, key: []const u8, screen_h: u16) !bool {
        if (!self.is_popup_open) return false;

        if (self.show_reload_confirm) {
            if (std.mem.eql(u8, key, "h") or std.mem.eql(u8, key, "<Left>") or std.mem.eql(u8, key, "l") or std.mem.eql(u8, key, "<Right>")) {
                self.reload_confirm_yes = !self.reload_confirm_yes;
                return true;
            } else if (std.mem.eql(u8, key, "<Enter>") or std.mem.eql(u8, key, "<CR>") or std.mem.eql(u8, key, "o") or std.mem.eql(u8, key, "<Space>")) {
                if (self.reload_confirm_yes) {
                    self.show_reload_confirm = false;
                    return error.ReloadApplication;
                } else {
                    self.show_reload_confirm = false;
                }
                return true;
            } else if (std.mem.eql(u8, key, "<Esc>")) {
                self.show_reload_confirm = false;
                return true;
            }
            return true; // Consume other keys
        }

        if (self.is_detail_open) {
            if (std.mem.eql(u8, key, "<Esc>")) {
                self.is_detail_open = false;
                return true;
            } else if (std.mem.eql(u8, key, "<Enter>") or std.mem.eql(u8, key, "<CR>") or std.mem.eql(u8, key, "o") or std.mem.eql(u8, key, "<Space>")) {
                try self.toggleInstall(self.detail_plugin_idx);
                return true;
            }
            return true; // Consume other keys
        }

        if (self.is_searching) {
            if (std.mem.eql(u8, key, "<Esc>") or std.mem.eql(u8, key, "<Enter>")) {
                self.is_searching = false;
                try self.triggerSearch();
                return true;
            } else if (std.mem.eql(u8, key, "<Backspace>")) {
                if (self.search_query.items.len > 0) {
                    _ = self.search_query.pop();
                }
                return true;
            } else if (key.len == 1) {
                try self.search_query.append(key[0]);
                return true;
            }
            return false;
        }

        if (std.mem.eql(u8, key, "<Esc>")) {
            self.is_popup_open = false;
            return true;
        } else if (std.mem.eql(u8, key, "/")) {
            self.is_searching = true;
            return true;
        } else if (std.mem.eql(u8, key, "j") or std.mem.eql(u8, key, "<Down>")) {
            if (self.plugins.items.len > 0) {
                const h = @min(24, screen_h -| 10);
                const max_visible = (h - 6) / 3;
                if (self.selected_idx < self.plugins.items.len - 1) {
                    self.selected_idx += 1;
                    if (self.selected_idx >= self.scroll_offset + max_visible) {
                        self.scroll_offset = self.selected_idx - (max_visible - 1);
                    }
                }
            }
            return true;
        } else if (std.mem.eql(u8, key, "k") or std.mem.eql(u8, key, "<Up>")) {
            if (self.selected_idx > 0) {
                self.selected_idx -= 1;
                if (self.selected_idx < self.scroll_offset) {
                    self.scroll_offset = self.selected_idx;
                }
            }
            return true;
        } else if (std.mem.eql(u8, key, "<Enter>") or std.mem.eql(u8, key, "o")) {
            if (self.plugins.items.len > 0 and self.selected_idx < self.plugins.items.len) {
                self.is_detail_open = true;
                self.detail_plugin_idx = self.selected_idx;
            }
            return true;
        }

        return false;
    }

    pub fn handleMouse(self: *ExtensionShop, mx: u16, my: u16, rect: Rect) !bool {
        if (self.is_popup_open) return false;

        _ = mx;
        const list_start_y = rect.y + 4;
        if (my < list_start_y) return false;

        const categories = [_]Category{ .all, .colorscheme, .lsp, .git, .ai, .treesitter, .telescope, .installed };
        const diff_y = my - list_start_y;
        if (diff_y % 2 == 0) {
            const idx = diff_y / 2;
            if (idx < categories.len) {
                self.sidebar_selected_idx = idx;
                self.selected_category = categories[idx];
                self.search_query.clearRetainingCapacity();
                self.selected_idx = 0;
                self.scroll_offset = 0;
                self.is_searching = false;
                self.is_popup_open = true;
                try self.triggerSearch();
                return true;
            }
        }

        return false;
    }

    pub fn handlePopupMouse(self: *ExtensionShop, m: input.MouseEvent, screen_w: u16, screen_h: u16) !bool {
        if (!self.is_popup_open) return false;

        if (self.show_reload_confirm) {
            const pw: u16 = 36;
            const ph: u16 = 7;
            const px: u16 = (screen_w -| pw) / 2;
            const py: u16 = (screen_h -| ph) / 2;

            if (m.row == py + 5) {
                if (m.col >= px + 8 and m.col < px + 15) {
                    self.show_reload_confirm = false;
                    return error.ReloadApplication;
                } else if (m.col >= px + 20 and m.col < px + 26) {
                    self.show_reload_confirm = false;
                    return true;
                }
            }
            if (m.col < px or m.col >= px + pw or m.row < py or m.row >= py + ph) {
                self.show_reload_confirm = false;
                return true;
            }
            return true;
        }

        if (self.is_detail_open) {
            const dw = @min(60, screen_w -| 14);
            const dh = @min(14, screen_h -| 14);
            const dx = (screen_w -| dw) / 2;
            const dy = (screen_h -| dh) / 2;

            if (m.row == dy and m.col >= dx + dw - 4 and m.col < dx + dw - 1) {
                self.is_detail_open = false;
                return true;
            }

            const p = self.plugins.items[self.detail_plugin_idx];
            const btn_y = dy + dh - 3;
            if (p.installed) {
                const btn1_w: u16 = 17;
                const btn1_x = dx + (dw / 2) -| btn1_w -| 2;
                const btn2_w: u16 = 22;
                const btn2_x = dx + (dw / 2) + 2;

                if (m.row == btn_y) {
                    if (m.col >= btn1_x and m.col < btn1_x + btn1_w) {
                        try self.editConfig(p);
                        return true;
                    } else if (m.col >= btn2_x and m.col < btn2_x + btn2_w) {
                        try self.toggleInstall(self.detail_plugin_idx);
                        return true;
                    }
                }
            } else {
                const btn_w: u16 = 22;
                const btn_x = dx + (dw -| btn_w) / 2;
                if (m.row == btn_y and m.col >= btn_x and m.col < btn_x + btn_w) {
                    try self.toggleInstall(self.detail_plugin_idx);
                    return true;
                }
            }

            if (m.col < dx or m.col >= dx + dw or m.row < dy or m.row >= dy + dh) {
                self.is_detail_open = false;
                return true;
            }

            return true;
        }

        const w = @min(80, screen_w -| 10);
        const h = @min(24, screen_h -| 10);
        const x = (screen_w -| w) / 2;
        const y = (screen_h -| h) / 2;

        if (m.col < x or m.col >= x + w or m.row < y or m.row >= y + h) {
            return false; // outside bounds -> will close popup
        }

        // Check if clicked the red cross
        if (m.row == y and m.col >= x + w - 4 and m.col < x + w - 1) {
            self.is_popup_open = false;
            return true;
        }

        if (m.button == .wheel_up) {
            if (self.selected_idx > 0) {
                self.selected_idx -= 1;
                if (self.selected_idx < self.scroll_offset) {
                    self.scroll_offset = self.selected_idx;
                }
            }
            return true;
        }

        if (m.button == .wheel_down) {
            if (self.plugins.items.len > 0) {
                const max_visible = (h - 6) / 3;
                if (self.selected_idx < self.plugins.items.len - 1) {
                    self.selected_idx += 1;
                    if (self.selected_idx >= self.scroll_offset + max_visible) {
                        self.scroll_offset = self.selected_idx - (max_visible - 1);
                    }
                }
            }
            return true;
        }

        const input_y = y + 2;
        const box_w = if (w > 10) w - 10 else 10;
        if (m.row == input_y and m.col >= x + 5 and m.col < x + 5 + box_w) {
            self.is_searching = true;
            return true;
        }

        const list_start_y = y + 5;
        if (m.row >= list_start_y) {
            const max_visible = (h - 6) / 3;
            const row = (m.row - list_start_y) / 3;
            if (row < max_visible) {
                const clicked_idx = self.scroll_offset + row;
                if (clicked_idx < self.plugins.items.len) {
                    self.selected_idx = clicked_idx;
                    self.is_detail_open = true;
                    self.detail_plugin_idx = clicked_idx;
                    return true;
                }
            }
        }

        return true;
    }

    pub fn toggleInstall(self: *ExtensionShop, idx: usize) !void {
        if (self.plugins.items.len == 0 or idx >= self.plugins.items.len) return;
        const p = &self.plugins.items[idx];
        const script_path = try std.fs.path.join(self.allocator, &[_][]const u8{ self.home, ".local", "share", "vide", "store_search.py" });
        defer self.allocator.free(script_path);

        const action = if (p.installed) "remove" else "add";
        const argv = &[_][]const u8{ "python3", script_path, action, p.full_name };

        var child = try std.process.spawn(self.io, .{
            .argv = argv,
            .stdout = .pipe,
            .stderr = .ignore,
        });
        const term = try child.wait(self.io);
        if (!term.success()) {
            self.setMessage("Failed to update plugin");
            return;
        }

        p.installed = !p.installed;
        self.show_reload_confirm = true;
        self.reload_confirm_yes = true;
    }

    fn editConfig(self: *ExtensionShop, p: StorePlugin) !void {
        const configs_dir = try std.fs.path.join(self.allocator, &[_][]const u8{ self.home, ".local", "share", "vide", "plugin_configs" });
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

        const file_z = try self.allocator.dupeSentinel(u8, config_file_path, 0);
        defer self.allocator.free(file_z);

        const fd = std.posix.openatZ(std.posix.AT.FDCWD, file_z, .{ .ACCMODE = .RDONLY }, 0) catch |err| blk: {
            if (err == error.FileNotFound) {
                const write_fd = try std.posix.openatZ(std.posix.AT.FDCWD, file_z, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o644);
                defer _ = std.os.linux.close(write_fd);

                var template_buf: [512]u8 = undefined;
                const template = std.fmt.bufPrint(&template_buf,
                    "-- Configuration for {s}\n" ++
                    "-- This file is loaded automatically by lazy.nvim\n\n" ++
                    "return {{\n" ++
                    "  -- Add your custom plugin configuration here\n" ++
                    "}}\n",
                    .{p.name}
                ) catch "";

                _ = std.os.linux.write(write_fd, template.ptr, template.len);
            }
            break :blk -1;
        };
        if (fd >= 0) {
            _ = std.os.linux.close(fd);
        }

        self.edit_config_path = config_file_path;
    }
};
