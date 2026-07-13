const std = @import("std");
const msgpack = @import("msgpack.zig");
const Value = msgpack.Value;
const Color = @import("../tui/renderer.zig").Color;
const Cell = @import("../tui/renderer.zig").Cell;

fn gridCellRepeat(has_repeat: bool, repeat_value: i64) usize {
    if (!has_repeat) return 1;
    return if (repeat_value > 0) @as(usize, @intCast(repeat_value)) else 0;
}

fn values(items: []const Value) []Value {
    return @constCast(items);
}

fn kvs(items: []const Value.KV) []Value.KV {
    return @constCast(items);
}

pub const Highlight = struct {
    fg: Color = .none,
    bg: Color = .none,
    bold: bool = false,
    italic: bool = false,
    reverse: bool = false,
};

pub const GridData = struct {
    width: u16 = 0,
    height: u16 = 0,
    cells: []Cell = &[_]Cell{},
    /// Screen position (in Neovim coordinate space, i.e. within the editor area)
    row: i32 = 0,
    col: i32 = 0,
    visible: bool = true,
    is_float: bool = false,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) GridData {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *GridData) void {
        self.allocator.free(self.cells);
    }

    pub fn resize(self: *GridData, new_w: u16, new_h: u16) !void {
        const size = @as(usize, new_w) * @as(usize, new_h);
        const new_cells = try self.allocator.alloc(Cell, size);
        @memset(new_cells, Cell{ .char = [_]u8{ ' ', 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }, .len = 1, .fg = .none, .bg = .none });
        const min_h = @min(self.height, new_h);
        const min_w = @min(self.width, new_w);
        for (0..min_h) |y| {
            for (0..min_w) |x| {
                new_cells[y * new_w + x] = self.cells[y * self.width + x];
            }
        }
        self.allocator.free(self.cells);
        self.cells = new_cells;
        self.width = new_w;
        self.height = new_h;
    }

    pub fn clear(self: *GridData) void {
        @memset(self.cells, Cell{ .char = [_]u8{ ' ', 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }, .len = 1, .fg = .none, .bg = .none });
    }
};

/// Entry in the grid map
const GridEntry = struct {
    id: i64,
    data: GridData,
};

pub const UiState = struct {
    /// Grid 1 (global/cmdline area) kept separate for clarity
    grid: GridData,
    /// All secondary grids (windows + floats), keyed by grid_id > 1
    secondary_grids: std.ArrayListUnmanaged(GridEntry),
    highlights: std.AutoHashMap(i64, Highlight),
    default_fg: Color = .none,
    default_bg: Color = .none,
    /// Cursor position within its own grid
    cursor_x: u16 = 0,
    cursor_y: u16 = 0,
    /// Which grid currently has the cursor
    cursor_grid: i64 = 1,
    allocator: std.mem.Allocator,
    telescope_rects: [2]?@import("../tui/layout.zig").Rect = .{ null, null },
    widget_title: [32]u8 = undefined,
    widget_title_len: usize = 0,
    toggle_zen_requested: bool = false,
    toggle_ide_requested: bool = false,
    theme_changed: bool = false,
    cursorline_bg: Color = .none,
    normal_bg: Color = .none,

    pub fn init(allocator: std.mem.Allocator) UiState {
        return .{
            .grid = GridData.init(allocator),
            .secondary_grids = .empty,
            .highlights = std.AutoHashMap(i64, Highlight).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *UiState) void {
        self.grid.deinit();
        for (self.secondary_grids.items) |*e| e.data.deinit();
        self.secondary_grids.deinit(self.allocator);
        self.highlights.deinit();
    }

    fn getOrCreate(self: *UiState, id: i64) !*GridData {
        for (self.secondary_grids.items) |*e| {
            if (e.id == id) return &e.data;
        }
        try self.secondary_grids.append(self.allocator, .{ .id = id, .data = GridData.init(self.allocator) });
        return &self.secondary_grids.items[self.secondary_grids.items.len - 1].data;
    }

    fn get(self: *UiState, id: i64) ?*GridData {
        for (self.secondary_grids.items) |*e| {
            if (e.id == id) return &e.data;
        }
        return null;
    }

    fn remove(self: *UiState, id: i64) void {
        for (self.secondary_grids.items, 0..) |*e, i| {
            if (e.id == id) {
                e.data.deinit();
                _ = self.secondary_grids.orderedRemove(i);
                return;
            }
        }
    }

    /// Returns the final screen cursor position in Neovim-space coordinates
    /// (i.e., relative to the editor area top-left).
    /// Caller adds layout.editor.x / .y to get screen coords.
    pub fn cursorScreenPos(self: *const UiState) struct { x: i32, y: i32 } {
        if (self.cursor_grid == 1) {
            return .{ .x = @as(i32, self.cursor_x), .y = @as(i32, self.cursor_y) };
        }
        for (self.secondary_grids.items) |*e| {
            if (e.id == self.cursor_grid) {
                return .{
                    .x = e.data.col + @as(i32, self.cursor_x),
                    .y = e.data.row + @as(i32, self.cursor_y),
                };
            }
        }
        return .{ .x = @as(i32, self.cursor_x), .y = @as(i32, self.cursor_y) };
    }

    fn handleDefaultColorsSet(self: *UiState, args: []const Value) void {
        for (args) |arg| {
            if (arg != .array or arg.array.len < 2) continue;
            const fg = arg.array[0].integer;
            const bg = arg.array[1].integer;
            self.default_fg = if (fg != -1) Color{ .rgb = .{
                .r = @as(u8, @intCast((fg >> 16) & 0xff)),
                .g = @as(u8, @intCast((fg >> 8) & 0xff)),
                .b = @as(u8, @intCast(fg & 0xff)),
            } } else .none;
            self.default_bg = if (bg != -1) Color{ .rgb = .{
                .r = @as(u8, @intCast((bg >> 16) & 0xff)),
                .g = @as(u8, @intCast((bg >> 8) & 0xff)),
                .b = @as(u8, @intCast(bg & 0xff)),
            } } else .none;
        }
    }

    fn handleHlAttrDefine(self: *UiState, args: []const Value) !void {
        for (args) |arg| {
            if (arg != .array or arg.array.len < 2) continue;
            const id = arg.array[0].integer;
            const rgb_attrs = arg.array[1];
            var hl = Highlight{ .fg = .none, .bg = .none };
            if (rgb_attrs == .map) {
                for (rgb_attrs.map) |kv| {
                    if (kv.key != .string) continue;
                    const key = kv.key.string;
                    if (std.mem.eql(u8, key, "foreground")) {
                        const val = kv.value.integer;
                        hl.fg = Color{ .rgb = .{
                            .r = @as(u8, @intCast((val >> 16) & 0xff)),
                            .g = @as(u8, @intCast((val >> 8) & 0xff)),
                            .b = @as(u8, @intCast(val & 0xff)),
                        } };
                    } else if (std.mem.eql(u8, key, "background")) {
                        const val = kv.value.integer;
                        hl.bg = Color{ .rgb = .{
                            .r = @as(u8, @intCast((val >> 16) & 0xff)),
                            .g = @as(u8, @intCast((val >> 8) & 0xff)),
                            .b = @as(u8, @intCast(val & 0xff)),
                        } };
                    } else if (std.mem.eql(u8, key, "bold")) {
                        hl.bold = kv.value.bool;
                    } else if (std.mem.eql(u8, key, "italic")) {
                        hl.italic = kv.value.bool;
                    } else if (std.mem.eql(u8, key, "reverse")) {
                        hl.reverse = kv.value.bool;
                    }
                }
            }
            try self.highlights.put(id, hl);
            if (arg.array.len >= 4) {
                const info = arg.array[3];
                if (info == .array) {
                    for (info.array) |inf| {
                        if (inf == .map) {
                            var is_cursorline = false;
                            var is_normal = false;
                            for (inf.map) |kv| {
                                if (kv.key == .string and (std.mem.eql(u8, kv.key.string, "ui_name") or std.mem.eql(u8, kv.key.string, "hi_name"))) {
                                    if (kv.value == .string and std.mem.eql(u8, kv.value.string, "CursorLine")) {
                                        is_cursorline = true;
                                    }
                                    if (kv.value == .string and std.mem.eql(u8, kv.value.string, "Normal")) {
                                        is_normal = true;
                                    }
                                }
                            }
                            if (is_cursorline) {
                                self.cursorline_bg = hl.bg;
                            }
                            if (is_normal) {
                                self.normal_bg = hl.bg;
                            }
                        }
                    }
                }
            }
        }
    }

    fn handleGridResize(self: *UiState, args: []const Value) !void {
        for (args) |arg| {
            if (arg != .array or arg.array.len < 3) continue;
            const id = arg.array[0].integer;
            const w = @as(u16, @intCast(arg.array[1].integer));
            const h = @as(u16, @intCast(arg.array[2].integer));
            if (id == 1) {
                try self.grid.resize(w, h);
            } else {
                const g = try self.getOrCreate(id);
                try g.resize(w, h);
            }
        }
    }

    fn handleGridClear(self: *UiState, args: []const Value) void {
        for (args) |arg| {
            if (arg != .array or arg.array.len < 1) continue;
            const id = arg.array[0].integer;
            if (id == 1) {
                self.grid.clear();
            } else {
                if (self.get(id)) |g| g.clear();
            }
        }
    }

    fn handleGridDestroy(self: *UiState, args: []const Value) void {
        for (args) |arg| {
            if (arg != .array or arg.array.len < 1) continue;
            const id = arg.array[0].integer;
            if (id != 1) self.remove(id);
        }
    }

    fn handleWinPos(self: *UiState, args: []const Value) !void {
        for (args) |arg| {
            if (arg != .array or arg.array.len < 4) continue;
            const id = arg.array[0].integer;
            if (id == 1) continue;
            const g = try self.getOrCreate(id);
            g.row = @as(i32, @intCast(arg.array[2].integer));
            g.col = @as(i32, @intCast(arg.array[3].integer));
            g.is_float = false;
            g.visible = true;
        }
    }

    fn handleMsgSetPos(self: *UiState, args: []const Value) !void {
        for (args) |arg| {
            if (arg != .array or arg.array.len < 3) continue;
            const id = arg.array[0].integer;
            const g = try self.getOrCreate(id);
            g.row = @as(i32, @intCast(arg.array[1].integer));
            g.col = 0;
            g.is_float = true;
            g.visible = true;
        }
    }

    fn handleWinFloatPos(self: *UiState, args: []const Value) !void {
        for (args) |arg| {
            if (arg != .array or arg.array.len < 1) continue;
            const id = arg.array[0].integer;
            if (id == 1) continue;
            const g = try self.getOrCreate(id);
            g.is_float = true;
            g.visible = true;
            if (arg.array.len >= 11 and
                arg.array[9] == .integer and
                arg.array[10] == .integer)
            {
                g.row = @as(i32, @intCast(arg.array[9].integer));
                g.col = @as(i32, @intCast(arg.array[10].integer));
            }
        }
    }

    fn handleWinHide(self: *UiState, args: []const Value) void {
        for (args) |arg| {
            if (arg != .array or arg.array.len < 1) continue;
            const id = arg.array[0].integer;
            if (self.get(id)) |g| g.visible = false;
        }
    }

    fn handleWinClose(self: *UiState, args: []const Value) void {
        for (args) |arg| {
            if (arg != .array or arg.array.len < 1) continue;
            self.remove(arg.array[0].integer);
        }
    }

    fn handleGridCursorGoto(self: *UiState, args: []const Value) void {
        for (args) |arg| {
            if (arg != .array or arg.array.len < 3) continue;
            self.cursor_grid = arg.array[0].integer;
            self.cursor_y = @as(u16, @intCast(arg.array[1].integer));
            self.cursor_x = @as(u16, @intCast(arg.array[2].integer));
        }
    }

    fn handleGridScroll(self: *UiState, args: []const Value) void {
        for (args) |arg| {
            if (arg != .array or arg.array.len < 7) continue;
            const id = arg.array[0].integer;
            const target: *GridData = if (id == 1) &self.grid else blk: {
                if (self.get(id)) |g| break :blk g;
                continue;
            };
            const top: u16 = @as(u16, @intCast(@max(0, arg.array[1].integer)));
            const bot: u16 = @as(u16, @intCast(@max(0, arg.array[2].integer)));
            const left: u16 = @as(u16, @intCast(@max(0, arg.array[3].integer)));
            const right: u16 = @as(u16, @intCast(@max(0, arg.array[4].integer)));
            const rows: i64 = arg.array[5].integer;
            if (top >= target.height or bot > target.height or
                left >= target.width or right > target.width or
                top >= bot or left >= right) continue;
            if (rows > 0) {
                var y = top;
                const ur = @as(u16, @intCast(rows));
                if (bot > ur) {
                    while (y < bot - ur) : (y += 1) {
                        const src_y = y + ur;
                        for (left..right) |x| {
                            target.cells[@as(usize, y) * @as(usize, target.width) + x] =
                                target.cells[@as(usize, src_y) * @as(usize, target.width) + x];
                        }
                    }
                }
            } else if (rows < 0) {
                const abs_rows = @as(u16, @intCast(-rows));
                if (bot > 0) {
                    var y = bot;
                    while (y > top + abs_rows) {
                        y -= 1;
                        const src_y = y - abs_rows;
                        for (left..right) |x| {
                            target.cells[@as(usize, y) * @as(usize, target.width) + x] =
                                target.cells[@as(usize, src_y) * @as(usize, target.width) + x];
                        }
                    }
                }
            }
        }
    }

    fn handleGridLine(self: *UiState, args: []const Value) !void {
        for (args) |arg| {
            if (arg != .array or arg.array.len < 4) continue;
            const id = arg.array[0].integer;
            const row = @as(u16, @intCast(arg.array[1].integer));
            var col = @as(u16, @intCast(arg.array[2].integer));
            const cells_val = arg.array[3];
            if (cells_val != .array) continue;

            const target: *GridData = if (id == 1) &self.grid else blk: {
                if (self.get(id)) |g| break :blk g;
                const g = self.getOrCreate(id) catch continue;
                break :blk g;
            };

            var current_hl_id: i64 = 0;
            for (cells_val.array) |c| {
                if (c != .array or c.array.len < 1) continue;
                const text = if (c.array[0] == .string) c.array[0].string else " ";
                if (c.array.len >= 2) current_hl_id = c.array[1].integer;
                // An omitted repeat means one cell. An explicitly supplied
                // zero means zero cells; Neovim uses this in incremental
                // updates, and treating it as one erases the following cell.
                const has_repeat = c.array.len >= 3;
                const repeat_i = if (has_repeat) c.array[2].integer else 1;
                const repeat = gridCellRepeat(has_repeat, repeat_i);
                const hl = self.highlights.get(current_hl_id) orelse Highlight{ .fg = .none, .bg = .none };
                var rep: usize = 0;
                while (rep < repeat) : (rep += 1) {
                    if (row < target.height and col < target.width) {
                        var cell = Cell{ .fg = hl.fg, .bg = hl.bg, .bold = hl.bold, .italic = hl.italic, .reverse = hl.reverse };
                        cell.setChar(text);
                        target.cells[@as(usize, row) * @as(usize, target.width) + col] = cell;
                    }
                    col += 1;
                }
            }
        }
    }

    pub fn handleRedraw(self: *UiState, events: []const Value) !void {
        for (events) |ev| {
            if (ev != .array or ev.array.len < 2) continue;
            const name = ev.array[0].string;
            const args = ev.array[1..];

            if (std.mem.eql(u8, name, "default_colors_set")) {
                self.handleDefaultColorsSet(args);
            } else if (std.mem.eql(u8, name, "hl_attr_define")) {
                try self.handleHlAttrDefine(args);
            } else if (std.mem.eql(u8, name, "grid_resize")) {
                try self.handleGridResize(args);
            } else if (std.mem.eql(u8, name, "grid_clear")) {
                self.handleGridClear(args);
            } else if (std.mem.eql(u8, name, "grid_destroy")) {
                self.handleGridDestroy(args);
            } else if (std.mem.eql(u8, name, "win_pos")) {
                try self.handleWinPos(args);
            } else if (std.mem.eql(u8, name, "msg_set_pos")) {
                try self.handleMsgSetPos(args);
            } else if (std.mem.eql(u8, name, "win_float_pos")) {
                try self.handleWinFloatPos(args);
            } else if (std.mem.eql(u8, name, "win_hide")) {
                self.handleWinHide(args);
            } else if (std.mem.eql(u8, name, "win_close")) {
                self.handleWinClose(args);
            } else if (std.mem.eql(u8, name, "grid_cursor_goto")) {
                self.handleGridCursorGoto(args);
            } else if (std.mem.eql(u8, name, "grid_scroll")) {
                self.handleGridScroll(args);
            } else if (std.mem.eql(u8, name, "grid_line")) {
                try self.handleGridLine(args);
            }
        }
    }
};

test "grid cell repeat distinguishes omitted and explicit zero" {
    try std.testing.expectEqual(@as(usize, 1), gridCellRepeat(false, 0));
    try std.testing.expectEqual(@as(usize, 0), gridCellRepeat(true, 0));
    try std.testing.expectEqual(@as(usize, 3), gridCellRepeat(true, 3));
}

test "ui protocol replays grid line, scroll, cursor, and grid lifecycle events" {
    var state = UiState.init(std.testing.allocator);
    defer state.deinit();

    const resize_events = [_]Value{
        .{ .array = values(&[_]Value{
            .{ .string = "grid_resize" },
            .{ .array = values(&[_]Value{ .{ .integer = 1 }, .{ .integer = 4 }, .{ .integer = 3 } }) },
            .{ .array = values(&[_]Value{ .{ .integer = 2 }, .{ .integer = 4 }, .{ .integer = 2 } }) },
            .{ .array = values(&[_]Value{ .{ .integer = 3 }, .{ .integer = 4 }, .{ .integer = 2 } }) },
        }) },
    };
    try state.handleRedraw(&resize_events);

    const hl_events = [_]Value{
        .{ .array = values(&[_]Value{
            .{ .string = "hl_attr_define" },
            .{ .array = values(&[_]Value{
                .{ .integer = 1 },
                .{ .map = kvs(&[_]Value.KV{
                    .{ .key = .{ .string = "foreground" }, .value = .{ .integer = 0xff0000 } },
                    .{ .key = .{ .string = "background" }, .value = .{ .integer = 0x111111 } },
                }) },
                .nil,
                .{ .array = values(&[_]Value{
                    .{ .map = kvs(&[_]Value.KV{
                        .{ .key = .{ .string = "ui_name" }, .value = .{ .string = "CursorLine" } },
                    }) },
                }) },
            }) },
        }) },
    };
    try state.handleRedraw(&hl_events);

    const line_events = [_]Value{
        .{ .array = values(&[_]Value{
            .{ .string = "grid_line" },
            .{ .array = values(&[_]Value{
                .{ .integer = 2 },
                .{ .integer = 0 },
                .{ .integer = 0 },
                .{ .array = values(&[_]Value{
                    .{ .array = values(&[_]Value{ .{ .string = "A" }, .{ .integer = 1 }, .{ .integer = 1 } }) },
                    .{ .array = values(&[_]Value{ .{ .string = "B" }, .{ .integer = 1 }, .{ .integer = 0 } }) },
                    .{ .array = values(&[_]Value{ .{ .string = "C" }, .{ .integer = 1 } }) },
                }) },
            }) },
            .{ .array = values(&[_]Value{
                .{ .integer = 3 },
                .{ .integer = 1 },
                .{ .integer = 0 },
                .{ .array = values(&[_]Value{
                    .{ .array = values(&[_]Value{ .{ .string = "D" }, .{ .integer = 1 }, .{ .integer = 2 } }) },
                }) },
            }) },
        }) },
    };
    try state.handleRedraw(&line_events);

    const live_grid = state.get(2).?;
    try std.testing.expectEqualStrings("A", live_grid.cells[0].char[0..live_grid.cells[0].len]);

    const lifecycle_events = [_]Value{
        .{ .array = values(&[_]Value{
            .{ .string = "grid_cursor_goto" },
            .{ .array = values(&[_]Value{ .{ .integer = 2 }, .{ .integer = 0 }, .{ .integer = 2 } }) },
        }) },
        .{ .array = values(&[_]Value{
            .{ .string = "grid_scroll" },
            .{ .array = values(&[_]Value{
                .{ .integer = 2 },
                .{ .integer = 0 },
                .{ .integer = 3 },
                .{ .integer = 0 },
                .{ .integer = 4 },
                .{ .integer = 1 },
                .{ .integer = 0 },
            }) },
        }) },
        .{ .array = values(&[_]Value{
            .{ .string = "win_pos" },
            .{ .array = values(&[_]Value{ .{ .integer = 2 }, .{ .integer = 0 }, .{ .integer = 1 }, .{ .integer = 2 } }) },
        }) },
        .{ .array = values(&[_]Value{
            .{ .string = "win_float_pos" },
            .{ .array = values(&[_]Value{
                .{ .integer = 3 }, .{ .integer = 0 }, .{ .integer = 0 }, .{ .integer = 0 }, .{ .integer = 0 },
                .{ .integer = 0 }, .{ .integer = 0 }, .{ .integer = 0 }, .{ .integer = 0 }, .{ .integer = 2 },
                .{ .integer = 1 },
            }) },
        }) },
        .{ .array = values(&[_]Value{
            .{ .string = "win_hide" },
            .{ .array = values(&[_]Value{.{ .integer = 3 }}) },
        }) },
        .{ .array = values(&[_]Value{
            .{ .string = "win_close" },
            .{ .array = values(&[_]Value{.{ .integer = 3 }}) },
        }) },
        .{ .array = values(&[_]Value{
            .{ .string = "grid_destroy" },
            .{ .array = values(&[_]Value{.{ .integer = 2 }}) },
        }) },
    };
    try state.handleRedraw(&lifecycle_events);
    try std.testing.expectEqual(@as(i64, 2), state.cursor_grid);
    const cursor_pos = state.cursorScreenPos();
    try std.testing.expectEqual(@as(i32, 2), cursor_pos.x);
    try std.testing.expectEqual(@as(i32, 0), cursor_pos.y);
    try std.testing.expect(state.get(3) == null);
    try std.testing.expect(state.get(2) == null);
}

test "ui protocol preserves width after scrolling and keeps explicit zero repeat intact" {
    var state = UiState.init(std.testing.allocator);
    defer state.deinit();

    const events = [_]Value{
        .{ .array = values(&[_]Value{
            .{ .string = "grid_resize" },
            .{ .array = values(&[_]Value{ .{ .integer = 1 }, .{ .integer = 5 }, .{ .integer = 4 } }) },
        }) },
        .{ .array = values(&[_]Value{
            .{ .string = "grid_line" },
            .{ .array = values(&[_]Value{
                .{ .integer = 1 },
                .{ .integer = 0 },
                .{ .integer = 0 },
                .{ .array = values(&[_]Value{
                    .{ .array = values(&[_]Value{.{ .string = "1" }}) },
                    .{ .array = values(&[_]Value{ .{ .string = "2" }, .{ .integer = 1 }, .{ .integer = 0 } }) },
                    .{ .array = values(&[_]Value{.{ .string = "3" }}) },
                    .{ .array = values(&[_]Value{.{ .string = "4" }}) },
                    .{ .array = values(&[_]Value{.{ .string = "5" }}) },
                }) },
            }) },
        }) },
    };
    try state.handleRedraw(&events);

    try std.testing.expectEqualStrings("1", state.grid.cells[0].char[0..state.grid.cells[0].len]);
    try std.testing.expectEqualStrings("3", state.grid.cells[1].char[0..state.grid.cells[1].len]);
    try std.testing.expectEqualStrings("4", state.grid.cells[2].char[0..state.grid.cells[2].len]);
    try std.testing.expectEqualStrings("5", state.grid.cells[3].char[0..state.grid.cells[3].len]);
}
