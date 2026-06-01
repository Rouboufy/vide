const std = @import("std");
const renderer = @import("../renderer.zig");
const Color = renderer.Color;
const Rect = @import("../layout.zig").Rect;

pub const GitItem = struct {
    path: []const u8,
    status: [2]u8, // e.g. "M ", " M", "??", "A "
    is_staged: bool,
};

pub const ActionState = enum { none, committing };

pub const GitPanel = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    arena: std.heap.ArenaAllocator,
    items: std.array_list.Managed(GitItem),
    
    current_branch: ?[]const u8 = null,
    recent_commits: std.array_list.Managed([]const u8),
    
    scroll_y: usize = 0,
    selected_idx: ?usize = null,

    is_staged_open: bool = true,
    is_changes_open: bool = true,
    is_commits_open: bool = true,

    commit_buf: [256]u8 = undefined,
    commit_len: usize = 0,
    is_focus_commit: bool = false,

    pub fn init(allocator: std.mem.Allocator, io: std.Io) GitPanel {
        return GitPanel{
            .allocator = allocator,
            .io = io,
            .arena = std.heap.ArenaAllocator.init(allocator),
            .items = std.array_list.Managed(GitItem).init(allocator),
            .recent_commits = std.array_list.Managed([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *GitPanel) void {
        self.items.deinit();
        self.recent_commits.deinit();
        self.arena.deinit();
    }

    pub fn refresh(self: *GitPanel) !void {
        self.items.clearRetainingCapacity();
        self.recent_commits.clearRetainingCapacity();
        _ = self.arena.reset(.retain_capacity);

        // 1. Fetch current branch
        {
            const argv = [_][]const u8{ "git", "branch", "--show-current" };
            var child = std.process.spawn(self.io, .{
                .argv = &argv,
                .stdout = .pipe,
                .stderr = .ignore,
            }) catch {
                self.current_branch = null;
                return;
            };

            var stdout = std.array_list.Managed(u8).init(self.allocator);
            defer stdout.deinit();
            if (child.stdout) |out| {
                while (true) {
                    var chunk: [1024]u8 = undefined;
                    const len = std.posix.read(out.handle, &chunk) catch 0;
                    if (len == 0) break;
                    stdout.appendSlice(chunk[0..len]) catch {};
                }
            }
            _ = child.wait(self.io) catch {};
            if (stdout.items.len > 0) {
                const clean_branch = std.mem.trim(u8, stdout.items, " \n\r");
                self.current_branch = try self.arena.allocator().dupe(u8, clean_branch);
            } else {
                self.current_branch = null;
            }
        }

        // 2. Fetch recent commits (Pipeline Graph)
        {
            const argv = [_][]const u8{ "git", "log", "--graph", "--abbrev-commit", "--format=format:%h - %s", "-n", "15" };
            var child = std.process.spawn(self.io, .{
                .argv = &argv,
                .stdout = .pipe,
                .stderr = .ignore,
            }) catch return;

            var stdout = std.array_list.Managed(u8).init(self.allocator);
            defer stdout.deinit();
            if (child.stdout) |out| {
                while (true) {
                    var chunk: [1024]u8 = undefined;
                    const len = std.posix.read(out.handle, &chunk) catch 0;
                    if (len == 0) break;
                    stdout.appendSlice(chunk[0..len]) catch {};
                }
            }
            _ = child.wait(self.io) catch {};
            
            var lines = std.mem.splitScalar(u8, stdout.items, '\n');
            while (lines.next()) |line| {
                var end: usize = line.len;
                while (end > 0 and (line[end - 1] == '\r' or line[end - 1] == ' ')) {
                    end -= 1;
                }
                const clean_line = line[0..end];
                if (clean_line.len > 0) {
                    try self.recent_commits.append(try self.arena.allocator().dupe(u8, clean_line));
                }
            }
        }

        // 3. Fetch status
        const argv = [_][]const u8{ "git", "status", "--porcelain" };
        var child = std.process.spawn(self.io, .{
            .argv = &argv,
            .stdout = .pipe,
            .stderr = .ignore,
        }) catch return;

        var stdout = std.array_list.Managed(u8).init(self.allocator);
        defer stdout.deinit();
        if (child.stdout) |out| {
            while (true) {
                var chunk: [1024]u8 = undefined;
                const len = std.posix.read(out.handle, &chunk) catch 0;
                if (len == 0) break;
                stdout.appendSlice(chunk[0..len]) catch {};
            }
        }
        _ = child.wait(self.io) catch {};

        var lines = std.mem.splitScalar(u8, stdout.items, '\n');
        while (lines.next()) |line| {
            if (line.len < 4) continue;
            const status = line[0..2];
            const rel_path = line[3..];
            
            var clean_path = rel_path;
            if (clean_path.len > 0 and clean_path[0] == '"' and clean_path[clean_path.len - 1] == '"') {
                clean_path = clean_path[1 .. clean_path.len - 1];
            }
            
            // X is index, Y is working tree
            const is_staged = (status[0] != ' ' and status[0] != '?');
            const is_unstaged = (status[1] != ' ');

            if (is_staged) {
                try self.items.append(.{
                    .path = try self.arena.allocator().dupe(u8, clean_path),
                    .status = .{ status[0], ' ' },
                    .is_staged = true,
                });
            }
            if (is_unstaged) {
                try self.items.append(.{
                    .path = try self.arena.allocator().dupe(u8, clean_path),
                    .status = .{ ' ', status[1] },
                    .is_staged = false,
                });
            }
        }

        // Sort: staged first, then alphabetically
        std.sort.block(GitItem, self.items.items, {}, struct {
            fn lessThan(_: void, a: GitItem, b: GitItem) bool {
                if (a.is_staged and !b.is_staged) return true;
                if (!a.is_staged and b.is_staged) return false;
                return std.mem.lessThan(u8, a.path, b.path);
            }
        }.lessThan);
    }

    pub fn handleMouse(self: *GitPanel, m_col: u16, m_row: u16, rect: Rect) !?[]const u8 {
        if (m_col >= rect.x and m_col < rect.x + rect.w and m_row >= rect.y and m_row < rect.y + rect.h) {
            const rel_y = m_row - rect.y;

            // Header line
            if (rel_y == 0) {
                if (m_col >= rect.x + rect.w - 10) {
                    return "__CMD__:GitWidget";
                }
                return null;
            }

            var cy: u16 = 1;

            // Branch line (no interaction anymore)
            if (rel_y == cy) {
                return null;
            }
            cy += 1;

            // Commit box
            if (rel_y == cy) {
                self.is_focus_commit = true;
                return null;
            } else {
                self.is_focus_commit = false;
            }
            cy += 1;

            // Divider
            cy += 1;

            // Headers and lists
            var i: usize = self.scroll_y;
            
            var has_staged = false;
            var has_unstaged = false;
            for (self.items.items) |item| {
                if (item.is_staged) has_staged = true;
                if (!item.is_staged) has_unstaged = true;
            }

            if (has_staged) {
                if (cy == rel_y) {
                    self.is_staged_open = !self.is_staged_open;
                    return null;
                }
                cy += 1;
                if (self.is_staged_open) {
                    while (i < self.items.items.len and self.items.items[i].is_staged and cy < rect.h) : ({ i += 1; cy += 1; }) {
                        if (cy == rel_y) {
                            self.selected_idx = i;
                            // check action buttons
                            if (m_col >= rect.x + rect.w - 3) {
                                try self.unstageFile(self.items.items[i].path);
                                return null;
                            }
                            return self.items.items[i].path;
                        }
                    }
                } else {
                    while (i < self.items.items.len and self.items.items[i].is_staged) : (i += 1) {}
                }
            }

            if (has_unstaged and cy < rect.h) {
                if (cy == rel_y) {
                    self.is_changes_open = !self.is_changes_open;
                    return null;
                }
                cy += 1;
                if (self.is_changes_open) {
                    while (i < self.items.items.len and !self.items.items[i].is_staged and cy < rect.h) : ({ i += 1; cy += 1; }) {
                        if (cy == rel_y) {
                            self.selected_idx = i;
                            // check action buttons
                            if (m_col >= rect.x + rect.w - 3) {
                                try self.stageFile(self.items.items[i].path);
                                return null;
                            }
                            return self.items.items[i].path;
                        }
                    }
                } else {
                    while (i < self.items.items.len and !self.items.items[i].is_staged) : (i += 1) {}
                }
            }

            // Commits
            if (self.recent_commits.items.len > 0 and cy < rect.h) {
                cy += 1;
                if (cy < rect.h) {
                    if (cy == rel_y) {
                        self.is_commits_open = !self.is_commits_open;
                        return null;
                    }
                    cy += 1;
                    if (self.is_commits_open) {
                        for (self.recent_commits.items) |_| {
                            if (cy >= rect.h) break;
                            if (cy == rel_y) return null;
                            cy += 1;
                        }
                    }
                }
            }
        }
        return null;
    }

    pub fn handleScroll(self: *GitPanel, dy: i32) void {
        if (dy < 0) {
            if (self.scroll_y > 0) self.scroll_y -= 1;
        } else if (dy > 0) {
            if (self.scroll_y + 1 < self.items.items.len) {
                self.scroll_y += 1;
            }
        }
    }

    pub fn handleKey(self: *GitPanel, key: []const u8) !bool {
        if (self.is_focus_commit) {
            if (std.mem.eql(u8, key, "<Enter>")) {
                if (self.commit_len > 0) {
                    try self.commit();
                }
                return true;
            } else if (std.mem.eql(u8, key, "<Esc>") or (key.len == 1 and key[0] == 0x1b)) {
                self.is_focus_commit = false;
                return true;
            } else if (std.mem.eql(u8, key, "<BS>") or std.mem.eql(u8, key, "\x7f")) {
                if (self.commit_len > 0) self.commit_len -= 1;
                return true;
            } else if (key.len == 1 and key[0] >= 32 and key[0] <= 126) {
                if (self.commit_len < self.commit_buf.len) {
                    self.commit_buf[self.commit_len] = key[0];
                    self.commit_len += 1;
                }
                return true;
            }
        }
        return false;
    }

    fn stageFile(self: *GitPanel, path: []const u8) !void {
        const argv = [_][]const u8{ "git", "add", path };
        var child = std.process.spawn(self.io, .{
            .argv = &argv,
        }) catch return;
        _ = child.wait(self.io) catch {};
        try self.refresh();
    }

    fn unstageFile(self: *GitPanel, path: []const u8) !void {
        const argv = [_][]const u8{ "git", "restore", "--staged", path };
        var child = std.process.spawn(self.io, .{
            .argv = &argv,
        }) catch return;
        _ = child.wait(self.io) catch {};
        try self.refresh();
    }

    fn commit(self: *GitPanel) !void {
        if (self.commit_len == 0) return;
        const msg = self.commit_buf[0..self.commit_len];
        const argv = [_][]const u8{ "git", "commit", "-m", msg };
        var child = std.process.spawn(self.io, .{
            .argv = &argv,
        }) catch return;
        _ = child.wait(self.io) catch {};
        
        self.commit_len = 0;
        self.is_focus_commit = false;
        try self.refresh();
    }

    fn drawTextClipped(rend: *renderer.Renderer, x: u16, y: u16, text: []const u8, max_w: u16, fg: Color, bg: Color, bold: bool, italic: bool) void {
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
            rend.setCell(col, y, cell);
            col += 1;
            i += len;
            rendered_len += 1;
        }
    }

    pub fn draw(self: *GitPanel, rend: *renderer.Renderer, rect: Rect, colors: anytype) void {
        rend.drawRect(rect, " ", colors.fg_primary, colors.bg_sidebar);
        
        // Draw title
        drawTextClipped(rend, rect.x + 1, rect.y, "SOURCE CONTROL", rect.w - 1, colors.fg_secondary, colors.bg_sidebar, true, false);
        
        // Detailed widget button
        if (rect.w >= 12) {
            rend.drawText(rect.x + rect.w - 10, rect.y, "[ More ]", colors.fg_accent, colors.bg_editor, true, false);
        }

        if (rect.h < 3) return;

        var cy: u16 = 1;

        // Branch Section
        var buf: [256]u8 = undefined;
        const branch_name = self.current_branch orelse "unknown";
        const branch_str = std.fmt.bufPrint(&buf, " {s}", .{branch_name}) catch " unknown";
        drawTextClipped(rend, rect.x + 1, rect.y + cy, branch_str, rect.w - 2, colors.fg_accent, colors.bg_sidebar, true, false);
        cy += 1;

        // Commit Box
        const c_bg = if (self.is_focus_commit) colors.bg_editor else colors.bg_sidebar;
        rend.drawRect(Rect{ .x = rect.x + 1, .y = rect.y + cy, .w = rect.w - 2, .h = 1 }, " ", colors.fg_primary, c_bg);
        const msg = std.fmt.bufPrint(&buf, "{s}{s}", .{self.commit_buf[0..self.commit_len], if (self.is_focus_commit) "_" else ""}) catch "";
        if (msg.len > 0) {
            drawTextClipped(rend, rect.x + 2, rect.y + cy, msg, rect.w - 4, colors.fg_primary, c_bg, false, false);
        } else {
            drawTextClipped(rend, rect.x + 2, rect.y + cy, "Message (Enter to commit)", rect.w - 4, colors.fg_secondary, c_bg, false, false);
        }
        cy += 1;
        if (cy >= rect.h) return;

        // Divider
        var i_w: u16 = 0;
        while (i_w < rect.w) : (i_w += 1) {
            rend.drawText(rect.x + i_w, rect.y + cy, "─", colors.border_color, colors.bg_sidebar, false, false);
        }
        cy += 1;

        var i: usize = self.scroll_y;
        
        var has_staged = false;
        var has_unstaged = false;
        for (self.items.items) |item| {
            if (item.is_staged) has_staged = true;
            if (!item.is_staged) has_unstaged = true;
        }

        if (has_staged and cy < rect.h) {
            const icon = if (self.is_staged_open) "v" else ">";
            const header = std.fmt.bufPrint(&buf, "{s} Staged Changes", .{icon}) catch "v Staged Changes";
            drawTextClipped(rend, rect.x + 1, rect.y + cy, header, rect.w - 1, colors.fg_secondary, colors.bg_sidebar, true, false);
            cy += 1;
            if (self.is_staged_open) {
                while (i < self.items.items.len and self.items.items[i].is_staged and cy < rect.h) : ({ i += 1; cy += 1; }) {
                    const item = self.items.items[i];
                    const is_sel = (self.selected_idx != null and self.selected_idx.? == i);
                    const bg = if (is_sel) colors.bg_editor else colors.bg_sidebar;
                    if (is_sel) rend.drawRect(Rect{ .x = rect.x, .y = rect.y + cy, .w = rect.w, .h = 1 }, " ", colors.fg_primary, bg);

                    drawTextClipped(rend, rect.x + 2, rect.y + cy, item.path, rect.w - 6, colors.fg_primary, bg, false, false);
                    const status_str = std.fmt.bufPrint(&buf, "{s}", .{item.status}) catch "";
                    rend.drawText(rect.x + rect.w - 6, rect.y + cy, status_str, .{ .rgb = .{ .r = 80, .g = 255, .b = 80 } }, bg, false, false);
                    rend.drawText(rect.x + rect.w - 3, rect.y + cy, " - ", colors.fg_accent, bg, true, false);
                }
            } else {
                while (i < self.items.items.len and self.items.items[i].is_staged) : (i += 1) {}
            }
        }

        if (has_unstaged and cy < rect.h) {
            const icon = if (self.is_changes_open) "v" else ">";
            const header = std.fmt.bufPrint(&buf, "{s} Changes", .{icon}) catch "v Changes";
            drawTextClipped(rend, rect.x + 1, rect.y + cy, header, rect.w - 1, colors.fg_secondary, colors.bg_sidebar, true, false);
            cy += 1;
            if (self.is_changes_open) {
                while (i < self.items.items.len and !self.items.items[i].is_staged and cy < rect.h) : ({ i += 1; cy += 1; }) {
                    const item = self.items.items[i];
                    const is_sel = (self.selected_idx != null and self.selected_idx.? == i);
                    const bg = if (is_sel) colors.bg_editor else colors.bg_sidebar;
                    if (is_sel) rend.drawRect(Rect{ .x = rect.x, .y = rect.y + cy, .w = rect.w, .h = 1 }, " ", colors.fg_primary, bg);

                    drawTextClipped(rend, rect.x + 2, rect.y + cy, item.path, rect.w - 6, colors.fg_primary, bg, false, false);
                    const status_str = std.fmt.bufPrint(&buf, "{s}", .{item.status}) catch "";
                    rend.drawText(rect.x + rect.w - 6, rect.y + cy, status_str, .{ .rgb = .{ .r = 255, .g = 80, .b = 80 } }, bg, false, false);
                    rend.drawText(rect.x + rect.w - 3, rect.y + cy, " + ", colors.fg_accent, bg, true, false);
                }
            } else {
                while (i < self.items.items.len and !self.items.items[i].is_staged) : (i += 1) {}
            }
        }

        // Draw Commits (Pipeline)
        if (self.recent_commits.items.len > 0 and cy < rect.h) {
            cy += 1;
            if (cy < rect.h) {
                const icon = if (self.is_commits_open) "v" else ">";
                const header = std.fmt.bufPrint(&buf, "{s} Pipeline", .{icon}) catch "v Pipeline";
                drawTextClipped(rend, rect.x + 1, rect.y + cy, header, rect.w - 1, colors.fg_secondary, colors.bg_sidebar, true, false);
                cy += 1;
                if (self.is_commits_open) {
                    for (self.recent_commits.items) |c_line| {
                        if (cy >= rect.h) break;
                        drawTextClipped(rend, rect.x + 2, rect.y + cy, c_line, rect.w - 3, colors.fg_primary, colors.bg_sidebar, false, false);
                        cy += 1;
                    }
                }
            }
        }
    }
};
