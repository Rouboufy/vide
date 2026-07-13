const std = @import("std");

pub const Value = union(enum) {
    nil,
    bool: bool,
    integer: i64,
    string: []const u8,
    array: []Value,
    map: []KV,
    ext: struct { type: i8, data: []const u8 },

    pub const KV = struct { key: Value, value: Value };
};

pub fn encode(writer: anytype, val: Value) !void {
    switch (val) {
        .nil => try writer.writeByte(0xc0),
        .bool => |b| try writer.writeByte(if (b) 0xc3 else 0xc2),
        .integer => |i| {
            if (i >= 0) {
                if (i <= 127) {
                    try writer.writeByte(@as(u8, @intCast(i)));
                } else if (i <= 255) {
                    try writer.writeByte(0xcc);
                    try writer.writeByte(@as(u8, @intCast(i)));
                } else if (i <= 65535) {
                    try writer.writeByte(0xcd);
                    try writer.writeInt(u16, @as(u16, @intCast(i)), .big);
                } else if (i <= 4294967295) {
                    try writer.writeByte(0xce);
                    try writer.writeInt(u32, @as(u32, @intCast(i)), .big);
                } else {
                    try writer.writeByte(0xcf);
                    try writer.writeInt(u64, @as(u64, @intCast(i)), .big);
                }
            } else {
                if (i >= -32) {
                    try writer.writeByte(@as(u8, @bitCast(@as(i8, @intCast(i)))));
                } else if (i >= -128) {
                    try writer.writeByte(0xd0);
                    try writer.writeByte(@as(u8, @bitCast(@as(i8, @intCast(i)))));
                } else if (i >= -32768) {
                    try writer.writeByte(0xd1);
                    try writer.writeInt(i16, @as(i16, @intCast(i)), .big);
                } else if (i >= -2147483648) {
                    try writer.writeByte(0xd2);
                    try writer.writeInt(i32, @as(i32, @intCast(i)), .big);
                } else {
                    try writer.writeByte(0xd3);
                    try writer.writeInt(i64, i, .big);
                }
            }
        },
        .string => |s| {
            if (s.len <= 31) {
                try writer.writeByte(0xa0 | @as(u8, @intCast(s.len)));
            } else if (s.len <= 255) {
                try writer.writeByte(0xd9);
                try writer.writeByte(@as(u8, @intCast(s.len)));
            } else if (s.len <= 65535) {
                try writer.writeByte(0xda);
                try writer.writeInt(u16, @as(u16, @intCast(s.len)), .big);
            } else {
                try writer.writeByte(0xdb);
                try writer.writeInt(u32, @as(u32, @intCast(s.len)), .big);
            }
            try writer.writeAll(s);
        },
        .array => |arr| {
            if (arr.len <= 15) {
                try writer.writeByte(0x90 | @as(u8, @intCast(arr.len)));
            } else if (arr.len <= 65535) {
                try writer.writeByte(0xdc);
                try writer.writeInt(u16, @as(u16, @intCast(arr.len)), .big);
            } else {
                try writer.writeByte(0xdd);
                try writer.writeInt(u32, @as(u32, @intCast(arr.len)), .big);
            }
            for (arr) |item| {
                try encode(writer, item);
            }
        },
        .map => |m| {
            if (m.len <= 15) {
                try writer.writeByte(0x80 | @as(u8, @intCast(m.len)));
            } else if (m.len <= 65535) {
                try writer.writeByte(0xde);
                try writer.writeInt(u16, @as(u16, @intCast(m.len)), .big);
            } else {
                try writer.writeByte(0xdf);
                try writer.writeInt(u32, @as(u32, @intCast(m.len)), .big);
            }
            for (m) |kv| {
                try encode(writer, kv.key);
                try encode(writer, kv.value);
            }
        },
        .ext => |ext| {
            const len = ext.data.len;
            if (len == 1) {
                try writer.writeByte(0xd4);
            } else if (len == 2) {
                try writer.writeByte(0xd5);
            } else if (len == 4) {
                try writer.writeByte(0xd6);
            } else if (len == 8) {
                try writer.writeByte(0xd7);
            } else if (len == 16) {
                try writer.writeByte(0xd8);
            } else if (len <= 255) {
                try writer.writeByte(0xc7);
                try writer.writeByte(@as(u8, @intCast(len)));
            } else if (len <= 65535) {
                try writer.writeByte(0xc8);
                try writer.writeInt(u16, @as(u16, @intCast(len)), .big);
            } else {
                try writer.writeByte(0xc9);
                try writer.writeInt(u32, @as(u32, @intCast(len)), .big);
            }
            try writer.writeByte(@as(u8, @bitCast(ext.type)));
            try writer.writeAll(ext.data);
        },
    }
}

pub const DecodeError = error{
    EndOfStream,
    ReadFailed,
    InvalidMarker,
    OutOfMemory,
    WouldBlock,
    MessageTooLarge,
};

const max_container_len = 1_000_000;
const max_blob_len = 64 * 1024 * 1024;

pub fn decode(reader: anytype, allocator: std.mem.Allocator) DecodeError!Value {
    const byte = try reader.takeByte();
    switch (byte) {
        0x00...0x7f => return Value{ .integer = byte },
        0x80...0x8f => {
            const len = byte & 0x0f;
            return try decodeMap(reader, allocator, len);
        },
        0x90...0x9f => {
            const len = byte & 0x0f;
            return try decodeArray(reader, allocator, len);
        },
        0xa0...0xbf => {
            const len = byte & 0x1f;
            return try decodeStr(reader, allocator, len);
        },
        0xc0 => return .nil,
        0xc1 => return error.InvalidMarker,
        0xc2 => return Value{ .bool = false },
        0xc3 => return Value{ .bool = true },
        0xc4 => {
            const len = try reader.takeByte();
            return try decodeStr(reader, allocator, len);
        },
        0xc5 => {
            const len = try reader.takeInt(u16, .big);
            return try decodeStr(reader, allocator, len);
        },
        0xc6 => {
            const len = try reader.takeInt(u32, .big);
            return try decodeStr(reader, allocator, len);
        },
        0xc7 => {
            const len = try reader.takeByte();
            return try decodeExt(reader, allocator, len);
        },
        0xc8 => {
            const len = try reader.takeInt(u16, .big);
            return try decodeExt(reader, allocator, len);
        },
        0xc9 => {
            const len = try reader.takeInt(u32, .big);
            return try decodeExt(reader, allocator, len);
        },
        0xca => {
            _ = try reader.takeInt(u32, .big);
            return .nil;
        },
        0xcb => {
            _ = try reader.takeInt(u64, .big);
            return .nil;
        },
        0xcc => return Value{ .integer = try reader.takeByte() },
        0xcd => return Value{ .integer = try reader.takeInt(u16, .big) },
        0xce => return Value{ .integer = try reader.takeInt(u32, .big) },
        0xcf => return Value{ .integer = @as(i64, @intCast(try reader.takeInt(u64, .big))) },
        0xd0 => return Value{ .integer = @as(i64, @intCast(@as(i8, @bitCast(try reader.takeByte())))) },
        0xd1 => return Value{ .integer = try reader.takeInt(i16, .big) },
        0xd2 => return Value{ .integer = try reader.takeInt(i32, .big) },
        0xd3 => return Value{ .integer = try reader.takeInt(i64, .big) },
        0xd4 => return try decodeExt(reader, allocator, 1),
        0xd5 => return try decodeExt(reader, allocator, 2),
        0xd6 => return try decodeExt(reader, allocator, 4),
        0xd7 => return try decodeExt(reader, allocator, 8),
        0xd8 => return try decodeExt(reader, allocator, 16),
        0xd9 => {
            const len = try reader.takeByte();
            return try decodeStr(reader, allocator, len);
        },
        0xda => {
            const len = try reader.takeInt(u16, .big);
            return try decodeStr(reader, allocator, len);
        },
        0xdb => {
            const len = try reader.takeInt(u32, .big);
            return try decodeStr(reader, allocator, len);
        },
        0xdc => {
            const len = try reader.takeInt(u16, .big);
            return try decodeArray(reader, allocator, len);
        },
        0xdd => {
            const len = try reader.takeInt(u32, .big);
            return try decodeArray(reader, allocator, len);
        },
        0xde => {
            const len = try reader.takeInt(u16, .big);
            return try decodeMap(reader, allocator, len);
        },
        0xdf => {
            const len = try reader.takeInt(u32, .big);
            return try decodeMap(reader, allocator, len);
        },
        0xe0...0xff => return Value{ .integer = @as(i8, @bitCast(byte)) },
    }
}

fn decodeStr(reader: anytype, allocator: std.mem.Allocator, len: usize) DecodeError!Value {
    if (len > max_blob_len) return error.MessageTooLarge;
    const buf = try allocator.alloc(u8, len);
    errdefer allocator.free(buf);
    try reader.readSliceAll(buf);
    return Value{ .string = buf };
}

fn decodeArray(reader: anytype, allocator: std.mem.Allocator, len: usize) DecodeError!Value {
    if (len > max_container_len) return error.MessageTooLarge;
    const arr = try allocator.alloc(Value, len);
    errdefer allocator.free(arr);
    var i: usize = 0;
    errdefer {
        for (0..i) |idx| {
            freeValue(arr[idx], allocator);
        }
    }
    while (i < len) : (i += 1) {
        arr[i] = try decode(reader, allocator);
    }
    return Value{ .array = arr };
}

fn decodeMap(reader: anytype, allocator: std.mem.Allocator, len: usize) DecodeError!Value {
    if (len > max_container_len) return error.MessageTooLarge;
    const map = try allocator.alloc(Value.KV, len);
    errdefer allocator.free(map);
    var i: usize = 0;
    errdefer {
        for (0..i) |idx| {
            freeValue(map[idx].key, allocator);
            freeValue(map[idx].value, allocator);
        }
    }
    while (i < len) : (i += 1) {
        const key = try decode(reader, allocator);
        errdefer freeValue(key, allocator);
        const value = try decode(reader, allocator);
        map[i] = .{ .key = key, .value = value };
    }
    return Value{ .map = map };
}

fn decodeExt(reader: anytype, allocator: std.mem.Allocator, len: usize) DecodeError!Value {
    if (len > max_blob_len) return error.MessageTooLarge;
    const type_byte = try reader.takeByte();
    const data = try allocator.alloc(u8, len);
    errdefer allocator.free(data);
    try reader.readSliceAll(data);
    return Value{
        .ext = .{
            .type = @as(i8, @bitCast(type_byte)),
            .data = data,
        },
    };
}

pub fn freeValue(val: Value, allocator: std.mem.Allocator) void {
    switch (val) {
        .string => |s| allocator.free(s),
        .array => |arr| {
            for (arr) |item| {
                freeValue(item, allocator);
            }
            allocator.free(arr);
        },
        .map => |m| {
            for (m) |kv| {
                freeValue(kv.key, allocator);
                freeValue(kv.value, allocator);
            }
            allocator.free(m);
        },
        .ext => |ext| allocator.free(ext.data),
        else => {},
    }
}

test "msgpack roundtrip" {
    const allocator = std.testing.allocator;
    var buf = std.Io.Writer.Allocating.init(allocator);
    defer buf.deinit();

    // Allocate array on heap for original value
    var list = try allocator.alloc(Value, 4);
    list[0] = .{ .integer = 42 };
    // Allocate string on heap
    list[1] = .{ .string = try allocator.dupe(u8, "hello msgpack") };
    list[2] = .{ .bool = true };
    list[3] = .nil;

    const original = Value{
        .array = list,
    };
    defer freeValue(original, allocator);
    try encode(&buf.writer, original);

    var reader = std.Io.Reader.fixed(buf.written());
    const decoded = try decode(&reader, allocator);
    defer freeValue(decoded, allocator);

    try std.testing.expect(decoded == .array);
    try std.testing.expectEqual(@as(usize, 4), decoded.array.len);
    try std.testing.expectEqual(@as(i64, 42), decoded.array[0].integer);
    try std.testing.expectEqualStrings("hello msgpack", decoded.array[1].string);
    try std.testing.expectEqual(true, decoded.array[2].bool);
    try std.testing.expect(decoded.array[3] == .nil);
}

test "msgpack rejects unreasonable declared payload sizes" {
    // str32 with a length one byte larger than the decoder's safety limit.
    const encoded = [_]u8{ 0xdb, 0x04, 0x00, 0x00, 0x01 };
    var reader = std.Io.Reader.fixed(&encoded);
    try std.testing.expectError(error.MessageTooLarge, decode(&reader, std.testing.allocator));
}

test "msgpack signed integer boundaries roundtrip" {
    const values = [_]i64{ -33, -128, -129, -32768, -32769, std.math.minInt(i32), std.math.minInt(i64), 127, 128, 65536 };
    for (values) |expected| {
        var buf = std.Io.Writer.Allocating.init(std.testing.allocator);
        defer buf.deinit();
        try encode(&buf.writer, .{ .integer = expected });
        var reader = std.Io.Reader.fixed(buf.written());
        const decoded = try decode(&reader, std.testing.allocator);
        try std.testing.expectEqual(expected, decoded.integer);
    }
}
