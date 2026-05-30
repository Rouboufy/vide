const std = @import("std");
const renderer = @import("../renderer.zig");
const Color = renderer.Color;
const Rect = @import("../layout.zig").Rect;

fn getFileIcon(name: []const u8) []const u8 {
    if (std.mem.endsWith(u8, name, ".zig")) return " ";
    if (std.mem.endsWith(u8, name, ".lua")) return " ";
    if (std.mem.endsWith(u8, name, ".py")) return " ";
    if (std.mem.endsWith(u8, name, ".md")) return " ";
    if (std.mem.endsWith(u8, name, ".js") or std.mem.endsWith(u8, name, ".ts") or std.mem.endsWith(u8, name, ".jsx") or std.mem.endsWith(u8, name, ".tsx")) return " ";
    if (std.mem.endsWith(u8, name, ".html")) return " ";
    if (std.mem.endsWith(u8, name, ".css")) return " ";
    if (std.mem.endsWith(u8, name, ".json")) return " ";
    if (std.mem.endsWith(u8, name, ".c") or std.mem.endsWith(u8, name, ".cpp") or std.mem.endsWith(u8, name, ".h") or std.mem.endsWith(u8, name, ".hpp")) return " ";
    if (std.mem.endsWith(u8, name, ".rs")) return " ";
    if (std.mem.endsWith(u8, name, ".sh")) return " ";
    if (std.mem.endsWith(u8, name, ".toml") or std.mem.endsWith(u8, name, ".yml") or std.mem.endsWith(u8, name, ".yaml") or std.mem.endsWith(u8, name, ".conf")) return " ";
    if (std.mem.endsWith(u8, name, ".txt")) return "󰈙 ";
    return "󰈔 ";
}

pub const ExplorerItem = struct {
    path: []const u8, // relative path
    name: []const u8,
    is_dir: bool,
    expanded: bool,
    depth: u16,
};

pub const ActionState = enum { none, creating_file, creating_dir, deleting };

pub const Explorer = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    expanded_dirs: std.StringHashMap(void),
    items: std.array_list.Managed(ExplorerItem),
    arena: std.heap.ArenaAllocator,
    
    scroll_y: usize = 0,
    selected_idx: ?usize = null,

    // File action state
    action_state: ActionState = .none,
    input_buf: [256]u8 = undefined,
    input_len: usize = 0,
    action_target_path: ?[]const u8 = null, // The directory in which to create, or file to delete

    pub fn init(allocator: std.mem.Allocator, io: std.Io) Explorer {
        return Explorer{
            .allocator = allocator,
            .io = io,
            .expanded_dirs = std.StringHashMap(void).init(allocator),
            .items = std.array_list.Managed(ExplorerItem).init(allocator),
            .arena = std.heap.ArenaAllocator.init(allocator),
            .action_state = .none,
        };
    }

    pub fn deinit(self: *Explorer) void {
        self.expanded_dirs.deinit();
        self.items.deinit();
        self.arena.deinit();
    }

    pub fn refresh(self: *Explorer) !void {
        self.items.clearRetainingCapacity();
        _ = self.arena.reset(.retain_capacity);

        try self.scanDir(".", 0);
    }

    fn scanDir(self: *Explorer, dir_path: []const u8, depth: u16) !void {
        var dir = std.Io.Dir.cwd().openDir(self.io, dir_path, .{ .iterate = true }) catch return;
        defer dir.close(self.io);

        var iter = dir.iterate();
        const EntryInfo = struct { name: []const u8, is_dir: bool };
        var entries = std.array_list.Managed(EntryInfo).init(self.arena.allocator());
        
        while (try iter.next(self.io)) |entry| {
            if (std.mem.eql(u8, entry.name, ".git") or std.mem.eql(u8, entry.name, "zig-cache") or std.mem.eql(u8, entry.name, "zig-out")) continue;
            try entries.append(.{
                .name = try self.arena.allocator().dupe(u8, entry.name),
                .is_dir = entry.kind == .directory,
            });
        }

        // Sort: dirs first, then files, alphabetically
        std.sort.block(EntryInfo, entries.items, {}, struct {
            fn lessThan(_: void, a: EntryInfo, b: EntryInfo) bool {
                if (a.is_dir and !b.is_dir) return true;
                if (!a.is_dir and b.is_dir) return false;
                return std.mem.lessThan(u8, a.name, b.name);
            }
        }.lessThan);

        for (entries.items) |entry| {
            const rel_path = if (std.mem.eql(u8, dir_path, ".")) 
                entry.name 
            else 
                try std.fmt.allocPrint(self.arena.allocator(), "{s}/{s}", .{dir_path, entry.name});

            const expanded = self.expanded_dirs.contains(rel_path);

            try self.items.append(.{
                .path = rel_path,
                .name = entry.name,
                .is_dir = entry.is_dir,
                .expanded = expanded,
                .depth = depth,
            });

            if (entry.is_dir and expanded) {
                try self.scanDir(rel_path, depth + 1);
            }
        }
    }

    pub fn toggleExpand(self: *Explorer, path: []const u8) !void {
        if (self.expanded_dirs.contains(path)) {
            _ = self.expanded_dirs.remove(path);
        } else {
            try self.expanded_dirs.put(try self.allocator.dupe(u8, path), {});
        }
        try self.refresh();
    }
    
    pub fn handleDelete(self: *Explorer) !void {
        if (self.action_target_path) |path| {
            if (std.Io.Dir.cwd().deleteFile(self.io, path)) {} else |err| {
                if (err == error.IsDir) {
                    if (std.Io.Dir.cwd().deleteTree(self.io, path)) {} else |_| {}
                }
            }
        }
        self.action_state = .none;
        self.action_target_path = null;
        try self.refresh();
    }
    
    pub fn handleCreateFile(self: *Explorer) !void {
        if (self.input_len == 0) {
            self.action_state = .none;
            return;
        }
        const name = self.input_buf[0..self.input_len];
        const path = if (self.action_target_path) |p| 
            try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{p, name})
        else
            try self.allocator.dupe(u8, name);
        defer self.allocator.free(path);
        
        if (self.action_state == .creating_dir) {
            if (std.Io.Dir.cwd().createDir(self.io, path, .default_dir)) {} else |_| {}
        } else {
            if (std.Io.Dir.cwd().createFile(self.io, path, .{})) |*f| { f.close(self.io); } else |_| {}
        }
        
        self.action_state = .none;
        self.action_target_path = null;
        self.input_len = 0;
        try self.refresh();
    }

    pub fn handleMouse(self: *Explorer, m_col: u16, m_row: u16, rect: Rect) !?[]const u8 {
        if (m_col >= rect.x and m_col < rect.x + rect.w and m_row >= rect.y and m_row < rect.y + rect.h) {
            const rel_y = m_row - rect.y;
            
            // Handle action bar (top line)
            if (rel_y == 0) {
                if (m_col >= rect.x + rect.w - 8 and m_col <= rect.x + rect.w - 6) {
                    self.action_state = .creating_file;
                    self.input_len = 0;
                    if (self.selected_idx) |idx| {
                        const sel = self.items.items[idx];
                        self.action_target_path = if (sel.is_dir) sel.path else std.fs.path.dirname(sel.path) orelse ".";
                    } else {
                        self.action_target_path = null;
                    }
                    return null;
                }
                if (m_col >= rect.x + rect.w - 5 and m_col <= rect.x + rect.w - 3) {
                    self.action_state = .creating_dir;
                    self.input_len = 0;
                    if (self.selected_idx) |idx| {
                        const sel = self.items.items[idx];
                        self.action_target_path = if (sel.is_dir) sel.path else std.fs.path.dirname(sel.path) orelse ".";
                    } else {
                        self.action_target_path = null;
                    }
                    return null;
                }
                if (m_col >= rect.x + rect.w - 2 and m_col <= rect.x + rect.w) {
                    if (self.selected_idx) |idx| {
                        self.action_state = .deleting;
                        self.action_target_path = self.items.items[idx].path;
                    }
                    return null;
                }
                return null;
            }
            
            if (self.action_state != .none) {
                return null; // Don't allow clicking items while prompt is open
            }

            const item_idx = rel_y - 1 + self.scroll_y;
            if (item_idx < self.items.items.len) {
                self.selected_idx = item_idx;
                const item = self.items.items[item_idx];
                if (item.is_dir) {
                    try self.toggleExpand(item.path);
                    return null;
                } else {
                    return item.path; // Return path to open
                }
            } else {
                self.selected_idx = null;
            }
        }
        return null;
    }

    pub fn handleScroll(self: *Explorer, dy: i32) void {
        if (dy < 0) {
            if (self.scroll_y > 0) self.scroll_y -= 1;
        } else if (dy > 0) {
            if (self.scroll_y + 1 < self.items.items.len) {
                self.scroll_y += 1;
            }
        }
    }

    pub fn handleKey(self: *Explorer, key: []const u8) !bool {
        if (self.action_state == .none) return false;

        if (std.mem.eql(u8, key, "<Enter>")) {
            if (self.action_state == .deleting) {
                try self.handleDelete();
            } else {
                try self.handleCreateFile();
            }
            return true;
        } else if (std.mem.eql(u8, key, "<Esc>") or (key.len == 1 and key[0] == 0x1b)) {
            self.action_state = .none;
            return true;
        } else if (std.mem.eql(u8, key, "<BS>") or std.mem.eql(u8, key, "\x7f")) {
            if (self.input_len > 0) self.input_len -= 1;
            return true;
        } else if (key.len == 1 and key[0] >= 32 and key[0] <= 126 and self.action_state != .deleting) {
            if (self.input_len < self.input_buf.len) {
                self.input_buf[self.input_len] = key[0];
                self.input_len += 1;
            }
            return true;
        }
        return false;
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

    pub fn draw(self: *Explorer, rend: *renderer.Renderer, rect: Rect, colors: anytype) void {
        rend.drawRect(rect, " ", colors.fg_primary, colors.bg_sidebar);
        
        // Draw title and buttons
        drawTextClipped(rend, rect.x + 1, rect.y, "EXPLORER", rect.w - 1, colors.fg_secondary, colors.bg_sidebar, true, false);
        
        if (rect.w >= 8) {
            drawTextClipped(rend, rect.x + rect.w - 8, rect.y, "+F", 2, colors.fg_accent, colors.bg_sidebar, true, false);
            drawTextClipped(rend, rect.x + rect.w - 5, rect.y, "+D", 2, colors.fg_accent, colors.bg_sidebar, true, false);
            drawTextClipped(rend, rect.x + rect.w - 2, rect.y, " X", 2, colors.fg_accent, colors.bg_sidebar, true, false);
        }

        const max_items = @max(1, rect.h - 1);
        var y: u16 = 1;
        
        // Draw Items
        var i: usize = self.scroll_y;
        while (i < self.items.items.len and y < max_items) : ({ i += 1; y += 1; }) {
            const item = self.items.items[i];
            const is_selected = (self.selected_idx != null and self.selected_idx.? == i);
            const bg = if (is_selected) colors.bg_editor else colors.bg_sidebar;
            
            // Highlight selected row
            if (is_selected) {
                rend.drawRect(Rect{ .x = rect.x, .y = rect.y + y, .w = rect.w, .h = 1 }, " ", colors.fg_primary, bg);
            }

            const indent = item.depth * 2;
            const prefix = if (item.is_dir) (if (item.expanded) "v " else "> ") else "  ";
            
            // Icon
            const icon = if (item.is_dir) "󰉋 " else getFileIcon(item.name);
            const text_x = rect.x + 1 + @as(u16, @intCast(indent));
            
            var avail_w: u16 = 0;
            if (text_x < rect.x + rect.w) avail_w = rect.x + rect.w - text_x;
            if (avail_w > 0) {
                var buf: [256]u8 = undefined;
                const formatted = std.fmt.bufPrint(&buf, "{s}{s}{s}", .{prefix, icon, item.name}) catch continue;
                drawTextClipped(rend, text_x, rect.y + y, formatted, avail_w, colors.fg_primary, bg, false, false);
            }
        }

        // Draw prompt if action_state != .none
        if (self.action_state != .none and rect.h > 2) {
            const prompt_y = rect.y + rect.h - 1;
            rend.drawRect(Rect{ .x = rect.x, .y = prompt_y - 1, .w = rect.w, .h = 2 }, " ", colors.fg_primary, colors.bg_editor);
            
            const ptext = switch (self.action_state) {
                .creating_file => "New File:",
                .creating_dir => "New Dir:",
                .deleting => "Del? (Enter=Y):",
                else => "",
            };
            drawTextClipped(rend, rect.x + 1, prompt_y - 1, ptext, rect.w - 2, colors.fg_accent, colors.bg_editor, true, false);
            
            var val_buf: [256]u8 = undefined;
            const val_text = if (self.action_state == .deleting) 
                self.action_target_path orelse ""
            else
                self.input_buf[0..self.input_len];
            
            const display_val = std.fmt.bufPrint(&val_buf, "{s}_", .{val_text}) catch val_text;
            drawTextClipped(rend, rect.x + 1, prompt_y, display_val, rect.w - 2, colors.fg_primary, colors.bg_editor, false, false);
        }
    }
};
