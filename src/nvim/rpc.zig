const std = @import("std");
const posix = std.posix;
const NvimProcess = @import("process.zig").NvimProcess;
const msgpack = @import("msgpack.zig");
const Value = msgpack.Value;

pub const RpcClient = struct {
    process: NvimProcess,
    msg_id: u32 = 0,
    allocator: std.mem.Allocator,
    io: std.Io,
    on_notification: ?*const fn (ctx: ?*anyopaque, method: []const u8, params: Value) anyerror!void = null,
    on_notification_ctx: ?*anyopaque = null,

    pub fn init(process: NvimProcess, allocator: std.mem.Allocator, io: std.Io) RpcClient {
        return .{
            .process = process,
            .allocator = allocator,
            .io = io,
        };
    }

    pub fn nextId(self: *RpcClient) u32 {
        self.msg_id += 1;
        return self.msg_id;
    }

    fn writeThread(fd: posix.fd_t, data: []const u8, allocator: std.mem.Allocator) void {
        var total_written: usize = 0;
        while (total_written < data.len) {
            const sub = data[total_written..];
            const rc = posix.system.write(fd, sub.ptr, sub.len);
            const err = posix.errno(rc);
            switch (err) {
                .SUCCESS => total_written += rc,
                .INTR => continue,
                .AGAIN => {
                    var fds = [1]posix.pollfd{.{ .fd = fd, .events = posix.POLL.OUT, .revents = 0 }};
                    _ = posix.poll(&fds, -1) catch 0;
                },
                else => break,
            }
        }
        allocator.free(data);
    }

    fn send(self: *RpcClient, val: Value) !void {
        var buf = std.Io.Writer.Allocating.init(self.allocator);
        defer buf.deinit();
        try msgpack.encode(&buf.writer, val);
        const data = try self.allocator.dupe(u8, buf.written());
        const thread = try std.Thread.spawn(.{}, writeThread, .{ self.process.stdin.handle, data, self.allocator });
        thread.detach();
    }

    pub fn call(self: *RpcClient, method: []const u8, params: []const Value) !Value {
        const id = self.nextId();
        var req_arr = try self.allocator.alloc(Value, 4);
        defer self.allocator.free(req_arr);
        req_arr[0] = .{ .integer = 0 };
        req_arr[1] = .{ .integer = id };
        req_arr[2] = .{ .string = method };
        const params_dup = try self.allocator.alloc(Value, params.len);
        @memcpy(params_dup, params);
        defer self.allocator.free(params_dup);
        req_arr[3] = .{ .array = params_dup };
        try self.send(.{ .array = req_arr });
        return try self.waitResponse(id);
    }

    pub fn notify(self: *RpcClient, method: []const u8, params: []const Value) !void {
        var req_arr = try self.allocator.alloc(Value, 3);
        defer self.allocator.free(req_arr);
        req_arr[0] = .{ .integer = 2 };
        req_arr[1] = .{ .string = method };
        const params_dup = try self.allocator.alloc(Value, params.len);
        @memcpy(params_dup, params);
        defer self.allocator.free(params_dup);
        req_arr[2] = .{ .array = params_dup };
        try self.send(.{ .array = req_arr });
    }

    fn waitResponse(self: *RpcClient, id: u32) !Value {
        var fd_reader = FdReader{ .fd = self.process.stdout.handle };
        while (true) {
            // Blocking read here is safer than a strict timeout
            const msg = try msgpack.decode(&fd_reader, self.allocator);
            errdefer msgpack.freeValue(msg, self.allocator);
            if (msg != .array or msg.array.len < 3) {
                return error.InvalidRpcMessage;
            }
            const msg_type = msg.array[0].integer;
            if (msg_type == 1) {
                const resp_id = msg.array[1].integer;
                if (resp_id == id) {
                    const err_val = msg.array[2];
                    if (err_val != .nil) {
                        if (err_val == .array and err_val.array.len >= 2 and err_val.array[1] == .string) {
                            std.debug.print("Neovim RPC Error: {s}\n", .{err_val.array[1].string});
                        } else {
                            std.debug.print("Unknown Neovim RPC Error\n", .{});
                        }
                        return error.NvimRpcError;
                    }
                    const result = msg.array[3];
                    for (msg.array, 0..) |item, idx| { if (idx != 3) msgpack.freeValue(item, self.allocator); }
                    self.allocator.free(msg.array);
                    return result;
                }
            } else if (msg_type == 2) {
                if (self.on_notification) |cb| {
                    const method = msg.array[1].string;
                    const params = msg.array[2];
                    try cb(self.on_notification_ctx, method, params);
                }
                msgpack.freeValue(msg, self.allocator);
            } else { msgpack.freeValue(msg, self.allocator); }
        }
    }

    pub fn processNotifications(self: *RpcClient) !bool {
        while (self.hasData()) {
            var fd_reader = FdReader{ .fd = self.process.stdout.handle };
            const msg = msgpack.decode(&fd_reader, self.allocator) catch |err| {
                if (err == error.EndOfStream) return false;
                return err;
            };
            defer msgpack.freeValue(msg, self.allocator);
            if (msg == .array and msg.array.len >= 3) {
                const msg_type = msg.array[0].integer;
                if (msg_type == 2) {
                    if (self.on_notification) |cb| {
                        const method = msg.array[1].string;
                        const params = msg.array[2];
                        try cb(self.on_notification_ctx, method, params);
                    }
                }
            }
        }
        return true;
    }

    pub fn hasData(self: RpcClient) bool {
        var fds = [1]posix.pollfd{.{ .fd = self.process.stdout.handle, .events = posix.POLL.IN, .revents = 0 }};
        const rc = posix.poll(&fds, 0) catch return false;
        return rc > 0 and (fds[0].revents & (posix.POLL.IN | posix.POLL.HUP | posix.POLL.ERR)) != 0;
    }
};

pub const FdReader = struct {
    fd: posix.fd_t,
    pub fn takeByte(self: *FdReader) !u8 {
        var buf: [1]u8 = undefined;
        try self.readSliceAll(&buf);
        return buf[0];
    }
    pub fn takeInt(self: *FdReader, comptime T: type, endian: std.builtin.Endian) !T {
        var buf: [@sizeOf(T)]u8 = undefined;
        try self.readSliceAll(&buf);
        return std.mem.readInt(T, &buf, endian);
    }
    pub fn readSliceAll(self: *FdReader, dest: []u8) !void {
        var total_read: usize = 0;
        while (total_read < dest.len) {
            const sub = dest[total_read..];
            const rc = posix.system.read(self.fd, sub.ptr, sub.len);
            const err = posix.errno(rc);
            switch (err) {
                .SUCCESS => {
                    if (rc == 0) return error.EndOfStream;
                    total_read += rc;
                },
                .INTR => continue,
                else => return error.ReadFailed,
            }
        }
    }
};
