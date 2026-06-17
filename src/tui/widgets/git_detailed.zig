const std = @import("std");
const renderer = @import("../renderer.zig");
const Color = renderer.Color;
const input = @import("../input.zig");
const git_utils = @import("git_utils.zig");

pub const CommitInfo = struct {
    hash: []const u8,
    author: []const u8,
    time: []const u8,
    msg: []const u8,
};

pub const GitDetailedTab = enum {
    history,
    branches,

    pub fn label(self: GitDetailedTab) []const u8 {
        return switch (self) {
            .history => " History ",
            .branches => " Branches ",
        };
    }
};

pub const GitDetailedWidget = struct {
    is_open: bool = false,
    allocator: std.mem.Allocator,
    io: std.Io,
    arena: std.heap.ArenaAllocator,
    commits: std.array_list.Managed(CommitInfo),
    branches: std.array_list.Managed([]const u8),
    current_branch: ?[]const u8 = null,
    scroll_offset: usize = 0,
    selected_idx: usize = 0,
    selected_tab: GitDetailedTab = .history,

    pub fn init(allocator: std.mem.Allocator, io: std.Io) GitDetailedWidget {
        return .{
            .allocator = allocator,
            .io = io,
            .arena = std.heap.ArenaAllocator.init(allocator),
            .commits = std.array_list.Managed(CommitInfo).init(allocator),
            .branches = std.array_list.Managed([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *GitDetailedWidget) void {
        self.arena.deinit();
        self.commits.deinit();
        self.branches.deinit();
    }

    pub fn refresh(self: *GitDetailedWidget) void {
        _ = self.arena.reset(.retain_capacity);
        self.commits.clearRetainingCapacity();
        self.branches.clearRetainingCapacity();
        self.current_branch = null;

        {
            const argv = [_][]const u8{ "git", "branch", "-a", "--format=%(refname:short)" };
            if (git_utils.runGitCommand(self.allocator, self.io, &argv)) |stdout| {
                defer self.allocator.free(stdout);
                var lines = std.mem.splitScalar(u8, stdout, '\n');
                while (lines.next()) |line| {
                    const clean_line = std.mem.trim(u8, line, " \r");
                    if (clean_line.len > 0 and !std.mem.endsWith(u8, clean_line, "/HEAD")) {
                        self.branches.append(self.arena.allocator().dupe(u8, clean_line) catch continue) catch {};
                    }
                }
            } else |_| {}
        }

        {
            const argv = [_][]const u8{ "git", "branch", "--show-current" };
            if (git_utils.runGitCommand(self.allocator, self.io, &argv)) |stdout| {
                defer self.allocator.free(stdout);
                if (stdout.len > 0) {
                    const clean_branch = std.mem.trim(u8, stdout, " \n\r");
                    self.current_branch = self.arena.allocator().dupe(u8, clean_branch) catch null;
                }
            } else |_| {}
        }

        const argv = [_][]const u8{ "git", "log", "--pretty=format:%h|%an|%ar|%s", "-n", "100" };
        if (git_utils.runGitCommand(self.allocator, self.io, &argv)) |stdout| {
            defer self.allocator.free(stdout);
            var lines = std.mem.splitScalar(u8, stdout, '\n');
            while (lines.next()) |line| {
                const clean_line = std.mem.trim(u8, line, " \r");
                if (clean_line.len > 0) {
                    var fields = std.mem.splitScalar(u8, clean_line, '|');
                    const hash = fields.next() orelse continue;
                    const author = fields.next() orelse continue;
                    const time = fields.next() orelse continue;
                    const msg = fields.rest();

                    self.commits.append(.{
                        .hash = self.arena.allocator().dupe(u8, hash) catch "",
                        .author = self.arena.allocator().dupe(u8, author) catch "",
                        .time = self.arena.allocator().dupe(u8, time) catch "",
                        .msg = self.arena.allocator().dupe(u8, msg) catch "",
                    }) catch {};
                }
            }
        } else |_| {}
    }

    fn drawTextClipped(ren: *renderer.Renderer, x: u16, y: u16, text: []const u8, max_w: u16, fg: Color, bg: Color, bold: bool, italic: bool) void {
        var col = x;
        var i: usize = 0;
        var rendered_len: u16 = 0;
        while (i < text.len and rendered_len < max_w) {
            const len = std.unicode.utf8ByteSequenceLength(text[i]) catch 1;
            const char = text[i..@min(text.len, i + len)];
            var cell = renderer.Cell{
                .fg = fg,
                .bg = bg,
                .bold = bold,
                .italic = italic,
            };
            cell.setChar(char);
            ren.setCell(col, y, cell);
            col += 1;
            i += len;
            rendered_len += 1;
        }
    }

    pub fn draw(self: *const GitDetailedWidget, ren: *renderer.Renderer, screen_w: u16, screen_h: u16, theme: anytype) void {
        if (!self.is_open) return;

        const w: u16 = @min(110, screen_w -| 4);
        const h: u16 = @min(34, screen_h -| 4);
        const x: u16 = (screen_w -| w) / 2;
        const y: u16 = (screen_h -| h) / 2;

        ren.drawRect(.{ .x = x + 1, .y = y + 1, .w = w, .h = h }, " ", theme.bg_editor, theme.bg_editor);
        ren.drawRect(.{ .x = x, .y = y, .w = w, .h = h }, " ", theme.fg_primary, theme.bg_sidebar);

        for (x..x + w) |bx| {
            ren.drawText(@intCast(bx), y, "─", theme.border_color, theme.bg_sidebar, false, false);
            ren.drawText(@intCast(bx), y + h - 1, "─", theme.border_color, theme.bg_sidebar, false, false);
            ren.drawText(@intCast(bx), y + 2, "─", theme.border_color, theme.bg_sidebar, false, false);
        }
        for (y..y + h) |by| {
            ren.drawText(x, @intCast(by), "│", theme.border_color, theme.bg_sidebar, false, false);
            ren.drawText(x + w - 1, @intCast(by), "│", theme.border_color, theme.bg_sidebar, false, false);
        }
        ren.drawText(x, y, "┌", theme.border_color, theme.bg_sidebar, false, false);
        ren.drawText(x + w - 1, y, "┐", theme.border_color, theme.bg_sidebar, false, false);
        ren.drawText(x, y + h - 1, "└", theme.border_color, theme.bg_sidebar, false, false);
        ren.drawText(x + w - 1, y + h - 1, "┘", theme.border_color, theme.bg_sidebar, false, false);
        ren.drawText(x, y + 2, "├", theme.border_color, theme.bg_sidebar, false, false);
        ren.drawText(x + w - 1, y + 2, "┤", theme.border_color, theme.bg_sidebar, false, false);

        ren.drawText(x + w - 2, y, "X", .{ .rgb = .{ .r = 255, .g = 0, .b = 0 } }, theme.bg_sidebar, true, false);

        const header_text = " GIT DETAILED ";
        ren.drawText(x + 2, y, header_text, theme.bg_sidebar, theme.fg_accent, true, false);

        // Tabs
        var tx: u16 = x + 18;
        inline for (@typeInfo(GitDetailedTab).@"enum".fields) |field| {
            const tab_enum = @as(GitDetailedTab, @enumFromInt(field.value));
            const label = tab_enum.label();
            const is_selected = (self.selected_tab == tab_enum);
            const fg = if (is_selected) theme.bg_sidebar else theme.fg_primary;
            const bg = if (is_selected) theme.fg_accent else theme.bg_sidebar;
            ren.drawText(tx, y, label, fg, bg, is_selected, false);
            tx += @as(u16, @intCast(label.len)) + 1;
        }

        const list_y = y + 3;
        const visible_items = h - 5;
        var rendered_count: usize = 0;
        var skipped_count: usize = 0;

        if (self.selected_tab == .history) {
            drawTextClipped(ren, x + 3, y + 1, "Hash", 8, theme.fg_secondary, theme.bg_sidebar, true, false);
            drawTextClipped(ren, x + 13, y + 1, "Author", 16, theme.fg_secondary, theme.bg_sidebar, true, false);
            drawTextClipped(ren, x + 31, y + 1, "Time", 14, theme.fg_secondary, theme.bg_sidebar, true, false);
            drawTextClipped(ren, x + 47, y + 1, "Message", w - 50, theme.fg_secondary, theme.bg_sidebar, true, false);

            for (self.commits.items, 0..) |commit, i| {
                if (skipped_count < self.scroll_offset) {
                    skipped_count += 1;
                    continue;
                }
                if (rendered_count >= visible_items) break;
                
                const py = list_y + @as(u16, @intCast(rendered_count));
                const is_selected = (i == self.selected_idx);
                const bg = if (is_selected) theme.bg_editor else theme.bg_sidebar;
                
                if (is_selected) {
                    for (x + 1..x + w - 1) |bx| {
                        ren.drawText(@intCast(bx), py, " ", theme.fg_primary, bg, false, false);
                    }
                }

                const prefix = if (is_selected) "»" else " ";
                ren.drawText(x + 1, py, prefix, theme.fg_accent, bg, true, false);

                drawTextClipped(ren, x + 3, py, commit.hash, 8, .{ .rgb = .{ .r = 220, .g = 180, .b = 50 } }, bg, false, false);
                drawTextClipped(ren, x + 13, py, commit.author, 16, .{ .rgb = .{ .r = 80, .g = 200, .b = 255 } }, bg, false, false);
                drawTextClipped(ren, x + 31, py, commit.time, 14, theme.fg_comment, bg, false, false);
                drawTextClipped(ren, x + 47, py, commit.msg, w - 50, if (is_selected) theme.fg_accent else theme.fg_primary, bg, false, false);
                
                rendered_count += 1;
            }
        } else if (self.selected_tab == .branches) {
            drawTextClipped(ren, x + 3, y + 1, "Branches", 16, theme.fg_secondary, theme.bg_sidebar, true, false);

            for (self.branches.items, 0..) |branch, i| {
                if (skipped_count < self.scroll_offset) {
                    skipped_count += 1;
                    continue;
                }
                if (rendered_count >= visible_items) break;
                
                const py = list_y + @as(u16, @intCast(rendered_count));
                const is_selected = (i == self.selected_idx);
                const bg = if (is_selected) theme.bg_editor else theme.bg_sidebar;
                
                if (is_selected) {
                    for (x + 1..x + w - 1) |bx| {
                        ren.drawText(@intCast(bx), py, " ", theme.fg_primary, bg, false, false);
                    }
                }

                const is_current = if (self.current_branch) |cb| std.mem.eql(u8, branch, cb) else false;
                const prefix = if (is_selected) "»" else if (is_current) "*" else " ";
                const fg = if (is_current) theme.fg_accent else theme.fg_primary;

                ren.drawText(x + 1, py, prefix, theme.fg_accent, bg, true, false);
                drawTextClipped(ren, x + 3, py, branch, w - 6, fg, bg, is_current, false);
                
                rendered_count += 1;
            }
        }

        const footer_y = y + h - 2;
        if (self.selected_tab == .history) {
            ren.drawText(x + 2, footer_y, " [c] checkout commit | [r] hard reset | [<Esc>] close ", theme.fg_comment, theme.bg_sidebar, false, false);
        } else {
            ren.drawText(x + 2, footer_y, " [Enter] checkout branch | [<Esc>] close ", theme.fg_comment, theme.bg_sidebar, false, false);
        }
    }

    pub fn handleMouse(self: *GitDetailedWidget, m: input.MouseEvent, screen_w: u16, screen_h: u16) bool {
        if (!self.is_open) return false;

        const w: u16 = @min(110, screen_w -| 4);
        const h: u16 = @min(34, screen_h -| 4);
        const x: u16 = (screen_w -| w) / 2;
        const y: u16 = (screen_h -| h) / 2;

        if (m.col >= x and m.col < x + w and m.row >= y and m.row < y + h) {
            if (m.action == .press and m.row == y and m.col == x + w - 2) {
                self.is_open = false;
                return true;
            }

            if (m.button == .wheel_up) {
                if (self.scroll_offset > 0) self.scroll_offset -= 1;
                return true;
            } else if (m.button == .wheel_down) {
                const visible_items = h - 5;
                const len = if (self.selected_tab == .history) self.commits.items.len else self.branches.items.len;
                if (len > visible_items and self.scroll_offset < len - visible_items) {
                    self.scroll_offset += 1;
                }
                return true;
            }

            if (m.action == .press) {
                if (m.row == y) {
                    var tx: u16 = x + 18;
                    inline for (@typeInfo(GitDetailedTab).@"enum".fields) |field| {
                        const tab_enum = @as(GitDetailedTab, @enumFromInt(field.value));
                        const label_len = tab_enum.label().len;
                        if (m.col >= tx and m.col < tx + label_len) {
                            self.selected_tab = tab_enum;
                            self.scroll_offset = 0;
                            self.selected_idx = 0;
                            return true;
                        }
                        tx += @as(u16, @intCast(label_len)) + 1;
                    }
                }

                const list_y = y + 3;
                const visible_items = h - 5;
                if (m.row >= list_y and m.row < list_y + visible_items) {
                    const click_row = m.row - list_y;
                    const idx = self.scroll_offset + click_row;
                    const len = if (self.selected_tab == .history) self.commits.items.len else self.branches.items.len;
                    if (idx < len) {
                        self.selected_idx = idx;
                    }
                }
            }
            return true;
        }
        return false;
    }

    pub fn handleKey(self: *GitDetailedWidget, key: []const u8) bool {
        if (!self.is_open) return false;

        if (std.mem.eql(u8, key, "<Esc>")) {
            self.is_open = false;
            return true;
        } else if (std.mem.eql(u8, key, "<Down>")) {
            const len = if (self.selected_tab == .history) self.commits.items.len else self.branches.items.len;
            if (self.selected_idx + 1 < len) {
                self.selected_idx += 1;
                self.ensureVisible();
            }
            return true;
        } else if (std.mem.eql(u8, key, "<Up>")) {
            if (self.selected_idx > 0) {
                self.selected_idx -= 1;
                self.ensureVisible();
            }
            return true;
        } else if (std.mem.eql(u8, key, "<Enter>")) {
            if (self.selected_tab == .branches) {
                if (self.selected_idx < self.branches.items.len) {
                    const branch = self.branches.items[self.selected_idx];
                    const argv = [_][]const u8{ "git", "checkout", branch };
                    if (git_utils.runGitCommand(self.allocator, self.io, &argv)) |res| {
                        self.allocator.free(res);
                    } else |_| {}
                    self.refresh();
                }
            }
            return true;
        } else if (std.mem.eql(u8, key, "c")) {
            if (self.selected_tab == .history and self.selected_idx < self.commits.items.len) {
                const hash = self.commits.items[self.selected_idx].hash;
                const argv = [_][]const u8{ "git", "checkout", hash };
                if (git_utils.runGitCommand(self.allocator, self.io, &argv)) |res| {
                    self.allocator.free(res);
                } else |_| {}
                self.refresh();
            }
            return true;
        } else if (std.mem.eql(u8, key, "r")) {
            if (self.selected_tab == .history and self.selected_idx < self.commits.items.len) {
                const hash = self.commits.items[self.selected_idx].hash;
                const argv = [_][]const u8{ "git", "reset", "--hard", hash };
                if (git_utils.runGitCommand(self.allocator, self.io, &argv)) |res| {
                    self.allocator.free(res);
                } else |_| {}
                self.refresh();
            }
            return true;
        } else if (key.len == 1 and key[0] >= '1' and key[0] <= '2') {
            const tab_idx = key[0] - '1';
            self.selected_tab = @as(GitDetailedTab, @enumFromInt(tab_idx));
            self.scroll_offset = 0;
            self.selected_idx = 0;
            return true;
        }
        return true; 
    }

    fn ensureVisible(self: *GitDetailedWidget) void {
        const visible_items = 29; // approximate height minus borders
        if (self.selected_idx < self.scroll_offset) {
            self.scroll_offset = self.selected_idx;
        } else if (self.selected_idx >= self.scroll_offset + visible_items) {
            self.scroll_offset = self.selected_idx - visible_items + 1;
        }
    }
};
