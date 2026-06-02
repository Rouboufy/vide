const std = @import("std");

pub const Color = union(enum) {
    none,
    index: u8,
    rgb: struct { r: u8, g: u8, b: u8 },
};

pub const Cell = struct {
    char: [4]u8 = [_]u8{ ' ', 0, 0, 0 },
    len: u8 = 1,
    fg: Color = .none,
    bg: Color = .none,
    bold: bool = false,
    italic: bool = false,

    pub fn setChar(self: *Cell, slice: []const u8) void {
        const copy_len = @min(slice.len, 4);
        @memcpy(self.char[0..copy_len], slice[0..copy_len]);
        self.len = @as(u8, @intCast(copy_len));
    }
};

pub const Renderer = struct {
    buf: []Cell,
    prev: []Cell,
    width: u16,
    height: u16,
    writer: *std.Io.Writer,

    pub fn init(allocator: std.mem.Allocator, width: u16, height: u16, writer: *std.Io.Writer) !Renderer {
        const size = @as(usize, width) * @as(usize, height);
        const buf = try allocator.alloc(Cell, size);
        const prev = try allocator.alloc(Cell, size);

        const empty_cell = Cell{
            .char = [_]u8{ ' ', 0, 0, 0 },
            .len = 1,
            .fg = .none,
            .bg = .none,
        };
        @memset(buf, empty_cell);
        @memset(prev, empty_cell);

        return Renderer{
            .buf = buf,
            .prev = prev,
            .width = width,
            .height = height,
            .writer = writer,
        };
    }

    pub fn deinit(self: *Renderer, allocator: std.mem.Allocator) void {
        allocator.free(self.buf);
        allocator.free(self.prev);
    }

    pub fn setCell(self: *Renderer, x: u16, y: u16, cell: Cell) void {
        if (x >= self.width or y >= self.height) return;
        self.buf[@as(usize, y) * @as(usize, self.width) + x] = cell;
    }

    pub fn drawRect(self: *Renderer, rect: @import("layout.zig").Rect, char: []const u8, fg: Color, bg: Color) void {
        var y: u16 = 0;
        while (y < rect.h) : (y += 1) {
            var x: u16 = 0;
            while (x < rect.w) : (x += 1) {
                var cell = Cell{
                    .fg = fg,
                    .bg = bg,
                };
                cell.setChar(char);
                self.setCell(rect.x + x, rect.y + y, cell);
            }
        }
    }

    pub fn drawText(self: *Renderer, x: u16, y: u16, text: []const u8, fg: Color, bg: Color, bold: bool, italic: bool) void {
        var col = x;
        var i: usize = 0;
        while (i < text.len) {
            const len = std.unicode.utf8ByteSequenceLength(text[i]) catch 1;
            const char = text[i..@min(text.len, i + len)];
            var cell = Cell{
                .fg = fg,
                .bg = bg,
                .bold = bold,
                .italic = italic,
            };
            cell.setChar(char);
            self.setCell(col, y, cell);
            col += 1;
            i += len;
        }
    }

    pub fn resize(self: *Renderer, allocator: std.mem.Allocator, new_width: u16, new_height: u16) !void {
        const new_size = @as(usize, new_width) * @as(usize, new_height);
        const new_buf = try allocator.alloc(Cell, new_size);
        const new_prev = try allocator.alloc(Cell, new_size);

        const empty_cell = Cell{
            .char = [_]u8{ ' ', 0, 0, 0 },
            .len = 1,
            .fg = .none,
            .bg = .none,
        };
        @memset(new_buf, empty_cell);
        @memset(new_prev, empty_cell);

        // Copy overlap
        const min_h = @min(self.height, new_height);
        const min_w = @min(self.width, new_width);
        for (0..min_h) |y| {
            for (0..min_w) |x| {
                new_buf[y * new_width + x] = self.buf[y * self.width + x];
            }
        }

        allocator.free(self.buf);
        allocator.free(self.prev);

        self.buf = new_buf;
        self.prev = new_prev;
        self.width = new_width;
        self.height = new_height;
    }

    pub fn flush(self: *Renderer) !void {
        var cur_fg: Color = .none;
        var cur_bg: Color = .none;
        var cur_bold: bool = false;
        var cur_italic: bool = false;

        // Reset terminal attributes initially
        try self.writer.writeAll("\x1b[0m");

        for (0..self.height) |y| {
            for (0..self.width) |x| {
                const idx = y * self.width + x;
                const cell = self.buf[idx];
                const prev_cell = self.prev[idx];

                if (std.meta.eql(cell, prev_cell)) continue;

                // Move cursor to 1-indexed console coordinates
                try self.writer.print("\x1b[{d};{d}H", .{ y + 1, x + 1 });

                var style_reset = false;

                // Handle bold/italic modifications
                if (cell.bold != cur_bold or cell.italic != cur_italic) {
                    if ((cur_bold and !cell.bold) or (cur_italic and !cell.italic)) {
                        // Reset all attributes if we need to remove bold or italic
                        try self.writer.writeAll("\x1b[0m");
                        cur_fg = .none;
                        cur_bg = .none;
                        cur_bold = false;
                        cur_italic = false;
                        style_reset = true;
                    }

                    if (cell.bold and !cur_bold) {
                        try self.writer.writeAll("\x1b[1m");
                        cur_bold = true;
                    }
                    if (cell.italic and !cur_italic) {
                        try self.writer.writeAll("\x1b[3m");
                        cur_italic = true;
                    }
                }

                // Handle foreground color changes
                if (!std.meta.eql(cell.fg, cur_fg) or style_reset) {
                    cur_fg = cell.fg;
                    switch (cur_fg) {
                        .none => try self.writer.writeAll("\x1b[39m"),
                        .index => |i| try self.writer.print("\x1b[38;5;{d}m", .{i}),
                        .rgb => |rgb| try self.writer.print("\x1b[38;2;{d};{d};{d}m", .{ rgb.r, rgb.g, rgb.b }),
                    }
                }

                // Handle background color changes
                if (!std.meta.eql(cell.bg, cur_bg) or style_reset) {
                    cur_bg = cell.bg;
                    switch (cur_bg) {
                        .none => try self.writer.writeAll("\x1b[49m"),
                        .index => |i| try self.writer.print("\x1b[48;5;{d}m", .{i}),
                        .rgb => |rgb| try self.writer.print("\x1b[48;2;{d};{d};{d}m", .{ rgb.r, rgb.g, rgb.b }),
                    }
                }

                try self.writer.writeAll(cell.char[0..cell.len]);
            }
        }

        // Reset attributes on finish
        try self.writer.writeAll("\x1b[0m");
        @memcpy(self.prev, self.buf);
    }
};
