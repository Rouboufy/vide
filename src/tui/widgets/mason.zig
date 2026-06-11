const std = @import("std");
const renderer = @import("../renderer.zig");
const Color = renderer.Color;
const msgpack = @import("../../nvim/msgpack.zig");
const Value = msgpack.Value;
const rpc_mod = @import("../../nvim/rpc.zig");
const RpcClient = rpc_mod.RpcClient;
const input = @import("../input.zig");

pub const MasonTab = enum {
    lsp,
    dap,
    linter,
    formatter,
    runtime,
    compiler,

    pub fn label(self: MasonTab) []const u8 {
        return switch (self) {
            .lsp => " LSP ",
            .dap => " DAP ",
            .linter => " Linter ",
            .formatter => " Formatter ",
            .runtime => " Runtime ",
            .compiler => " Compiler ",
        };
    }

    pub fn fromString(s: []const u8) ?MasonTab {
        if (std.mem.eql(u8, s, "LSP")) return .lsp;
        if (std.mem.eql(u8, s, "DAP")) return .dap;
        if (std.mem.eql(u8, s, "Linter")) return .linter;
        if (std.mem.eql(u8, s, "Formatter")) return .formatter;
        if (std.mem.eql(u8, s, "Runtime")) return .runtime;
        if (std.mem.eql(u8, s, "Compiler")) return .compiler;
        return null;
    }
};

pub const MasonPackage = struct {
    name: []const u8,
    is_installed: bool = false,
    target_is_installed: bool = false,
    tabs: std.EnumSet(MasonTab),
};

pub const MasonWidget = struct {
    is_open: bool = false,
    allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    packages: std.array_list.Managed(MasonPackage),
    scroll_offset: usize = 0,
    selected_idx: usize = 0, // index in the FULL packages list
    selected_tab: MasonTab = .lsp,

    // Search functionality
    search_query: [64]u8 = @splat(0),
    search_len: usize = 0,
    is_searching: bool = false,

    pub fn init(allocator: std.mem.Allocator) MasonWidget {
        return .{
            .allocator = allocator,
            .arena = std.heap.ArenaAllocator.init(allocator),
            .packages = std.array_list.Managed(MasonPackage).init(allocator),
        };
    }

    pub fn deinit(self: *MasonWidget) void {
        self.arena.deinit();
        self.packages.deinit();
    }

    pub fn refresh(self: *MasonWidget, rpc: *RpcClient) void {
        const script = 
            \\local has_mason, registry = pcall(require, 'mason-registry')
            \\if not has_mason then return {} end
            \\local res = {}
            \\for _, p in ipairs(registry.get_all_packages()) do
            \\    table.insert(res, {
            \\        name = p.name,
            \\        categories = p.spec.categories,
            \\        installed = p:is_installed()
            \\    })
            \\end
            \\return res
        ;

        var params = self.allocator.alloc(Value, 2) catch return;
        defer self.allocator.free(params);
        params[0] = .{ .string = script };
        params[1] = .{ .array = &[_]Value{} };

        if (rpc.call("nvim_exec_lua", params) catch null) |res| {
            defer msgpack.freeValue(res, self.allocator);
            if (res == .array) {
                _ = self.arena.reset(.retain_capacity);
                self.packages.clearRetainingCapacity();
                
                for (res.array) |item| {
                    if (item == .map) {
                        var pkg: MasonPackage = .{
                            .name = "",
                            .tabs = std.EnumSet(MasonTab).empty,
                        };
                        for (item.map) |kv| {
                            if (kv.key == .string) {
                                if (std.mem.eql(u8, kv.key.string, "name") and kv.value == .string) {
                                    pkg.name = self.arena.allocator().dupe(u8, kv.value.string) catch "";
                                } else if (std.mem.eql(u8, kv.key.string, "installed") and kv.value == .bool) {
                                    pkg.is_installed = kv.value.bool;
                                    pkg.target_is_installed = pkg.is_installed;
                                } else if (std.mem.eql(u8, kv.key.string, "categories") and kv.value == .array) {
                                    for (kv.value.array) |cat_val| {
                                        if (cat_val == .string) {
                                            if (MasonTab.fromString(cat_val.string)) |tab| {
                                                pkg.tabs.insert(tab);
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        if (pkg.name.len > 0) {
                            self.packages.append(pkg) catch {};
                        }
                    }
                }
                
                // Sort alphabetically
                std.sort.block(MasonPackage, self.packages.items, {}, struct {
                    fn lessThan(_: void, a: MasonPackage, b: MasonPackage) bool {
                        return std.mem.lessThan(u8, a.name, b.name);
                    }
                }.lessThan);
                
                self.ensureSelectionValid();
            }
        }
    }

    fn matchesSearch(self: *const MasonWidget, pkg: MasonPackage) bool {
        if (self.search_len == 0) return true;
        const query = self.search_query[0..self.search_len];
        return std.ascii.findIgnoreCase(pkg.name, query) != null;
    }

    fn ensureSelectionValid(self: *MasonWidget) void {
        if (self.packages.items.len == 0) return;
        
        // Check if current selected_idx is still valid for current tab AND search
        if (self.selected_idx < self.packages.items.len) {
            const pkg = self.packages.items[self.selected_idx];
            if (pkg.tabs.contains(self.selected_tab) and self.matchesSearch(pkg)) return;
        }

        // Find first valid package
        for (self.packages.items, 0..) |pkg, i| {
            if (pkg.tabs.contains(self.selected_tab) and self.matchesSearch(pkg)) {
                self.selected_idx = i;
                return;
            }
        }
    }

    pub fn draw(self: *const MasonWidget, ren: *renderer.Renderer, screen_w: u16, screen_h: u16, theme: anytype) void {
        if (!self.is_open) return;

        const w: u16 = @min(84, screen_w -| 4);
        const h: u16 = @min(28, screen_h -| 4);
        const x: u16 = (screen_w -| w) / 2;
        const y: u16 = (screen_h -| h) / 2;

        // Shadow
        ren.drawRect(.{ .x = x + 1, .y = y + 1, .w = w, .h = h }, " ", theme.bg_editor, theme.bg_editor);
        // Background
        ren.drawRect(.{ .x = x, .y = y, .w = w, .h = h }, " ", theme.fg_primary, theme.bg_sidebar);

        // Border
        for (x..x + w) |bx| {
            ren.drawText(@intCast(bx), y, "─", theme.border_color, theme.bg_sidebar, false, false);
            ren.drawText(@intCast(bx), y + h - 1, "─", theme.border_color, theme.bg_sidebar, false, false);
        }
        for (y..y + h) |by| {
            ren.drawText(x, @intCast(by), "│", theme.border_color, theme.bg_sidebar, false, false);
            ren.drawText(x + w - 1, @intCast(by), "│", theme.border_color, theme.bg_sidebar, false, false);
        }
        ren.drawText(x, y, "┌", theme.border_color, theme.bg_sidebar, false, false);
        ren.drawText(x + w - 1, y, "┐", theme.border_color, theme.bg_sidebar, false, false);
        ren.drawText(x, y + h - 1, "└", theme.border_color, theme.bg_sidebar, false, false);
        ren.drawText(x + w - 1, y + h - 1, "┘", theme.border_color, theme.bg_sidebar, false, false);

        // Red Close Button Top Right
        ren.drawText(x + w - 2, y, "X", .{ .rgb = .{ .r = 255, .g = 0, .b = 0 } }, theme.bg_sidebar, true, false);

        // Header
        const header_text = " MASON ";
        ren.drawText(x + 2, y, header_text, theme.bg_sidebar, theme.fg_accent, true, false);
        
        // Search Bar (Right of Header)
        const search_x = x + 12;
        if (self.is_searching or self.search_len > 0) {
            var search_buf: [80]u8 = undefined;
            const display_query = if (self.search_len > 0) self.search_query[0..self.search_len] else "";
            const search_line = std.fmt.bufPrint(&search_buf, " Search: {s}{s} ", .{display_query, if (self.is_searching) "_" else ""}) catch "";
            ren.drawText(search_x, y, search_line, theme.bg_sidebar, theme.fg_primary, false, false);
        } else {
            ren.drawText(search_x, y, " [/] Search ", theme.fg_comment, theme.bg_sidebar, false, false);
        }

        // Stats
        var tab_total: usize = 0;
        var tab_installed: usize = 0;
        for (self.packages.items) |pkg| {
            if (pkg.tabs.contains(self.selected_tab) and self.matchesSearch(pkg)) {
                tab_total += 1;
                if (pkg.is_installed) tab_installed += 1;
            }
        }
        var buf: [128]u8 = undefined;
        const stats = std.fmt.bufPrint(&buf, " {d}/{d} matches ", .{tab_installed, tab_total}) catch "";
        ren.drawText(x + w - 14 - @as(u16, @intCast(stats.len)), y, stats, theme.bg_sidebar, theme.fg_comment, false, false);

        // Tabs
        const tab_y = y + 2;
        var tx: u16 = x + 2;
        inline for (@typeInfo(MasonTab).@"enum".field_values) |val| {
            const tab_enum = @as(MasonTab, @enumFromInt(val));
            const label = tab_enum.label();
            const is_selected = (self.selected_tab == tab_enum);
            const fg = if (is_selected) theme.bg_sidebar else theme.fg_primary;
            const bg = if (is_selected) theme.fg_accent else theme.bg_sidebar;
            ren.drawText(tx, tab_y, label, fg, bg, is_selected, false);
            tx += @as(u16, @intCast(label.len)) + 1;
        }
        
        for (x + 1..x + w - 1) |bx| {
            ren.drawText(@intCast(bx), tab_y + 1, "─", theme.border_color, theme.bg_sidebar, false, false);
        }

        // List
        const list_y = tab_y + 4;
        const visible_items = h - 8;
        
        var rendered_count: usize = 0;
        var skipped_count: usize = 0;
        
        for (self.packages.items, 0..) |pkg, i| {
            if (!pkg.tabs.contains(self.selected_tab) or !self.matchesSearch(pkg)) continue;
            
            if (skipped_count < self.scroll_offset) {
                skipped_count += 1;
                continue;
            }
            
            if (rendered_count >= visible_items) break;
            
            const py = list_y + @as(u16, @intCast(rendered_count));
            const is_selected = (i == self.selected_idx);
            const bg = if (is_selected) theme.bg_editor else theme.bg_sidebar;
            const fg = if (is_selected) theme.fg_accent else theme.fg_primary;
            
            if (is_selected) {
                for (x + 1..x + w - 1) |bx| {
                    ren.drawText(@intCast(bx), py, " ", fg, bg, false, false);
                }
            }
            
            const icon = if (pkg.target_is_installed) "◍" else "○";
            const changed = if (pkg.is_installed != pkg.target_is_installed) "*" else " ";
            
            const max_name_len = w - 10;
            const display_name = if (pkg.name.len > max_name_len) 
                pkg.name[0 .. max_name_len - 3] 
            else 
                pkg.name;
            const dots = if (pkg.name.len > max_name_len) "..." else "";
            
            const line = std.fmt.bufPrint(&buf, "{s} {s}{s} {s}{s}", .{
                if (is_selected) "»" else " ",
                icon,
                changed,
                display_name,
                dots
            }) catch continue;
            
            ren.drawText(x + 2, py, line, fg, bg, is_selected, false);
            
            rendered_count += 1;
        }
        
        // Scrollbar
        if (tab_total > visible_items) {
            const scroll_h = visible_items - 2;
            const scroll_y = list_y + 1;
            const max_scroll = tab_total - visible_items;
            const pos = @as(u16, @intCast((self.scroll_offset * scroll_h) / (max_scroll + 1)));
            for (0..scroll_h) |si| {
                const char = if (si == pos) "█" else "│";
                ren.drawText(x + w - 2, scroll_y + @as(u16, @intCast(si)), char, theme.fg_comment, theme.bg_sidebar, false, false);
            }
        }

        // Footer
        const footer_y = y + h - 2;
        const footer_text = " <Space> toggle | [/] search | i: install | u: uninstall | <Enter> apply | <Esc> close ";
        const display_footer = if (footer_text.len > w - 4) footer_text[0 .. w - 7] else footer_text;
        const footer_dots = if (footer_text.len > w - 4) "..." else "";
        const final_footer = std.fmt.bufPrint(&buf, "{s}{s}", .{display_footer, footer_dots}) catch footer_text;
        ren.drawText(x + 2, footer_y, final_footer, theme.fg_comment, theme.bg_sidebar, false, false);
    }

    pub fn handleMouse(self: *MasonWidget, m: input.MouseEvent, screen_w: u16, screen_h: u16, rpc: *RpcClient) bool {
        if (!self.is_open) return false;

        const w: u16 = @min(84, screen_w -| 4);
        const h: u16 = @min(28, screen_h -| 4);
        const x: u16 = (screen_w -| w) / 2;
        const y: u16 = (screen_h -| h) / 2;

        if (m.col >= x and m.col < x + w and m.row >= y and m.row < y + h) {
            // Close Button Top Right
            if (m.action == .press and m.row == y and m.col == x + w - 2) {
                self.is_open = false;
                return true;
            }

            if (m.button == .wheel_up) {
                if (self.scroll_offset > 0) self.scroll_offset -= 1;
                return true;
            } else if (m.button == .wheel_down) {
                var tab_total: usize = 0;
                for (self.packages.items) |pkg| if (pkg.tabs.contains(self.selected_tab) and self.matchesSearch(pkg)) { tab_total += 1; };
                const visible_items = h - 8;
                if (tab_total > visible_items and self.scroll_offset < tab_total - visible_items) {
                    self.scroll_offset += 1;
                }
                return true;
            }

            if (m.action == .press) {
                const tab_y = y + 2;
                if (m.row == tab_y) {
                    var tx: u16 = x + 2;
                    inline for (@typeInfo(MasonTab).@"enum".field_values) |val| {
                        const tab_enum = @as(MasonTab, @enumFromInt(val));
                        const label_len = tab_enum.label().len;
                        if (m.col >= tx and m.col < tx + label_len) {
                            self.selected_tab = tab_enum;
                            self.scroll_offset = 0;
                            self.ensureSelectionValid();
                            return true;
                        }
                        tx += @as(u16, @intCast(label_len)) + 1;
                    }
                }

                const list_y = tab_y + 4;
                const visible_items = h - 8;
                if (m.row >= list_y and m.row < list_y + visible_items) {
                    const click_row = m.row - list_y;
                    var current_row: u16 = 0;
                    var skipped: usize = 0;
                    for (self.packages.items, 0..) |*pkg, i| {
                        if (!pkg.tabs.contains(self.selected_tab) or !self.matchesSearch(pkg.*)) continue;
                        if (skipped < self.scroll_offset) {
                            skipped += 1;
                            continue;
                        }
                        if (current_row == click_row) {
                            self.selected_idx = i;
                            pkg.target_is_installed = !pkg.target_is_installed;
                            return true;
                        }
                        current_row += 1;
                        if (current_row >= visible_items) break;
                    }
                }
                
                if (m.row == y + h - 2) {
                    self.save(rpc);
                    self.is_open = false;
                    return true;
                }
            }
            return true;
        }
        return false;
    }

    pub fn handleKey(self: *MasonWidget, key: []const u8, rpc: *RpcClient) bool {
        if (!self.is_open) return false;

        if (self.is_searching) {
            if (std.mem.eql(u8, key, "<Esc>") or std.mem.eql(u8, key, "<Enter>")) {
                self.is_searching = false;
                return true;
            } else if (std.mem.eql(u8, key, "<BS>")) {
                if (self.search_len > 0) {
                    self.search_len -= 1;
                    self.scroll_offset = 0;
                    self.ensureSelectionValid();
                }
                return true;
            } else if (key.len == 1 and std.ascii.isPrint(key[0])) {
                if (self.search_len < self.search_query.len) {
                    self.search_query[self.search_len] = key[0];
                    self.search_len += 1;
                    self.scroll_offset = 0;
                    self.ensureSelectionValid();
                }
                return true;
            }
        }

        if (std.mem.eql(u8, key, "<Esc>")) {
            self.is_open = false;
            return true;
        } else if (std.mem.eql(u8, key, "/")) {
            self.is_searching = true;
            return true;
        } else if (std.mem.eql(u8, key, "<Down>")) {
            var next_idx = self.selected_idx + 1;
            while (next_idx < self.packages.items.len) : (next_idx += 1) {
                if (self.packages.items[next_idx].tabs.contains(self.selected_tab) and self.matchesSearch(self.packages.items[next_idx])) {
                    self.selected_idx = next_idx;
                    self.ensureVisible();
                    break;
                }
            }
            return true;
        } else if (std.mem.eql(u8, key, "<Up>")) {
            if (self.selected_idx > 0) {
                var prev_idx = self.selected_idx - 1;
                while (true) : (prev_idx -= 1) {
                    if (self.packages.items[prev_idx].tabs.contains(self.selected_tab) and self.matchesSearch(self.packages.items[prev_idx])) {
                        self.selected_idx = prev_idx;
                        self.ensureVisible();
                        break;
                    }
                    if (prev_idx == 0) break;
                }
            }
            return true;
        } else if (std.mem.eql(u8, key, " ") or std.mem.eql(u8, key, "i") or std.mem.eql(u8, key, "u")) {
            if (self.packages.items.len > 0) {
                if (std.mem.eql(u8, key, "i")) {
                    self.packages.items[self.selected_idx].target_is_installed = true;
                } else if (std.mem.eql(u8, key, "u")) {
                    self.packages.items[self.selected_idx].target_is_installed = false;
                } else {
                    self.packages.items[self.selected_idx].target_is_installed = !self.packages.items[self.selected_idx].target_is_installed;
                }
            }
            return true;
        } else if (std.mem.eql(u8, key, "<Enter>")) {
            self.save(rpc);
            self.is_open = false;
            return true;
        } else if (key.len == 1 and key[0] >= '1' and key[0] <= '6') {
            const tab_idx = key[0] - '1';
            self.selected_tab = @as(MasonTab, @enumFromInt(tab_idx));
            self.scroll_offset = 0;
            self.ensureSelectionValid();
            return true;
        }
        return true; 
    }

    fn ensureVisible(self: *MasonWidget) void {
        const visible_items = 20;
        var count_in_tab: usize = 0;
        var idx_in_tab: ?usize = null;
        for (self.packages.items, 0..) |pkg, i| {
            if (!pkg.tabs.contains(self.selected_tab) or !self.matchesSearch(pkg)) continue;
            if (i == self.selected_idx) {
                idx_in_tab = count_in_tab;
            }
            count_in_tab += 1;
        }

        if (idx_in_tab) |it| {
            if (it < self.scroll_offset) {
                self.scroll_offset = it;
            } else if (it >= self.scroll_offset + visible_items) {
                self.scroll_offset = it - visible_items + 1;
            }
        }
    }

    fn save(self: *MasonWidget, rpc: *RpcClient) void {
        var buf: [8192]u8 = undefined;
        var offset: usize = 0;

        const header = 
            \\local has_mason, registry = pcall(require, 'mason-registry')
            \\if not has_mason then return end
            \\
        ;
        
        std.mem.copyForwards(u8, buf[offset..], header);
        offset += header.len;

        var count: usize = 0;
        for (self.packages.items) |pkg| {
            if (pkg.is_installed != pkg.target_is_installed) {
                count += 1;
                const method = if (pkg.target_is_installed) "install" else "uninstall";
                const line = std.fmt.bufPrint(buf[offset..], 
                    \\local p = registry.get_package('{s}')
                    \\if p then p:{s}() end
                    \\
                , .{pkg.name, method}) catch continue;
                offset += line.len;
            }
        }
        
        if (count == 0) return;

        var cmd_p = self.allocator.alloc(Value, 2) catch return;
        defer self.allocator.free(cmd_p);
        cmd_p[0] = .{ .string = buf[0..offset] };
        cmd_p[1] = .{ .array = &[_]Value{} };

        if (rpc.call("nvim_exec_lua", cmd_p) catch null) |res| {
            msgpack.freeValue(res, self.allocator);
        }
        
        for (self.packages.items) |*pkg| {
            pkg.is_installed = pkg.target_is_installed;
        }
    }
};
