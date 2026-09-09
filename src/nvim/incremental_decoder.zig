//! Bounded, allocation-safe incremental MessagePack framing for Prompt 05A.
//!
//! `feed` only retains bytes. `next` first scans a complete frame without
//! allocating, then decodes exactly that frame. Incomplete input therefore
//! never creates a partially-owned Value and never waits for more bytes.
const std = @import("std");
const msgpack = @import("msgpack.zig");

pub const max_buffered_bytes: usize = 8 * 1024 * 1024;
pub const max_blob_bytes: usize = 4 * 1024 * 1024;
pub const max_collection_items: usize = 262_144;
pub const max_nesting_depth: usize = 64;

pub const Error = error{
    Incomplete,
    TruncatedFrame,
    BufferLimitExceeded,
    BlobLimitExceeded,
    CollectionLimitExceeded,
    NestingLimitExceeded,
    InvalidMarker,
    IntegerOverflow,
    OutOfMemory,
};

pub const Decoder = struct {
    allocator: std.mem.Allocator,
    bytes: std.array_list.Managed(u8),
    head: usize = 0,
    eof: bool = false,
    framer: Framer = .{},

    pub fn init(allocator: std.mem.Allocator) Decoder {
        return .{ .allocator = allocator, .bytes = .init(allocator) };
    }

    pub fn deinit(self: *Decoder) void {
        self.bytes.deinit();
        self.* = undefined;
    }

    pub fn feed(self: *Decoder, input: []const u8) Error!void {
        if (self.eof) return error.TruncatedFrame;
        if (input.len > max_buffered_bytes - self.bufferedLen()) return error.BufferLimitExceeded;
        if (self.head != 0 and input.len > max_buffered_bytes - self.bytes.items.len) self.compact();
        try self.bytes.appendSlice(input);
    }

    pub fn finish(self: *Decoder) void {
        self.eof = true;
    }

    pub fn bufferedLen(self: *const Decoder) usize {
        return self.bytes.items.len - self.head;
    }

    /// Caller owns the returned Value. Incomplete leaves all bytes untouched.
    pub fn next(self: *Decoder) (Error || msgpack.DecodeError)!?msgpack.Value {
        if (self.bufferedLen() == 0) return null;
        const buffered = self.bytes.items[self.head..];
        self.framer.advance(buffered) catch |err| switch (err) {
            error.Incomplete => if (self.eof) return error.TruncatedFrame else return null,
            else => return err,
        };
        const frame_len = self.framer.offset;
        var reader: SliceReader = .{ .input = buffered[0..frame_len] };
        const value = try msgpack.decode(&reader, self.allocator);
        std.debug.assert(reader.offset == frame_len);
        self.head += frame_len;
        self.framer = .{};
        if (self.head == self.bytes.items.len) {
            self.bytes.clearRetainingCapacity();
            self.head = 0;
        } else if (self.head >= self.bytes.items.len / 2) {
            self.compact();
        }
        return value;
    }

    fn compact(self: *Decoder) void {
        if (self.head == 0) return;
        const remaining = self.bufferedLen();
        std.mem.copyForwards(u8, self.bytes.items[0..remaining], self.bytes.items[self.head..]);
        self.bytes.shrinkRetainingCapacity(remaining);
        self.head = 0;
    }
};

const Framer = struct {
    offset: usize = 0,
    remaining: [max_nesting_depth + 1]usize = [_]usize{0} ** (max_nesting_depth + 1),
    stack_len: usize = 1,
    initialized: bool = false,

    fn take(input: []const u8, cursor: *usize, count: usize) Error![]const u8 {
        if (count > input.len - cursor.*) return error.Incomplete;
        const result = input[cursor.* .. cursor.* + count];
        cursor.* += count;
        return result;
    }

    fn uint(input: []const u8, cursor: *usize, comptime T: type) Error!usize {
        const bytes = try take(input, cursor, @sizeOf(T));
        const number = std.mem.readInt(T, bytes[0..@sizeOf(T)], .big);
        return std.math.cast(usize, number) orelse error.IntegerOverflow;
    }

    fn blob(input: []const u8, cursor: *usize, len: usize) Error!void {
        if (len > max_blob_bytes) return error.BlobLimitExceeded;
        _ = try take(input, cursor, len);
    }

    fn pushCollection(self: *Framer, len: usize, multiplier: usize) Error!void {
        if (len > max_collection_items) return error.CollectionLimitExceeded;
        const total = std.math.mul(usize, len, multiplier) catch return error.CollectionLimitExceeded;
        std.debug.assert(self.remaining[self.stack_len - 1] != 0);
        self.remaining[self.stack_len - 1] -= 1;
        if (total == 0) {
            self.collapseCompleted();
            return;
        }
        if (self.stack_len == self.remaining.len) return error.NestingLimitExceeded;
        self.remaining[self.stack_len] = total;
        self.stack_len += 1;
    }

    fn completeValue(self: *Framer) void {
        std.debug.assert(self.remaining[self.stack_len - 1] != 0);
        self.remaining[self.stack_len - 1] -= 1;
        self.collapseCompleted();
    }

    fn collapseCompleted(self: *Framer) void {
        while (self.stack_len > 1 and self.remaining[self.stack_len - 1] == 0) self.stack_len -= 1;
    }

    fn advance(self: *Framer, input: []const u8) Error!void {
        if (!self.initialized) {
            self.remaining[0] = 1;
            self.initialized = true;
        }
        while (!(self.stack_len == 1 and self.remaining[0] == 0)) try self.one(input);
    }

    fn one(self: *Framer, input: []const u8) Error!void {
        var cursor = self.offset;
        const marker = (try take(input, &cursor, 1))[0];
        switch (marker) {
            0x00...0x7f, 0xc0, 0xc2, 0xc3, 0xe0...0xff => self.completeValue(),
            0x80...0x8f => try self.pushCollection(marker & 0x0f, 2),
            0x90...0x9f => try self.pushCollection(marker & 0x0f, 1),
            0xa0...0xbf => {
                try blob(input, &cursor, marker & 0x1f);
                self.completeValue();
            },
            0xc1 => return error.InvalidMarker,
            0xc4, 0xd9 => {
                try blob(input, &cursor, try uint(input, &cursor, u8));
                self.completeValue();
            },
            0xc5, 0xda => {
                try blob(input, &cursor, try uint(input, &cursor, u16));
                self.completeValue();
            },
            0xc6, 0xdb => {
                try blob(input, &cursor, try uint(input, &cursor, u32));
                self.completeValue();
            },
            0xc7 => {
                const len = try uint(input, &cursor, u8);
                _ = try take(input, &cursor, 1);
                try blob(input, &cursor, len);
                self.completeValue();
            },
            0xc8 => {
                const len = try uint(input, &cursor, u16);
                _ = try take(input, &cursor, 1);
                try blob(input, &cursor, len);
                self.completeValue();
            },
            0xc9 => {
                const len = try uint(input, &cursor, u32);
                _ = try take(input, &cursor, 1);
                try blob(input, &cursor, len);
                self.completeValue();
            },
            0xca => {
                _ = try take(input, &cursor, 4);
                self.completeValue();
            },
            0xcb => {
                _ = try take(input, &cursor, 8);
                self.completeValue();
            },
            0xcc, 0xd0 => {
                _ = try take(input, &cursor, 1);
                self.completeValue();
            },
            0xcd, 0xd1 => {
                _ = try take(input, &cursor, 2);
                self.completeValue();
            },
            0xce, 0xd2 => {
                _ = try take(input, &cursor, 4);
                self.completeValue();
            },
            0xcf => {
                const unsigned = try uint(input, &cursor, u64);
                if (unsigned > std.math.maxInt(i64)) return error.IntegerOverflow;
                self.completeValue();
            },
            0xd3 => {
                _ = try take(input, &cursor, 8);
                self.completeValue();
            },
            0xd4 => {
                _ = try take(input, &cursor, 1);
                try blob(input, &cursor, 1);
                self.completeValue();
            },
            0xd5 => {
                _ = try take(input, &cursor, 1);
                try blob(input, &cursor, 2);
                self.completeValue();
            },
            0xd6 => {
                _ = try take(input, &cursor, 1);
                try blob(input, &cursor, 4);
                self.completeValue();
            },
            0xd7 => {
                _ = try take(input, &cursor, 1);
                try blob(input, &cursor, 8);
                self.completeValue();
            },
            0xd8 => {
                _ = try take(input, &cursor, 1);
                try blob(input, &cursor, 16);
                self.completeValue();
            },
            0xdc => try self.pushCollection(try uint(input, &cursor, u16), 1),
            0xdd => try self.pushCollection(try uint(input, &cursor, u32), 1),
            0xde => try self.pushCollection(try uint(input, &cursor, u16), 2),
            0xdf => try self.pushCollection(try uint(input, &cursor, u32), 2),
        }
        self.offset = cursor;
    }
};

const SliceReader = struct {
    input: []const u8,
    offset: usize = 0,
    pub fn takeByte(self: *SliceReader) error{EndOfStream}!u8 {
        if (self.offset == self.input.len) return error.EndOfStream;
        defer self.offset += 1;
        return self.input[self.offset];
    }
    pub fn takeInt(self: *SliceReader, comptime T: type, endian: std.builtin.Endian) error{EndOfStream}!T {
        var bytes: [@sizeOf(T)]u8 = undefined;
        try self.readSliceAll(&bytes);
        return std.mem.readInt(T, &bytes, endian);
    }
    pub fn readSliceAll(self: *SliceReader, destination: []u8) error{EndOfStream}!void {
        if (destination.len > self.input.len - self.offset) return error.EndOfStream;
        @memcpy(destination, self.input[self.offset .. self.offset + destination.len]);
        self.offset += destination.len;
    }
};

test "byte-by-byte delivery and every truncation boundary allocate nothing while incomplete" {
    const encoded = [_]u8{ 0x93, 0xa3, 'o', 'n', 'e', 0x92, 1, 2, 0xc3 };
    for (0..encoded.len) |cut| {
        var decoder = Decoder.init(std.testing.allocator);
        defer decoder.deinit();
        try decoder.feed(encoded[0..cut]);
        try std.testing.expect(try decoder.next() == null);
        try std.testing.expectEqual(cut, decoder.bufferedLen());
    }
    var decoder = Decoder.init(std.testing.allocator);
    defer decoder.deinit();
    for (encoded) |byte| {
        try decoder.feed(&.{byte});
        if (decoder.bufferedLen() < encoded.len) try std.testing.expect(try decoder.next() == null);
    }
    const value = (try decoder.next()).?;
    defer msgpack.freeValue(value, std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 3), value.array.len);
}

test "multiple frames survive one feed and complete data survives HUP" {
    var decoder = Decoder.init(std.testing.allocator);
    defer decoder.deinit();
    try decoder.feed(&.{ 1, 0xa1, 'x' });
    decoder.finish();
    const first = (try decoder.next()).?;
    defer msgpack.freeValue(first, std.testing.allocator);
    const second = (try decoder.next()).?;
    defer msgpack.freeValue(second, std.testing.allocator);
    try std.testing.expectEqual(@as(i64, 1), first.integer);
    try std.testing.expectEqualStrings("x", second.string);
    try std.testing.expect(try decoder.next() == null);
}

test "HUP rejects only the incomplete tail after complete frames" {
    var decoder = Decoder.init(std.testing.allocator);
    defer decoder.deinit();
    try decoder.feed(&.{ 7, 0xda, 0, 4, 'x' });
    decoder.finish();
    const first = (try decoder.next()).?;
    defer msgpack.freeValue(first, std.testing.allocator);
    try std.testing.expectEqual(@as(i64, 7), first.integer);
    try std.testing.expectError(error.TruncatedFrame, decoder.next());
}

test "depth collection blob and total buffer limits are enforced" {
    var depth_decoder = Decoder.init(std.testing.allocator);
    defer depth_decoder.deinit();
    try depth_decoder.feed(&([_]u8{0x91} ** (max_nesting_depth + 2)));
    try std.testing.expectError(error.NestingLimitExceeded, depth_decoder.next());

    var collection_decoder = Decoder.init(std.testing.allocator);
    defer collection_decoder.deinit();
    try collection_decoder.feed(&.{ 0xdd, 0, 4, 0, 1 });
    try std.testing.expectError(error.CollectionLimitExceeded, collection_decoder.next());

    var blob_decoder = Decoder.init(std.testing.allocator);
    defer blob_decoder.deinit();
    try blob_decoder.feed(&.{ 0xdb, 0, 64, 0, 1 });
    try std.testing.expectError(error.BlobLimitExceeded, blob_decoder.next());

    var buffer_decoder = Decoder.init(std.testing.allocator);
    defer buffer_decoder.deinit();
    const oversized = try std.testing.allocator.alloc(u8, max_buffered_bytes + 1);
    defer std.testing.allocator.free(oversized);
    try std.testing.expectError(error.BufferLimitExceeded, buffer_decoder.feed(oversized));
}

test "allocation failure preserves the complete frame for retry" {
    var decoder = Decoder.init(std.testing.allocator);
    defer decoder.deinit();
    try decoder.feed(&.{ 0x92, 0xa3, 'a', 'b', 'c', 0xa3, 'd', 'e', 'f' });
    const original_allocator = decoder.allocator;
    decoder.allocator = std.testing.failing_allocator;
    try std.testing.expectError(error.OutOfMemory, decoder.next());
    try std.testing.expectEqual(@as(usize, 9), decoder.bufferedLen());
    decoder.allocator = original_allocator;
    const value = (try decoder.next()).?;
    defer msgpack.freeValue(value, std.testing.allocator);
}

test "every decode allocation failure cleans partial ownership" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, struct {
        fn run(allocator: std.mem.Allocator) !void {
            var decoder = Decoder.init(allocator);
            defer decoder.deinit();
            try decoder.feed(&.{ 0x82, 0xa3, 'o', 'n', 'e', 0x92, 1, 2, 0xa3, 't', 'w', 'o', 0xa3, 'a', 'b', 'c' });
            const decoded = (try decoder.next()).?;
            defer msgpack.freeValue(decoded, allocator);
        }
    }.run, .{});
}

test "invalid marker and unsigned integer overflow are deterministic" {
    var invalid = Decoder.init(std.testing.allocator);
    defer invalid.deinit();
    try invalid.feed(&.{0xc1});
    try std.testing.expectError(error.InvalidMarker, invalid.next());

    var overflow = Decoder.init(std.testing.allocator);
    defer overflow.deinit();
    try overflow.feed(&.{ 0xcf, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff });
    try std.testing.expectError(error.IntegerOverflow, overflow.next());
}

test "large fragmented collection retains linear framing progress" {
    const item_count: usize = 32_768;
    var decoder = Decoder.init(std.testing.allocator);
    defer decoder.deinit();
    const header = [_]u8{ 0xdd, 0, 0, 0x80, 0 };
    for (header) |byte| {
        try decoder.feed(&.{byte});
        try std.testing.expect(try decoder.next() == null);
    }
    var previous_offset = decoder.framer.offset;
    for (0..item_count) |index| {
        try decoder.feed(&.{0});
        const result = try decoder.next();
        if (index + 1 == item_count) {
            const value = result.?;
            defer msgpack.freeValue(value, std.testing.allocator);
            try std.testing.expectEqual(item_count, value.array.len);
        } else {
            try std.testing.expect(result == null);
            try std.testing.expect(decoder.framer.offset > previous_offset);
            previous_offset = decoder.framer.offset;
        }
    }
}

test "many tiny frames use amortized compaction" {
    const frame_count: usize = 16_384;
    var decoder = Decoder.init(std.testing.allocator);
    defer decoder.deinit();
    const frames = try std.testing.allocator.alloc(u8, frame_count);
    defer std.testing.allocator.free(frames);
    @memset(frames, 1);
    try decoder.feed(frames);
    for (0..frame_count) |_| {
        const value = (try decoder.next()).?;
        try std.testing.expectEqual(@as(i64, 1), value.integer);
    }
    try std.testing.expectEqual(@as(usize, 0), decoder.bufferedLen());
}

test "multi-megabyte frame accepts more than one hundred transport chunks" {
    const payload_len: usize = 1024 * 1024 + 17;
    var decoder = Decoder.init(std.testing.allocator);
    defer decoder.deinit();
    const payload = try std.testing.allocator.alloc(u8, payload_len);
    defer std.testing.allocator.free(payload);
    @memset(payload, 'z');
    const header = [_]u8{ 0xdb, 0, 0x10, 0, 0x11 };
    try decoder.feed(&header);
    var offset: usize = 0;
    while (offset < payload.len) {
        const end = @min(offset + 8192, payload.len);
        try decoder.feed(payload[offset..end]);
        const decoded = try decoder.next();
        if (end == payload.len) {
            const value = decoded.?;
            defer msgpack.freeValue(value, std.testing.allocator);
            try std.testing.expectEqual(payload_len, value.string.len);
        } else try std.testing.expect(decoded == null);
        offset = end;
    }
}
