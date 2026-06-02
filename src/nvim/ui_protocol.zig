const std = @import("std");
const msgpack = @import("msgpack.zig");
const Value = msgpack.Value;
const Color = @import("../tui/renderer.zig").Color;
const Cell = @import("../tui/renderer.zig").Cell;

pub const Highlight = struct {
    fg: Color = .none,
    bg: Color = .none,
    bold: bool = false,
    italic: bool = false,
};

pub const NvimGrid = struct {
    width: u16 = 0,
    height: u16 = 0,
    cells: []Cell = &[_]Cell{},
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) NvimGrid {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *NvimGrid) void {
        self.allocator.free(self.cells);
    }

    pub fn resize(self: *NvimGrid, new_w: u16, new_h: u16) !void {
        const size = @as(usize, new_w) * @as(usize, new_h);
        const new_cells = try self.allocator.alloc(Cell, size);
        @memset(new_cells, Cell{ .char = [_]u8{ ' ', 0, 0, 0 }, .len = 1, .fg = .none, .bg = .none });

        // Copy old contents
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

    pub fn clear(self: *NvimGrid) void {
        @memset(self.cells, Cell{ .char = [_]u8{ ' ', 0, 0, 0 }, .len = 1, .fg = .none, .bg = .none });
    }
};

pub const UiState = struct {
    grid: NvimGrid,
    highlights: std.AutoHashMap(i64, Highlight),
    default_fg: Color = .none,
    default_bg: Color = .none,
    cursor_x: u16 = 0,
    cursor_y: u16 = 0,
    allocator: std.mem.Allocator,
    current_buf_path: ?[]const u8 = null,
    buf_path_changed: bool = false,
    telescope_rects: [2]?@import("../tui/layout.zig").Rect = .{ null, null },
    toggle_zen_requested: bool = false,
    toggle_ide_requested: bool = false,
    theme_changed: bool = false,

    pub fn init(allocator: std.mem.Allocator) UiState {
        return .{
            .grid = NvimGrid.init(allocator),
            .highlights = std.AutoHashMap(i64, Highlight).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *UiState) void {
        self.grid.deinit();
        self.highlights.deinit();
        if (self.current_buf_path) |p| self.allocator.free(p);
    }

    pub fn handleRedraw(self: *UiState, events: []const Value) !void {
        for (events) |ev| {
            if (ev != .array or ev.array.len < 2) continue;
            const name = ev.array[0].string;
            const args = ev.array[1..];

            if (std.mem.eql(u8, name, "default_colors_set")) {
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
            } else if (std.mem.eql(u8, name, "hl_attr_define")) {
                for (args) |arg| {
                    if (arg != .array or arg.array.len < 2) continue;
                    const id = arg.array[0].integer;
                    const rgb_attrs = arg.array[1];
                    
                    var hl = Highlight{
                        .fg = .none,
                        .bg = .none,
                    };

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
                            }
                        }
                    }

                    try self.highlights.put(id, hl);
                }
            } else if (std.mem.eql(u8, name, "grid_resize")) {
                for (args) |arg| {
                    if (arg != .array or arg.array.len < 3) continue;
                    const grid_id = arg.array[0].integer;
                    if (grid_id == 1) {
                        const w = @as(u16, @intCast(arg.array[1].integer));
                        const h = @as(u16, @intCast(arg.array[2].integer));
                        try self.grid.resize(w, h);
                    }
                }
            } else if (std.mem.eql(u8, name, "grid_clear")) {
                for (args) |arg| {
                    if (arg != .array or arg.array.len < 1) continue;
                    const grid_id = arg.array[0].integer;
                    if (grid_id == 1) {
                        self.grid.clear();
                    }
                }
            } else if (std.mem.eql(u8, name, "grid_cursor_goto")) {
                for (args) |arg| {
                    if (arg != .array or arg.array.len < 3) continue;
                    const grid_id = arg.array[0].integer;
                    if (grid_id == 1) {
                        self.cursor_y = @as(u16, @intCast(arg.array[1].integer));
                        self.cursor_x = @as(u16, @intCast(arg.array[2].integer));
                    }
                }
            } else if (std.mem.eql(u8, name, "grid_scroll")) {
                for (args) |arg| {
                    if (arg != .array or arg.array.len < 7) continue;
                    const grid_id = arg.array[0].integer;
                    if (grid_id != 1) continue;
                    const top: u16 = @as(u16, @intCast(@max(0, arg.array[1].integer)));
                    const bot: u16 = @as(u16, @intCast(@max(0, arg.array[2].integer)));
                    const left: u16 = @as(u16, @intCast(@max(0, arg.array[3].integer)));
                    const right: u16 = @as(u16, @intCast(@max(0, arg.array[4].integer)));
                    const rows: i64 = arg.array[5].integer;
                    
                    if (top >= self.grid.height or bot > self.grid.height or left >= self.grid.width or right > self.grid.width or top >= bot or left >= right) {
                        continue;
                    }
                    // const cols = arg.array[6].integer; // Always 0 in current Nvim

                    if (rows > 0) {
                        // Scroll up: move rows from [top+rows, bot) to [top, bot-rows)
                        var y = top;
                        const ur = @as(u16, @intCast(rows));
                        if (bot > ur) {
                            while (y < bot - ur) : (y += 1) {
                                const src_y = y + ur;
                                for (left..right) |x| {
                                    self.grid.cells[@as(usize, y) * @as(usize, self.grid.width) + x] = self.grid.cells[@as(usize, src_y) * @as(usize, self.grid.width) + x];
                                }
                            }
                        }
                    } else if (rows < 0) {
                        // Scroll down: move rows from [top, bot+rows) to [top-rows, bot)
                        const abs_rows = @as(u16, @intCast(-rows));
                        if (bot > 0) {
                            var y = bot - 1;
                            while (y >= top + abs_rows) : (y -= 1) {
                                const src_y = y - abs_rows;
                                for (left..right) |x| {
                                    self.grid.cells[@as(usize, y) * @as(usize, self.grid.width) + x] = self.grid.cells[@as(usize, src_y) * @as(usize, self.grid.width) + x];
                                }
                            }
                        }
                    }
                }
            } else if (std.mem.eql(u8, name, "grid_line")) {
                for (args) |arg| {
                    if (arg != .array or arg.array.len < 4) continue;
                    const grid_id = arg.array[0].integer;
                    if (grid_id != 1) continue;
                    const row = @as(u16, @intCast(arg.array[1].integer));
                    var col = @as(u16, @intCast(arg.array[2].integer));
                    const cells = arg.array[3];

                    if (cells != .array) continue;

                    var current_hl_id: i64 = 0;

                    for (cells.array) |c| {
                        if (c != .array or c.array.len < 1) continue;
                        const text = if (c.array[0] == .string) c.array[0].string else " ";
                        if (c.array.len >= 2) {
                            current_hl_id = c.array[1].integer;
                        }
                        const repeat_i = if (c.array.len >= 3) c.array[2].integer else 1;
                        const repeat: usize = if (repeat_i > 0) @as(usize, @intCast(repeat_i)) else 1;

                        const hl = self.highlights.get(current_hl_id) orelse Highlight{
                            .fg = .none,
                            .bg = .none,
                        };

                        var rep: usize = 0;
                        while (rep < repeat) : (rep += 1) {
                            if (row < self.grid.height and col < self.grid.width) {
                                var cell = Cell{
                                    .fg = hl.fg,
                                    .bg = hl.bg,
                                    .bold = hl.bold,
                                    .italic = hl.italic,
                                };
                                cell.setChar(text);
                                self.grid.cells[@as(usize, row) * @as(usize, self.grid.width) + col] = cell;
                            }
                            col += 1;
                        }
                    }
                }
            }
        }
    }
};
