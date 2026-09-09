const std = @import("std");
const msgpack = @import("msgpack.zig");
const Value = msgpack.Value;
const Color = @import("../tui/renderer.zig").Color;
const Cell = @import("../tui/renderer.zig").Cell;

fn blankCell() Cell {
    var cell = Cell{};
    cell.setChar(" ");
    return cell;
}

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
        @memset(new_cells, blankCell());
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
        @memset(self.cells, blankCell());
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
    editor_mode: u8 = 'n',
    allocator: std.mem.Allocator,
    telescope_rects: [2]?@import("../tui/layout.zig").Rect = .{ null, null },
    native_picker_chrome: bool = false,
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
            // Neovim 0.12 appends the resolved screen position to this event.
            // Older versions (including the 0.11 runtime bundled in the
            // AppImage) stop after zindex, so resolve their anchor-relative
            // position here instead of leaving every float at (0, 0).
            if (arg.array.len >= 11 and
                arg.array[9] == .integer and
                arg.array[10] == .integer)
            {
                g.row = @as(i32, @intCast(arg.array[9].integer));
                g.col = @as(i32, @intCast(arg.array[10].integer));
            } else if (arg.array.len >= 6 and
                arg.array[2] == .string and
                arg.array[3] == .integer and
                arg.array[4] == .integer and
                arg.array[5] == .integer)
            {
                var row = @as(i32, @intCast(arg.array[4].integer));
                var col = @as(i32, @intCast(arg.array[5].integer));
                const anchor_grid = arg.array[3].integer;
                if (anchor_grid != 1) {
                    if (self.get(anchor_grid)) |anchor| {
                        row += anchor.row;
                        col += anchor.col;
                    }
                }

                const anchor = arg.array[2].string;
                if (std.mem.indexOfScalar(u8, anchor, 'S') != null) {
                    row -= @as(i32, @intCast(g.height));
                }
                if (std.mem.indexOfScalar(u8, anchor, 'E') != null) {
                    col -= @as(i32, @intCast(g.width));
                }
                g.row = row;
                g.col = col;
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
            const cols: i64 = arg.array[6].integer;
            if (top >= target.height or bot > target.height or
                left >= target.width or right > target.width or
                top >= bot or left >= right) continue;
            const region_h = bot - top;
            const region_w = right - left;
            var yi: u16 = 0;
            while (yi < region_h) : (yi += 1) {
                const y = if (rows >= 0) top + yi else bot - 1 - yi;
                var xi: u16 = 0;
                while (xi < region_w) : (xi += 1) {
                    const x = if (cols >= 0) left + xi else right - 1 - xi;
                    const src_y = @as(i128, y) + @as(i128, rows);
                    const src_x = @as(i128, x) + @as(i128, cols);
                    const dst_index = @as(usize, y) * @as(usize, target.width) + x;
                    if (src_y >= @as(i128, top) and src_y < @as(i128, bot) and
                        src_x >= @as(i128, left) and src_x < @as(i128, right))
                    {
                        const sy: usize = @intCast(src_y);
                        const sx: usize = @intCast(src_x);
                        target.cells[dst_index] = target.cells[sy * @as(usize, target.width) + sx];
                    } else {
                        target.cells[dst_index] = blankCell();
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
                        if (text.len == 0) {
                            @memset(&cell.char, 0);
                            cell.len = 0;
                            cell.continuation = true;
                        } else {
                            cell.setChar(text);
                        }
                        target.cells[@as(usize, row) * @as(usize, target.width) + col] = cell;
                    }
                    col += 1;
                }
            }
        }
    }

    pub const RedrawDamage = struct {
        grid: bool = false,
        cursor: bool = false,
        lifecycle: bool = false,
        composition_uncertain: bool = false,
    };

    /// Applies a complete redraw batch and reports conservative grid-space
    /// damage. The caller maps it to a screen region only after all positions
    /// and z-order changes in the batch have landed.
    pub fn handleRedraw(self: *UiState, events: []const Value) !RedrawDamage {
        var damage = RedrawDamage{};
        for (events) |ev| {
            if (ev != .array or ev.array.len < 2) continue;
            const name = ev.array[0].string;
            const args = ev.array[1..];

            if (std.mem.eql(u8, name, "mode_change")) {
                if (args.len > 0 and args[0] == .array and args[0].array.len > 0 and args[0].array[0] == .string and args[0].array[0].string.len > 0) {
                    self.editor_mode = args[0].array[0].string[0];
                }
            } else if (std.mem.eql(u8, name, "default_colors_set")) {
                self.handleDefaultColorsSet(args);
                damage.grid = true;
            } else if (std.mem.eql(u8, name, "hl_attr_define")) {
                try self.handleHlAttrDefine(args);
                damage.grid = true;
            } else if (std.mem.eql(u8, name, "grid_resize")) {
                try self.handleGridResize(args);
                damage.lifecycle = true;
                damage.composition_uncertain = true;
            } else if (std.mem.eql(u8, name, "grid_clear")) {
                self.handleGridClear(args);
                damage.grid = true;
            } else if (std.mem.eql(u8, name, "grid_destroy")) {
                self.handleGridDestroy(args);
                damage.lifecycle = true;
                damage.composition_uncertain = true;
            } else if (std.mem.eql(u8, name, "win_pos")) {
                try self.handleWinPos(args);
                damage.lifecycle = true;
                damage.composition_uncertain = true;
            } else if (std.mem.eql(u8, name, "msg_set_pos")) {
                try self.handleMsgSetPos(args);
                damage.lifecycle = true;
                damage.composition_uncertain = true;
            } else if (std.mem.eql(u8, name, "win_float_pos")) {
                try self.handleWinFloatPos(args);
                damage.lifecycle = true;
                damage.composition_uncertain = true;
            } else if (std.mem.eql(u8, name, "win_hide")) {
                self.handleWinHide(args);
                damage.lifecycle = true;
                damage.composition_uncertain = true;
            } else if (std.mem.eql(u8, name, "win_close")) {
                self.handleWinClose(args);
                damage.lifecycle = true;
                damage.composition_uncertain = true;
            } else if (std.mem.eql(u8, name, "grid_cursor_goto")) {
                self.handleGridCursorGoto(args);
                damage.cursor = true;
            } else if (std.mem.eql(u8, name, "grid_scroll")) {
                self.handleGridScroll(args);
                damage.grid = true;
                damage.composition_uncertain = true;
            } else if (std.mem.eql(u8, name, "grid_line")) {
                try self.handleGridLine(args);
                damage.grid = true;
            }
        }
        return damage;
    }
};

test "grid cell repeat distinguishes omitted and explicit zero" {
    try std.testing.expectEqual(@as(usize, 1), gridCellRepeat(false, 0));
    try std.testing.expectEqual(@as(usize, 0), gridCellRepeat(true, 0));
    try std.testing.expectEqual(@as(usize, 3), gridCellRepeat(true, 3));
}

test "redraw damage separates cursor updates from grid lifecycle" {
    var state = UiState.init(std.testing.allocator);
    defer state.deinit();

    const cursor_events = [_]Value{
        .{ .array = values(&[_]Value{
            .{ .string = "grid_cursor_goto" },
            .{ .array = values(&[_]Value{ .{ .integer = 1 }, .{ .integer = 2 }, .{ .integer = 3 } }) },
        }) },
    };
    const cursor_damage = try state.handleRedraw(&cursor_events);
    try std.testing.expect(cursor_damage.cursor);
    try std.testing.expect(!cursor_damage.grid);
    try std.testing.expect(!cursor_damage.lifecycle);

    const lifecycle_events = [_]Value{
        .{ .array = values(&[_]Value{
            .{ .string = "grid_resize" },
            .{ .array = values(&[_]Value{ .{ .integer = 1 }, .{ .integer = 80 }, .{ .integer = 24 } }) },
        }) },
    };
    const lifecycle_damage = try state.handleRedraw(&lifecycle_events);
    try std.testing.expect(lifecycle_damage.lifecycle);
    try std.testing.expect(lifecycle_damage.composition_uncertain);
    try std.testing.expect(!lifecycle_damage.cursor);
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
    _ = try state.handleRedraw(&resize_events);

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
    _ = try state.handleRedraw(&hl_events);

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
    _ = try state.handleRedraw(&line_events);

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
    _ = try state.handleRedraw(&lifecycle_events);
    try std.testing.expectEqual(@as(i64, 2), state.cursor_grid);
    const cursor_pos = state.cursorScreenPos();
    try std.testing.expectEqual(@as(i32, 2), cursor_pos.x);
    try std.testing.expectEqual(@as(i32, 0), cursor_pos.y);
    try std.testing.expect(state.get(3) == null);
    try std.testing.expect(state.get(2) == null);
}

test "ui protocol resolves legacy float positions without absolute coordinates" {
    var state = UiState.init(std.testing.allocator);
    defer state.deinit();

    const events = [_]Value{
        .{ .array = values(&[_]Value{
            .{ .string = "grid_resize" },
            .{ .array = values(&[_]Value{ .{ .integer = 2 }, .{ .integer = 40 }, .{ .integer = 12 } }) },
            .{ .array = values(&[_]Value{ .{ .integer = 3 }, .{ .integer = 20 }, .{ .integer = 6 } }) },
        }) },
        .{ .array = values(&[_]Value{
            .{ .string = "win_pos" },
            .{ .array = values(&[_]Value{ .{ .integer = 2 }, .{ .integer = 20 }, .{ .integer = 4 }, .{ .integer = 7 } }) },
        }) },
        // Neovim 0.11: [grid, win, anchor, anchor_grid, anchor_row,
        //               anchor_col, focusable, zindex]
        .{ .array = values(&[_]Value{
            .{ .string = "win_float_pos" },
            .{ .array = values(&[_]Value{
                .{ .integer = 3 }, .{ .integer = 30 }, .{ .string = "NW" }, .{ .integer = 1 },
                .{ .integer = 8 }, .{ .integer = 13 }, .{ .bool = true },   .{ .integer = 50 },
            }) },
        }) },
    };
    _ = try state.handleRedraw(&events);

    const float = state.get(3).?;
    try std.testing.expectEqual(@as(i32, 8), float.row);
    try std.testing.expectEqual(@as(i32, 13), float.col);

    const anchored_events = [_]Value{
        .{ .array = values(&[_]Value{
            .{ .string = "win_float_pos" },
            .{ .array = values(&[_]Value{
                .{ .integer = 3 },  .{ .integer = 30 }, .{ .string = "SE" }, .{ .integer = 2 },
                .{ .integer = 10 }, .{ .integer = 30 }, .{ .bool = true },   .{ .integer = 50 },
            }) },
        }) },
    };
    _ = try state.handleRedraw(&anchored_events);
    try std.testing.expectEqual(@as(i32, 8), float.row);
    try std.testing.expectEqual(@as(i32, 17), float.col);
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
    _ = try state.handleRedraw(&events);

    try std.testing.expectEqualStrings("1", state.grid.cells[0].char[0..state.grid.cells[0].len]);
    try std.testing.expectEqualStrings("3", state.grid.cells[1].char[0..state.grid.cells[1].len]);
    try std.testing.expectEqualStrings("4", state.grid.cells[2].char[0..state.grid.cells[2].len]);
    try std.testing.expectEqualStrings("5", state.grid.cells[3].char[0..state.grid.cells[3].len]);
}

test "grid scroll translates both axes and blanks exposed cells" {
    var state = UiState.init(std.testing.allocator);
    defer state.deinit();
    try state.grid.resize(4, 3);
    for (state.grid.cells, 0..) |*cell, i| cell.setChar(&[_]u8{@as(u8, @intCast('A' + i))});

    const diagonal = [_]Value{.{ .array = values(&[_]Value{
        .{ .integer = 1 }, .{ .integer = 0 }, .{ .integer = 3 }, .{ .integer = 0 },
        .{ .integer = 4 }, .{ .integer = 1 }, .{ .integer = 1 },
    }) }};
    state.handleGridScroll(&diagonal);

    try std.testing.expectEqual(@as(u8, 'F'), state.grid.cells[0].char[0]);
    try std.testing.expectEqual(@as(u8, 'K'), state.grid.cells[5].char[0]);
    for ([_]usize{ 3, 7, 8, 9, 10, 11 }) |index| {
        const cell = state.grid.cells[index];
        try std.testing.expectEqual(@as(u8, ' '), cell.char[0]);
        try std.testing.expectEqual(Color.none, cell.fg);
        try std.testing.expectEqual(Color.none, cell.bg);
        try std.testing.expect(!cell.continuation);
    }
}

test "grid scroll supports negative and oversized displacement in a partial region" {
    var state = UiState.init(std.testing.allocator);
    defer state.deinit();
    try state.grid.resize(4, 3);
    for (state.grid.cells, 0..) |*cell, i| cell.setChar(&[_]u8{@as(u8, @intCast('A' + i))});

    const negative = [_]Value{.{ .array = values(&[_]Value{
        .{ .integer = 1 }, .{ .integer = 0 },  .{ .integer = 3 },  .{ .integer = 0 },
        .{ .integer = 4 }, .{ .integer = -1 }, .{ .integer = -1 },
    }) }};
    state.handleGridScroll(&negative);
    try std.testing.expectEqual(@as(u8, 'A'), state.grid.cells[5].char[0]);
    try std.testing.expectEqual(@as(u8, ' '), state.grid.cells[0].char[0]);
    try std.testing.expectEqual(@as(u8, ' '), state.grid.cells[4].char[0]);

    for (state.grid.cells, 0..) |*cell, i| cell.setChar(&[_]u8{@as(u8, @intCast('A' + i))});
    const oversized_partial = [_]Value{.{ .array = values(&[_]Value{
        .{ .integer = 1 }, .{ .integer = 1 },                    .{ .integer = 3 },                    .{ .integer = 1 },
        .{ .integer = 3 }, .{ .integer = std.math.maxInt(i64) }, .{ .integer = std.math.minInt(i64) },
    }) }};
    state.handleGridScroll(&oversized_partial);
    try std.testing.expectEqual(@as(u8, ' '), state.grid.cells[5].char[0]);
    try std.testing.expectEqual(@as(u8, ' '), state.grid.cells[6].char[0]);
    try std.testing.expectEqual(@as(u8, 'D'), state.grid.cells[3].char[0]);
    try std.testing.expectEqual(@as(u8, 'L'), state.grid.cells[11].char[0]);
}

test "deterministic msgpack redraw replay produces canonical styled unicode cell grid" {
    // This is a decoded Neovim redraw batch first serialized through msgpack,
    // ensuring the replay fixture exercises the wire representation as well as
    // the protocol state machine.
    const fixture = Value{ .array = values(&[_]Value{
        .{ .array = values(&[_]Value{
            .{ .string = "grid_resize" },
            .{ .array = values(&[_]Value{ .{ .integer = 1 }, .{ .integer = 6 }, .{ .integer = 3 } }) },
            .{ .array = values(&[_]Value{ .{ .integer = 2 }, .{ .integer = 2 }, .{ .integer = 2 } }) },
            .{ .array = values(&[_]Value{ .{ .integer = 3 }, .{ .integer = 2 }, .{ .integer = 1 } }) },
        }) },
        .{ .array = values(&[_]Value{
            .{ .string = "hl_attr_define" },
            .{ .array = values(&[_]Value{
                .{ .integer = 7 },
                .{ .map = kvs(&[_]Value.KV{
                    .{ .key = .{ .string = "foreground" }, .value = .{ .integer = 0x112233 } },
                    .{ .key = .{ .string = "background" }, .value = .{ .integer = 0x445566 } },
                    .{ .key = .{ .string = "bold" }, .value = .{ .bool = true } },
                    .{ .key = .{ .string = "italic" }, .value = .{ .bool = true } },
                    .{ .key = .{ .string = "reverse" }, .value = .{ .bool = true } },
                }) },
                .nil,
                .{ .array = values(&[_]Value{}) },
            }) },
        }) },
        .{ .array = values(&[_]Value{
            .{ .string = "grid_line" },
            .{ .array = values(&[_]Value{
                .{ .integer = 1 }, .{ .integer = 0 }, .{ .integer = 0 },
                .{ .array = values(&[_]Value{
                    .{ .array = values(&[_]Value{ .{ .string = "A" }, .{ .integer = 7 } }) },
                    .{ .array = values(&[_]Value{.{ .string = "界" }}) },
                    .{ .array = values(&[_]Value{.{ .string = "" }}) },
                    .{ .array = values(&[_]Value{.{ .string = "🚀" }}) },
                    .{ .array = values(&[_]Value{.{ .string = "" }}) },
                    .{ .array = values(&[_]Value{.{ .string = "Z" }}) },
                }) },
            }) },
            .{ .array = values(&[_]Value{
                .{ .integer = 1 }, .{ .integer = 1 }, .{ .integer = 0 },
                .{ .array = values(&[_]Value{
                    .{ .array = values(&[_]Value{ .{ .string = "á" }, .{ .integer = 7 } }) },
                    .{ .array = values(&[_]Value{ .{ .string = "s" }, .{ .integer = 0 }, .{ .integer = 5 } }) },
                }) },
            }) },
        }) },
        .{ .array = values(&[_]Value{ .{ .string = "grid_cursor_goto" }, .{ .array = values(&[_]Value{ .{ .integer = 1 }, .{ .integer = 1 }, .{ .integer = 0 } }) } }) },
        .{ .array = values(&[_]Value{ .{ .string = "win_pos" }, .{ .array = values(&[_]Value{ .{ .integer = 2 }, .{ .integer = 20 }, .{ .integer = 1 }, .{ .integer = 2 } }) } }) },
        .{ .array = values(&[_]Value{ .{ .string = "win_float_pos" }, .{ .array = values(&[_]Value{
            .{ .integer = 3 }, .{ .integer = 30 }, .{ .string = "NW" }, .{ .integer = 1 }, .{ .integer = 0 }, .{ .integer = 0 }, .{ .bool = true }, .{ .integer = 50 },
        }) } }) },
        .{ .array = values(&[_]Value{ .{ .string = "win_hide" }, .{ .array = values(&[_]Value{.{ .integer = 3 }}) } }) },
        .{ .array = values(&[_]Value{ .{ .string = "grid_clear" }, .{ .array = values(&[_]Value{.{ .integer = 2 }}) } }) },
        .{ .array = values(&[_]Value{ .{ .string = "grid_scroll" }, .{ .array = values(&[_]Value{
            .{ .integer = 1 }, .{ .integer = 0 }, .{ .integer = 3 }, .{ .integer = 0 }, .{ .integer = 6 }, .{ .integer = 1 }, .{ .integer = 0 },
        }) } }) },
        .{ .array = values(&[_]Value{ .{ .string = "win_close" }, .{ .array = values(&[_]Value{.{ .integer = 3 }}) } }) },
        .{ .array = values(&[_]Value{ .{ .string = "grid_destroy" }, .{ .array = values(&[_]Value{.{ .integer = 2 }}) } }) },
    }) };

    var encoded = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer encoded.deinit();
    try msgpack.encode(&encoded.writer, fixture);
    var reader = std.Io.Reader.fixed(encoded.written());
    const decoded = try msgpack.decode(&reader, std.testing.allocator);
    defer msgpack.freeValue(decoded, std.testing.allocator);

    var state = UiState.init(std.testing.allocator);
    defer state.deinit();
    _ = try state.handleRedraw(decoded.array);

    // Canonical final grid after the one-row scroll. Every cell is asserted.
    const expected = [_][]const u8{ "á", "s", "s", "s", "s", "s", " ", " ", " ", " ", " ", " ", " ", " ", " ", " ", " ", " " };
    for (state.grid.cells, expected) |cell, text| {
        try std.testing.expectEqualStrings(text, cell.char[0..cell.len]);
    }
    const styled = state.grid.cells[0];
    try std.testing.expectEqual(Color{ .rgb = .{ .r = 0x11, .g = 0x22, .b = 0x33 } }, styled.fg);
    try std.testing.expectEqual(Color{ .rgb = .{ .r = 0x44, .g = 0x55, .b = 0x66 } }, styled.bg);
    try std.testing.expect(styled.bold and styled.italic and styled.reverse);
    try std.testing.expectEqual(@as(u16, 0), state.cursor_x);
    try std.testing.expectEqual(@as(u16, 1), state.cursor_y);
    try std.testing.expect(state.get(2) == null and state.get(3) == null);

    // Verify the pre-scroll Unicode fixture separately, including explicit
    // wide-cell continuations from Neovim's empty-string cells.
    var unicode_state = UiState.init(std.testing.allocator);
    defer unicode_state.deinit();
    _ = try unicode_state.handleRedraw(decoded.array[0..3]);
    try std.testing.expectEqualStrings("A", unicode_state.grid.cells[0].char[0..unicode_state.grid.cells[0].len]);
    try std.testing.expectEqualStrings("界", unicode_state.grid.cells[1].char[0..unicode_state.grid.cells[1].len]);
    try std.testing.expect(unicode_state.grid.cells[2].continuation and unicode_state.grid.cells[2].len == 0);
    try std.testing.expectEqualStrings("🚀", unicode_state.grid.cells[3].char[0..unicode_state.grid.cells[3].len]);
    try std.testing.expect(unicode_state.grid.cells[4].continuation and unicode_state.grid.cells[4].len == 0);
    try std.testing.expectEqualStrings("Z", unicode_state.grid.cells[5].char[0..unicode_state.grid.cells[5].len]);
}
