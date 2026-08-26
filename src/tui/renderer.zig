const std = @import("std");
const metrics = @import("../metrics.zig");

pub const Color = union(enum) {
    none,
    index: u8,
    rgb: struct { r: u8, g: u8, b: u8 },
};

pub const Cell = struct {
    char: [12]u8 = [_]u8{ ' ', 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
    len: u8 = 1,
    continuation: bool = false,
    fg: Color = .none,
    bg: Color = .none,
    bold: bool = false,
    italic: bool = false,
    reverse: bool = false,

    pub fn setChar(self: *Cell, slice: []const u8) void {
        const copy_len = @min(slice.len, self.char.len);
        @memset(&self.char, 0);
        @memcpy(self.char[0..copy_len], slice[0..copy_len]);
        self.len = @as(u8, @intCast(copy_len));
        self.continuation = false;
    }

    pub fn appendBytes(self: *Cell, slice: []const u8) void {
        const available = self.char.len - self.len;
        const copy_len = @min(slice.len, available);
        @memcpy(self.char[self.len .. self.len + copy_len], slice[0..copy_len]);
        self.len += @intCast(copy_len);
    }
};

pub fn unicodeCellWidth(cp: u21) u2 {
    if (cp == 0 or cp < 0x20 or (cp >= 0x7f and cp < 0xa0)) return 0;
    if ((cp >= 0x0300 and cp <= 0x036f) or
        (cp >= 0x1ab0 and cp <= 0x1aff) or
        (cp >= 0x1dc0 and cp <= 0x1dff) or
        (cp >= 0x20d0 and cp <= 0x20ff) or
        (cp >= 0xfe00 and cp <= 0xfe0f) or
        (cp >= 0xfe20 and cp <= 0xfe2f) or
        (cp >= 0x1f3fb and cp <= 0x1f3ff)) return 0;
    if ((cp >= 0x1100 and cp <= 0x115f) or
        cp == 0x2329 or cp == 0x232a or
        (cp >= 0x2e80 and cp <= 0xa4cf and cp != 0x303f) or
        (cp >= 0xac00 and cp <= 0xd7a3) or
        (cp >= 0xf900 and cp <= 0xfaff) or
        (cp >= 0xfe10 and cp <= 0xfe19) or
        (cp >= 0xfe30 and cp <= 0xfe6f) or
        (cp >= 0xff00 and cp <= 0xff60) or
        (cp >= 0xffe0 and cp <= 0xffe6) or
        (cp >= 0x1f300 and cp <= 0x1faff) or
        (cp >= 0x20000 and cp <= 0x3fffd)) return 2;
    return 1;
}

pub fn rgbToAnsi256(r: u8, g: u8, b: u8) u8 {
    const rr: u16 = (@as(u16, r) * 5 + 127) / 255;
    const gg: u16 = (@as(u16, g) * 5 + 127) / 255;
    const bb: u16 = (@as(u16, b) * 5 + 127) / 255;
    return @intCast(16 + 36 * rr + 6 * gg + bb);
}

pub const Renderer = struct {
    const CursorPosition = struct { x: u16, y: u16 };

    buf: []Cell,
    prev: []Cell,
    width: u16,
    height: u16,
    writer: *std.Io.Writer,
    true_color: bool = true,
    force_full_redraw: bool = true,
    cursor_position: ?CursorPosition = null,

    pub fn init(allocator: std.mem.Allocator, width: u16, height: u16, writer: *std.Io.Writer) !Renderer {
        const size = @as(usize, width) * @as(usize, height);
        const buf = try allocator.alloc(Cell, size);
        const prev = try allocator.alloc(Cell, size);

        const empty_cell = Cell{
            .char = [_]u8{ ' ', 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
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

    pub fn drawCursor(self: *Renderer, x: u16, y: u16) void {
        if (x >= self.width or y >= self.height) return;
        self.cursor_position = .{ .x = x, .y = y };
        const cell = &self.buf[@as(usize, y) * @as(usize, self.width) + x];
        const old_fg = cell.fg;
        cell.fg = cell.bg;
        cell.bg = old_fg;
        if (std.meta.eql(cell.fg, cell.bg)) {
            cell.fg = .{ .rgb = .{ .r = 30, .g = 30, .b = 30 } };
            cell.bg = .{ .rgb = .{ .r = 220, .g = 220, .b = 220 } };
        }
    }

    pub fn forceFullRedraw(self: *Renderer) void {
        self.force_full_redraw = true;
    }

    fn emitStyle(self: *Renderer, cell: Cell, cur_fg: *Color, cur_bg: *Color, cur_bold: *bool, cur_italic: *bool) !void {
        var style_reset = false;
        if (cell.bold != cur_bold.* or cell.italic != cur_italic.*) {
            if ((cur_bold.* and !cell.bold) or (cur_italic.* and !cell.italic)) {
                try self.writer.writeAll("\x1b[0m");
                cur_fg.* = .none;
                cur_bg.* = .none;
                cur_bold.* = false;
                cur_italic.* = false;
                style_reset = true;
            }
            if (cell.bold and !cur_bold.*) {
                try self.writer.writeAll("\x1b[1m");
                cur_bold.* = true;
            }
            if (cell.italic and !cur_italic.*) {
                try self.writer.writeAll("\x1b[3m");
                cur_italic.* = true;
            }
        }

        if (!std.meta.eql(cell.fg, cur_fg.*) or style_reset) {
            cur_fg.* = cell.fg;
            switch (cur_fg.*) {
                .none => try self.writer.writeAll("\x1b[39m"),
                .index => |i| try self.writer.print("\x1b[38;5;{d}m", .{i}),
                .rgb => |rgb| if (self.true_color)
                    try self.writer.print("\x1b[38;2;{d};{d};{d}m", .{ rgb.r, rgb.g, rgb.b })
                else
                    try self.writer.print("\x1b[38;5;{d}m", .{rgbToAnsi256(rgb.r, rgb.g, rgb.b)}),
            }
        }
        if (!std.meta.eql(cell.bg, cur_bg.*) or style_reset) {
            cur_bg.* = cell.bg;
            switch (cur_bg.*) {
                .none => try self.writer.writeAll("\x1b[49m"),
                .index => |i| try self.writer.print("\x1b[48;5;{d}m", .{i}),
                .rgb => |rgb| if (self.true_color)
                    try self.writer.print("\x1b[48;2;{d};{d};{d}m", .{ rgb.r, rgb.g, rgb.b })
                else
                    try self.writer.print("\x1b[48;5;{d}m", .{rgbToAnsi256(rgb.r, rgb.g, rgb.b)}),
            }
        }
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
        self.drawTextClipped(x, y, self.width -| x, text, fg, bg, bold, italic);
    }

    pub fn drawTextClipped(self: *Renderer, x: u16, y: u16, max_width: u16, text: []const u8, fg: Color, bg: Color, bold: bool, italic: bool) void {
        var col = x;
        var i: usize = 0;
        while (i < text.len) {
            const len = std.unicode.utf8ByteSequenceLength(text[i]) catch 1;
            const char = text[i..@min(text.len, i + len)];
            const cp = std.unicode.utf8Decode(char) catch @as(u21, text[i]);
            const cell_width = unicodeCellWidth(cp);
            if (cell_width == 0) {
                if (col > x and col - 1 < self.width and y < self.height) {
                    const row_start = @as(usize, y) * @as(usize, self.width);
                    const previous_col = if (self.buf[row_start + col - 1].continuation and col >= 2) col - 2 else col - 1;
                    self.buf[row_start + previous_col].appendBytes(char);
                }
                i += len;
                continue;
            }
            if (col >= self.width or col - x + cell_width > max_width) break;
            var cell = Cell{
                .fg = fg,
                .bg = bg,
                .bold = bold,
                .italic = italic,
            };
            cell.setChar(char);
            self.setCell(col, y, cell);
            if (cell_width == 2 and col + 1 < self.width) {
                var continuation = Cell{ .fg = fg, .bg = bg, .bold = bold, .italic = italic, .continuation = true, .len = 0 };
                @memset(&continuation.char, 0);
                self.setCell(col + 1, y, continuation);
            }
            col +|= cell_width;
            i += len;
        }
    }

    pub fn resize(self: *Renderer, allocator: std.mem.Allocator, new_width: u16, new_height: u16) !void {
        const new_size = @as(usize, new_width) * @as(usize, new_height);
        const new_buf = try allocator.alloc(Cell, new_size);
        const new_prev = try allocator.alloc(Cell, new_size);

        const empty_cell = Cell{
            .char = [_]u8{ ' ', 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
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
        self.cursor_position = null;
    }

    pub fn flush(self: *Renderer) !void {
        var encode_timer = metrics.ScopedTimer.start(&metrics.global, &metrics.global.ansi_encoding);
        defer encode_timer.stop();
        if (metrics.global.enabled) {
            metrics.global.frame_count +|= 1;
            metrics.global.rendered_cells +|= @as(u64, self.width) * @as(u64, self.height);
        }
        var has_damage = self.force_full_redraw and self.buf.len > 0;
        if (!has_damage) {
            for (self.buf, self.prev) |cell, previous| {
                if (!std.meta.eql(cell, previous)) {
                    has_damage = true;
                    break;
                }
            }
        }
        if (!has_damage) return;

        var cur_fg: Color = .none;
        var cur_bg: Color = .none;
        var cur_bold: bool = false;
        var cur_italic: bool = false;

        // Hide cursor and reset terminal attributes initially
        try self.writer.writeAll("\x1b[?25l\x1b[0m");

        var dirty_count: u64 = 0;
        var dirty_regions: u64 = 0;
        for (0..self.height) |y| {
            var x: usize = 0;
            while (x < self.width) {
                const idx = y * self.width + x;
                if (!self.force_full_redraw and std.meta.eql(self.buf[idx], self.prev[idx])) {
                    x += 1;
                    continue;
                }

                var run_start = x;
                // A changed continuation cannot be painted independently;
                // replay its wide-cell leader so terminal width stays aligned.
                if (self.buf[idx].continuation and run_start > 0) run_start -= 1;
                var run_end = x + 1;
                while (run_end < self.width) : (run_end += 1) {
                    const next_idx = y * self.width + run_end;
                    if (!self.force_full_redraw and std.meta.eql(self.buf[next_idx], self.prev[next_idx])) break;
                }

                dirty_regions +|= 1;
                for (x..run_end) |dirty_x| {
                    const dirty_idx = y * self.width + dirty_x;
                    if (self.force_full_redraw or !std.meta.eql(self.buf[dirty_idx], self.prev[dirty_idx])) dirty_count +|= 1;
                }
                // One absolute move per changed row run. Sequential writes,
                // including style changes, then advance the terminal cursor.
                try self.writer.print("\x1b[{d};{d}H", .{ y + 1, run_start + 1 });
                for (run_start..run_end) |run_x| {
                    const cell = self.buf[y * self.width + run_x];
                    if (cell.continuation) continue;
                    try self.emitStyle(cell, &cur_fg, &cur_bg, &cur_bold, &cur_italic);
                    try self.writer.writeAll(cell.char[0..cell.len]);
                }
                x = run_end;
            }
        }

        // Reset attributes on finish
        try self.writer.writeAll("\x1b[0m");
        if (self.cursor_position) |cursor| {
            try self.writer.print("\x1b[{d};{d}H", .{ cursor.y + 1, cursor.x + 1 });
        }
        @memcpy(self.prev, self.buf);
        self.force_full_redraw = false;
        if (metrics.global.enabled) {
            metrics.global.dirty_cells +|= dirty_count;
            metrics.global.dirty_regions +|= dirty_regions;
        }
    }
};

test "terminal cell width handles ASCII combining CJK and emoji" {
    try std.testing.expectEqual(@as(u2, 1), unicodeCellWidth('A'));
    try std.testing.expectEqual(@as(u2, 0), unicodeCellWidth(0x0301));
    try std.testing.expectEqual(@as(u2, 2), unicodeCellWidth(0x754c));
    try std.testing.expectEqual(@as(u2, 2), unicodeCellWidth(0x1f680));
}

test "RGB colors map to portable ANSI 256-color cube" {
    try std.testing.expectEqual(@as(u8, 16), rgbToAnsi256(0, 0, 0));
    try std.testing.expectEqual(@as(u8, 231), rgbToAnsi256(255, 255, 255));
    try std.testing.expectEqual(@as(u8, 196), rgbToAnsi256(255, 0, 0));
}

test "renderer emits indexed fallback when true color is unavailable" {
    var output = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer output.deinit();
    var renderer = try Renderer.init(std.testing.allocator, 1, 1, &output.writer);
    defer renderer.deinit(std.testing.allocator);
    renderer.true_color = false;
    var cell = Cell{ .fg = .{ .rgb = .{ .r = 255, .g = 0, .b = 0 } } };
    cell.setChar("X");
    renderer.setCell(0, 0, cell);
    try renderer.flush();
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "\x1b[38;5;196m") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "\x1b[38;2;") == null);
}

test "forced full redraw re-emits unchanged cells" {
    var output = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer output.deinit();
    var renderer = try Renderer.init(std.testing.allocator, 1, 1, &output.writer);
    defer renderer.deinit(std.testing.allocator);
    var cell = Cell{};
    cell.setChar("X");
    renderer.setCell(0, 0, cell);

    try renderer.flush();
    const after_first = output.written().len;
    try renderer.flush();
    const unchanged_bytes = output.written().len - after_first;
    renderer.forceFullRedraw();
    try renderer.flush();
    const forced_bytes = output.written().len - after_first - unchanged_bytes;

    try std.testing.expect(forced_bytes > unchanged_bytes);
    try std.testing.expectEqualStrings("\x1b[?25l\x1b[0m\x1b[1;1HX\x1b[0m", output.written()[after_first + unchanged_bytes ..]);
}

test "row-run encoder golden batches adjacent cells with one cursor move" {
    var output = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer output.deinit();
    var renderer = try Renderer.init(std.testing.allocator, 3, 1, &output.writer);
    defer renderer.deinit(std.testing.allocator);
    renderer.drawText(0, 0, "ABC", .none, .none, false, false);

    try renderer.flush();
    try std.testing.expectEqualStrings("\x1b[?25l\x1b[0m\x1b[1;1HABC\x1b[0m", output.written());
}

test "row-run encoder golden separates unchanged gaps and preserves right edge" {
    var output = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer output.deinit();
    var renderer = try Renderer.init(std.testing.allocator, 5, 1, &output.writer);
    defer renderer.deinit(std.testing.allocator);
    try renderer.flush();
    const start = output.written().len;

    var left = Cell{};
    left.setChar("L");
    var right = Cell{};
    right.setChar("R");
    renderer.setCell(0, 0, left);
    renderer.setCell(4, 0, right);
    try renderer.flush();

    try std.testing.expectEqualStrings("\x1b[?25l\x1b[0m\x1b[1;1HL\x1b[1;5HR\x1b[0m", output.written()[start..]);
}

test "row-run encoder emits nothing for an unchanged frame and restores virtual cursor" {
    var output = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer output.deinit();
    var renderer = try Renderer.init(std.testing.allocator, 2, 1, &output.writer);
    defer renderer.deinit(std.testing.allocator);
    renderer.drawText(0, 0, "AB", .none, .none, false, false);
    renderer.drawCursor(1, 0);
    try renderer.flush();
    try std.testing.expect(std.mem.endsWith(u8, output.written(), "\x1b[0m\x1b[1;2H"));

    const first_frame_len = output.written().len;
    try renderer.flush();
    try std.testing.expectEqual(first_frame_len, output.written().len);
}

test "row-run encoder golden removes styles inside a run" {
    var output = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer output.deinit();
    var renderer = try Renderer.init(std.testing.allocator, 2, 1, &output.writer);
    defer renderer.deinit(std.testing.allocator);
    var styled = Cell{ .fg = .{ .index = 2 }, .bold = true };
    styled.setChar("A");
    var plain = Cell{ .fg = .{ .index = 3 } };
    plain.setChar("B");
    renderer.setCell(0, 0, styled);
    renderer.setCell(1, 0, plain);
    try renderer.flush();

    try std.testing.expect(std.mem.indexOf(u8, output.written(), "\x1b[1m\x1b[38;5;2mA\x1b[0m\x1b[38;5;3m\x1b[49mB") != null);
}

test "row-run encoder replays wide leader for either half of partial damage" {
    var output = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer output.deinit();
    var renderer = try Renderer.init(std.testing.allocator, 3, 1, &output.writer);
    defer renderer.deinit(std.testing.allocator);
    renderer.drawText(0, 0, "界X", .none, .none, false, false);
    try renderer.flush();

    var changed_leader = renderer.buf[0];
    changed_leader.setChar("語");
    renderer.setCell(0, 0, changed_leader);
    const leader_start = output.written().len;
    try renderer.flush();
    try std.testing.expect(std.mem.indexOf(u8, output.written()[leader_start..], "\x1b[1;1H語") != null);

    renderer.buf[1].bg = .{ .index = 1 };
    const continuation_start = output.written().len;
    try renderer.flush();
    try std.testing.expect(std.mem.indexOf(u8, output.written()[continuation_start..], "\x1b[1;1H語") != null);
}

test "row-run encoder golden handles unicode continuation combining style and erasure" {
    var output = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer output.deinit();
    var renderer = try Renderer.init(std.testing.allocator, 4, 1, &output.writer);
    defer renderer.deinit(std.testing.allocator);
    try renderer.flush();
    const start = output.written().len;

    renderer.drawTextClipped(0, 0, 4, "界á", .{ .index = 2 }, .{ .index = 4 }, true, false);
    try renderer.flush();
    const unicode_frame = output.written()[start..];
    try std.testing.expect(std.mem.indexOf(u8, unicode_frame, "\x1b[1;1H") != null);
    try std.testing.expect(std.mem.indexOf(u8, unicode_frame, "\x1b[1m\x1b[38;5;2m\x1b[48;5;4m界á") != null);

    const erase_start = output.written().len;
    renderer.setCell(0, 0, Cell{ .bg = .{ .index = 4 } });
    renderer.setCell(1, 0, Cell{ .bg = .{ .index = 4 } });
    try renderer.flush();
    const erase_frame = output.written()[erase_start..];
    try std.testing.expect(std.mem.indexOf(u8, erase_frame, "\x1b[1;1H") != null);
    try std.testing.expect(std.mem.indexOf(u8, erase_frame, " ") != null);
}

test "row-run encoder reduces a full changed row by more than half versus per-cell moves" {
    var output = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer output.deinit();
    const width: u16 = 80;
    var renderer = try Renderer.init(std.testing.allocator, width, 1, &output.writer);
    defer renderer.deinit(std.testing.allocator);
    for (0..width) |x| {
        var cell = Cell{};
        cell.setChar("X");
        renderer.setCell(@intCast(x), 0, cell);
    }
    try renderer.flush();

    // Legacy emitted at least a six-byte absolute move plus one glyph per
    // changed cell. Include its common frame prefix/suffix in the comparison.
    const legacy_lower_bound = 12 + @as(usize, width) * 7;
    try std.testing.expect(output.written().len * 2 < legacy_lower_bound);
}

test "terminal cell width covers variation selectors nerd font symbols and double-width continuation cases" {
    try std.testing.expectEqual(@as(u2, 0), unicodeCellWidth(0xfe0f));
    try std.testing.expectEqual(@as(u2, 1), unicodeCellWidth(0x2665));
    try std.testing.expectEqual(@as(u2, 1), unicodeCellWidth(0xe0b0));
    try std.testing.expectEqual(@as(u2, 1), unicodeCellWidth(0x200d));
}

test "drawTextClipped respects terminal boundaries and preserves continuation cells" {
    var buf = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer buf.deinit();

    var renderer = try Renderer.init(std.testing.allocator, 4, 2, &buf.writer);
    defer renderer.deinit(std.testing.allocator);

    renderer.drawTextClipped(0, 0, 4, "界áZ", .none, .none, false, false);
    renderer.drawTextClipped(3, 1, 1, "AB", .none, .none, false, false);

    try std.testing.expectEqualStrings("界", renderer.buf[0].char[0..renderer.buf[0].len]);
    try std.testing.expect(renderer.buf[1].continuation);
    try std.testing.expectEqualStrings("á", renderer.buf[2].char[0..renderer.buf[2].len]);
    try std.testing.expectEqualStrings("Z", renderer.buf[3].char[0..renderer.buf[3].len]);
    try std.testing.expectEqualStrings("A", renderer.buf[7].char[0..renderer.buf[7].len]);
}
