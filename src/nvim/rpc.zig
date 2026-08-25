const std = @import("std");
const posix = std.posix;
const NvimProcess = @import("process.zig").NvimProcess;
const msgpack = @import("msgpack.zig");
const Value = msgpack.Value;
const metrics = @import("../metrics.zig");

pub const RpcClient = struct {
    process: NvimProcess,
    msg_id: u32 = 0,
    allocator: std.mem.Allocator,
    io: std.Io,
    on_notification: ?*const fn (ctx: ?*anyopaque, method: []const u8, params: Value) anyerror!void = null,
    on_notification_ctx: ?*anyopaque = null,
    reader: FdReader,

    pub fn init(process: NvimProcess, allocator: std.mem.Allocator, io: std.Io) RpcClient {
        return .{
            .process = process,
            .allocator = allocator,
            .io = io,
            .reader = FdReader.init(process.stdout.handle, allocator),
        };
    }

    pub fn deinit(self: *RpcClient) void {
        self.reader.deinit();
    }

    pub fn nextId(self: *RpcClient) u32 {
        self.msg_id += 1;
        return self.msg_id;
    }

    fn send(self: *RpcClient, val: Value) !void {
        var buf = std.Io.Writer.Allocating.init(self.allocator);
        defer buf.deinit();
        try msgpack.encode(&buf.writer, val);
        const data = buf.written();
        var total_written: usize = 0;
        while (total_written < data.len) {
            var fds = [2]posix.pollfd{
                .{ .fd = self.process.stdin.handle, .events = posix.POLL.OUT, .revents = 0 },
                .{ .fd = self.process.stdout.handle, .events = posix.POLL.IN, .revents = 0 },
            };
            const rc_poll = posix.poll(&fds, -1) catch 0;
            if (rc_poll > 0) {
                // Drain exactly one complete inbound frame to prevent a full
                // stdout pipe from deadlocking Neovim while we write. Do not
                // drain-until-empty here: callbacks may enqueue more traffic.
                if ((fds[1].revents & (posix.POLL.IN | posix.POLL.ERR | posix.POLL.HUP)) != 0) {
                    if (!try self.processOneMessage()) return error.Closed;
                }
                if ((fds[0].revents & posix.POLL.OUT) != 0) {
                    const rc = posix.system.write(self.process.stdin.handle, data[total_written..].ptr, data.len - total_written);
                    const err = posix.errno(rc);
                    switch (err) {
                        .SUCCESS => {
                            if (rc > 0) total_written += @as(usize, @intCast(rc)) else return error.Closed;
                        },
                        .INTR => continue,
                        .AGAIN => continue,
                        else => return error.WriteFailed,
                    }
                }
            }
        }
    }

    pub fn call(self: *RpcClient, method: []const u8, params: []const Value) !Value {
        var timer = metrics.ScopedTimer.start(&metrics.global, &metrics.global.blocking_rpc);
        defer timer.stop();
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

    /// Send an error response to a request message received from nvim.
    /// Without this, nvim blocks forever waiting for the response (deadlock).
    /// Uses a direct write (not send()) to avoid recursive processNotifications() calls.
    fn replyError(self: *RpcClient, req_id: i64) void {
        var resp_arr = self.allocator.alloc(Value, 4) catch return;
        resp_arr[0] = .{ .integer = 1 };
        resp_arr[1] = .{ .integer = req_id };
        resp_arr[2] = .{ .string = "method not found" };
        resp_arr[3] = .nil;
        defer self.allocator.free(resp_arr);

        var buf = std.Io.Writer.Allocating.init(self.allocator);
        defer buf.deinit();
        msgpack.encode(&buf.writer, Value{ .array = resp_arr }) catch return;
        const data = buf.written();

        // Direct write without calling processNotifications() recursively.
        var written: usize = 0;
        while (written < data.len) {
            var fds = [1]posix.pollfd{.{ .fd = self.process.stdin.handle, .events = posix.POLL.OUT, .revents = 0 }};
            const rc_poll = posix.poll(&fds, 200) catch break;
            if (rc_poll == 0) break; // timeout, give up
            const rc = posix.system.write(self.process.stdin.handle, data[written..].ptr, data.len - written);
            switch (posix.errno(rc)) {
                .SUCCESS => {
                    if (rc > 0) written += @as(usize, @intCast(rc)) else break;
                },
                .INTR => continue,
                .AGAIN => continue,
                else => break,
            }
        }
    }

    fn waitResponse(self: *RpcClient, id: u32) !Value {
        var retries: usize = 0;
        const max_retries = 100;
        while (true) {
            // Read with retry on WouldBlock (non-blocking stdout fd)
            const checkpoint = self.reader.head;
            var decode_timer = metrics.ScopedTimer.start(&metrics.global, &metrics.global.rpc_decode);
            const msg = msgpack.decode(&self.reader, self.allocator) catch |err| {
                decode_timer.stop();
                self.reader.head = checkpoint;
                if (err == error.WouldBlock) {
                    if (retries >= max_retries) {
                        return error.Timeout;
                    }
                    retries += 1;
                    // No complete message yet: wait a bit and retry
                    var fds = [1]posix.pollfd{.{ .fd = self.process.stdout.handle, .events = posix.POLL.IN, .revents = 0 }};
                    _ = posix.poll(&fds, 100) catch {};
                    continue;
                }
                return err;
            };
            decode_timer.stop();
            self.reader.discardConsumed();
            retries = 0;
            errdefer msgpack.freeValue(msg, self.allocator);
            if (msg != .array or msg.array.len < 3) {
                return error.InvalidRpcMessage;
            }
            const msg_type = msg.array[0].integer;
            if (msg_type == 0 and msg.array.len >= 4) {
                // nvim sent a request to us — reply with an error to unblock it
                const req_id = msg.array[1].integer;
                self.replyError(req_id);
                msgpack.freeValue(msg, self.allocator);
            } else if (msg_type == 1) {
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
                    for (msg.array, 0..) |item, idx| {
                        if (idx != 3) msgpack.freeValue(item, self.allocator);
                    }
                    self.allocator.free(msg.array);
                    return result;
                } else {
                    msgpack.freeValue(msg, self.allocator);
                }
            } else if (msg_type == 2) {
                if (self.on_notification) |cb| {
                    var callback_timer = metrics.ScopedTimer.start(&metrics.global, &metrics.global.callback_dispatch);
                    defer callback_timer.stop();
                    const method = msg.array[1].string;
                    const params = msg.array[2];
                    try cb(self.on_notification_ctx, method, params);
                }
                msgpack.freeValue(msg, self.allocator);
            } else {
                msgpack.freeValue(msg, self.allocator);
            }
        }
    }

    pub fn processNotifications(self: *RpcClient) !bool {
        var msg_count: usize = 0;
        while (self.hasData() and msg_count < 250) : (msg_count += 1) {
            if (!try self.processOneMessage()) return false;
        }
        if (metrics.global.enabled) {
            metrics.global.queue_depth = @max(metrics.global.queue_depth, msg_count);
            if (msg_count > 1) metrics.global.coalesced_events +|= @intCast(msg_count - 1);
        }
        return true;
    }

    fn processOneMessage(self: *RpcClient) !bool {
        const checkpoint = self.reader.head;
        var decode_timer = metrics.ScopedTimer.start(&metrics.global, &metrics.global.rpc_decode);
        const msg = msgpack.decode(&self.reader, self.allocator) catch |err| {
            decode_timer.stop();
            self.reader.head = checkpoint;
            if (err == error.EndOfStream) return false;
            return err;
        };
        decode_timer.stop();
        self.reader.discardConsumed();
        defer msgpack.freeValue(msg, self.allocator);
        if (msg != .array or msg.array.len < 3 or msg.array[0] != .integer) return true;
        const msg_type = msg.array[0].integer;
        if (msg_type == 0 and msg.array.len >= 4 and msg.array[1] == .integer) {
            self.replyError(msg.array[1].integer);
        } else if (msg_type == 2 and msg.array[1] == .string) {
            if (self.on_notification) |cb| {
                var callback_timer = metrics.ScopedTimer.start(&metrics.global, &metrics.global.callback_dispatch);
                defer callback_timer.stop();
                try cb(self.on_notification_ctx, msg.array[1].string, msg.array[2]);
            }
        }
        return true;
    }

    pub fn hasData(self: *RpcClient) bool {
        if (self.reader.head < self.reader.buf.items.len) return true;
        var fds = [1]posix.pollfd{.{ .fd = self.process.stdout.handle, .events = posix.POLL.IN, .revents = 0 }};
        const rc = posix.poll(&fds, 0) catch return false;
        return rc > 0 and (fds[0].revents & (posix.POLL.IN | posix.POLL.HUP | posix.POLL.ERR)) != 0;
    }
};

pub const FdReader = struct {
    fd: posix.fd_t,
    buf: std.array_list.Managed(u8),
    head: usize = 0,

    pub fn init(fd: posix.fd_t, allocator: std.mem.Allocator) FdReader {
        return .{ .fd = fd, .buf = std.array_list.Managed(u8).init(allocator) };
    }

    pub fn deinit(self: *FdReader) void {
        self.buf.deinit();
    }

    pub fn discardConsumed(self: *FdReader) void {
        if (self.head == 0) return;
        if (self.head >= self.buf.items.len) {
            self.buf.clearRetainingCapacity();
            self.head = 0;
            return;
        }
        const remaining = self.buf.items.len - self.head;
        std.mem.copyForwards(u8, self.buf.items[0..remaining], self.buf.items[self.head..]);
        self.buf.shrinkRetainingCapacity(remaining);
        self.head = 0;
    }

    fn fill(self: *FdReader) !void {
        var temp: [8192]u8 = undefined;
        while (true) {
            const rc = posix.system.read(self.fd, &temp, temp.len);
            const err = posix.errno(rc);
            switch (err) {
                .SUCCESS => {
                    if (rc == 0) return error.EndOfStream;
                    try self.buf.appendSlice(temp[0..@as(usize, @intCast(rc))]);
                    return;
                },
                .INTR => continue,
                .AGAIN => {
                    // Non-blocking fd: wait up to 50ms for data.
                    // This prevents an infinite hang when only part of a
                    // msgpack message has arrived in the pipe buffer.
                    var fds = [1]posix.pollfd{.{ .fd = self.fd, .events = posix.POLL.IN, .revents = 0 }};
                    const poll_rc = posix.poll(&fds, 50) catch return error.WouldBlock;
                    if (poll_rc == 0) return error.WouldBlock; // timeout
                    continue;
                },
                else => return error.ReadFailed,
            }
        }
    }

    pub fn takeByte(self: *FdReader) !u8 {
        if (self.head >= self.buf.items.len) try self.fill();
        const b = self.buf.items[self.head];
        self.head += 1;
        return b;
    }

    pub fn takeInt(self: *FdReader, comptime T: type, endian: std.builtin.Endian) !T {
        var buf_int: [@sizeOf(T)]u8 = undefined;
        try self.readSliceAll(&buf_int);
        return std.mem.readInt(T, &buf_int, endian);
    }

    pub fn readSliceAll(self: *FdReader, dest: []u8) !void {
        var total_read: usize = 0;
        while (total_read < dest.len) {
            if (self.head >= self.buf.items.len) try self.fill();
            const available = self.buf.items.len - self.head;
            const needed = dest.len - total_read;
            const to_copy = @min(available, needed);
            @memcpy(dest[total_read .. total_read + to_copy], self.buf.items[self.head .. self.head + to_copy]);
            self.head += to_copy;
            total_read += to_copy;
        }
    }
};
