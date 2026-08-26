//! Bounded poll-driven RPC transport introduced by Prompt 05B.
const std = @import("std");
const msgpack = @import("msgpack.zig");
const incremental = @import("incremental_decoder.zig");

pub const max_outbound_messages = 64;
pub const max_outbound_bytes = 4 * 1024 * 1024;
pub const protocol_reply_reserved_messages = 8;
pub const protocol_reply_reserved_bytes = 256 * 1024;
pub const max_pending_requests = 64;
pub const max_completions = 64;

pub const RequestId = enum(u32) { _ };
pub const Priority = enum { normal, protocol_reply };

const Envelope = struct {
    bytes: []u8,
    offset: usize = 0,
    request_id: ?RequestId,
    priority: Priority,
    fn deinit(self: *Envelope, allocator: std.mem.Allocator) void {
        allocator.free(self.bytes);
        self.* = undefined;
    }
};

const Pending = struct {
    id: RequestId,
    deadline_ns: ?i128,
};

pub const FailureReason = enum { eof, shutdown, timeout, canceled, child_failed };

pub const Completion = struct {
    id: RequestId,
    outcome: union(enum) {
        response: struct { error_value: msgpack.Value, result: msgpack.Value },
        failed: FailureReason,
    },
    pub fn deinit(self: *Completion, allocator: std.mem.Allocator) void {
        switch (self.outcome) {
            .response => |response| {
                msgpack.freeValue(response.error_value, allocator);
                msgpack.freeValue(response.result, allocator);
            },
            .failed => {},
        }
        self.* = undefined;
    }
};

pub const Inbound = union(enum) {
    notification: msgpack.Value,
    request: msgpack.Value,
    unknown_response: msgpack.Value,
    response_completed: RequestId,
    pub fn deinit(self: *Inbound, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .notification, .request, .unknown_response => |value| msgpack.freeValue(value, allocator),
            .response_completed => {},
        }
        self.* = undefined;
    }
};

pub const Transport = struct {
    allocator: std.mem.Allocator,
    decoder: incremental.Decoder,
    outbound: [max_outbound_messages]?Envelope = [_]?Envelope{null} ** max_outbound_messages,
    outbound_len: usize = 0,
    outbound_bytes: usize = 0,
    pending: [max_pending_requests]?Pending = [_]?Pending{null} ** max_pending_requests,
    pending_len: usize = 0,
    completions: [max_completions]?Completion = [_]?Completion{null} ** max_completions,
    completion_len: usize = 0,
    next_request_id: u32 = 1,
    accepting: bool = true,
    eof: bool = false,
    eof_drained: bool = false,
    terminal_failure: FailureReason = .eof,

    pub fn init(allocator: std.mem.Allocator) Transport {
        return .{ .allocator = allocator, .decoder = .init(allocator) };
    }

    pub fn deinit(self: *Transport) void {
        self.failAllPending(.shutdown);
        while (self.outbound_len != 0) {
            var envelope = self.removeOutbound(0);
            envelope.deinit(self.allocator);
        }
        while (self.takeCompletion()) |value| {
            var completion = value;
            completion.deinit(self.allocator);
        }
        self.decoder.deinit();
        self.* = undefined;
    }

    pub fn wantsWrite(self: *const Transport) bool {
        return self.outbound_len != 0;
    }
    pub fn queuedBytes(self: *const Transport) usize {
        return self.outbound_bytes;
    }
    pub fn pendingCount(self: *const Transport) usize {
        return self.pending_len;
    }
    pub fn isEofDrained(self: *const Transport) bool {
        return self.eof_drained;
    }

    pub fn queueNotification(self: *Transport, method: []const u8, params: []const msgpack.Value) !void {
        var items = [_]msgpack.Value{ .{ .integer = 2 }, .{ .string = method }, .{ .array = @constCast(params) } };
        try self.queueEncoded(.{ .array = &items }, null, .normal);
    }

    pub fn queueReply(self: *Transport, id: RequestId, error_value: msgpack.Value, result: msgpack.Value) !void {
        var items = [_]msgpack.Value{ .{ .integer = 1 }, .{ .integer = @intFromEnum(id) }, error_value, result };
        try self.queueEncoded(.{ .array = &items }, null, .protocol_reply);
    }

    pub fn queueRequest(self: *Transport, method: []const u8, params: []const msgpack.Value) !RequestId {
        return self.queueRequestWithDeadline(method, params, null);
    }

    /// The deadline is an absolute value from the caller's monotonic clock.
    /// Null means that the request has no transport-enforced deadline.
    pub fn queueRequestWithDeadline(self: *Transport, method: []const u8, params: []const msgpack.Value, deadline_ns: ?i128) !RequestId {
        if (self.pending_len + self.completion_len == max_pending_requests) return error.PendingFull;
        if (self.next_request_id == 0) return error.RequestIdExhausted;
        const id: RequestId = @enumFromInt(self.next_request_id);
        var items = [_]msgpack.Value{ .{ .integer = 0 }, .{ .integer = self.next_request_id }, .{ .string = method }, .{ .array = @constCast(params) } };
        try self.queueEncoded(.{ .array = &items }, id, .normal);
        self.pending[self.pending_len] = .{ .id = id, .deadline_ns = deadline_ns };
        self.pending_len += 1;
        self.next_request_id +%= 1;
        return id;
    }

    fn queueEncoded(self: *Transport, value: msgpack.Value, request_id: ?RequestId, priority: Priority) !void {
        if (!self.accepting) return error.Closed;
        const message_limit: usize = if (priority == .protocol_reply) max_outbound_messages else max_outbound_messages - protocol_reply_reserved_messages;
        if (self.outbound_len >= message_limit) return error.OutboundFull;
        var writer = std.Io.Writer.Allocating.init(self.allocator);
        defer writer.deinit();
        msgpack.encode(&writer.writer, value) catch |err| switch (err) {
            error.WriteFailed => return error.OutOfMemory,
        };
        const byte_limit: usize = if (priority == .protocol_reply) max_outbound_bytes else max_outbound_bytes - protocol_reply_reserved_bytes;
        if (self.outbound_bytes > byte_limit or writer.written().len > byte_limit - self.outbound_bytes) return error.OutboundBytesFull;
        const owned = try self.allocator.dupe(u8, writer.written());
        self.outbound[self.outbound_len] = .{ .bytes = owned, .request_id = request_id, .priority = priority };
        self.outbound_len += 1;
        self.outbound_bytes += owned.len;
    }

    /// Writer returns bytes written, zero for would-block. FIFO ordering is
    /// preserved across notifications, requests, and protocol replies.
    pub fn flushOne(self: *Transport, context: anytype, comptime writeFn: anytype) !bool {
        if (self.outbound_len == 0) return false;
        const envelope = &self.outbound[0].?;
        const written = try writeFn(context, envelope.bytes[envelope.offset..]);
        if (written > envelope.bytes.len - envelope.offset) return error.InvalidWriteCount;
        envelope.offset += written;
        if (envelope.offset != envelope.bytes.len) return written != 0;
        var completed = self.removeOutbound(0);
        completed.deinit(self.allocator);
        return true;
    }

    pub fn feed(self: *Transport, bytes: []const u8) !void {
        try self.decoder.feed(bytes);
    }
    pub fn finish(self: *Transport) void {
        self.finishWithReason(.eof);
    }

    /// Stop admission, preserve already-buffered complete frames, and fail any
    /// still-unresolved requests exactly once after that input is drained.
    pub fn finishWithReason(self: *Transport, reason: FailureReason) void {
        if (self.eof) {
            if (!self.eof_drained and reason != .eof) self.terminal_failure = reason;
            return;
        }
        self.eof = true;
        self.accepting = false;
        self.terminal_failure = reason;
        self.decoder.finish();
    }

    pub fn shutdown(self: *Transport) void {
        self.finishWithReason(.shutdown);
        self.dropOutbound();
        self.failAllPending(.shutdown);
        self.eof_drained = true;
    }

    pub fn nextInbound(self: *Transport) !?Inbound {
        const value = self.decoder.next() catch |err| {
            if (self.eof) {
                self.failAllPending(self.terminal_failure);
                self.eof_drained = true;
            }
            return err;
        } orelse {
            if (self.eof) {
                self.failAllPending(self.terminal_failure);
                self.eof_drained = true;
            }
            return null;
        };
        errdefer msgpack.freeValue(value, self.allocator);
        if (value != .array or value.array.len < 3 or value.array[0] != .integer) return .{ .notification = value };
        if (value.array[0].integer != 1 or value.array.len < 4 or value.array[1] != .integer) return if (value.array[0].integer == 0) .{ .request = value } else .{ .notification = value };
        const raw_id = value.array[1].integer;
        if (raw_id <= 0 or raw_id > std.math.maxInt(u32)) return .{ .unknown_response = value };
        const id: RequestId = @enumFromInt(@as(u32, @intCast(raw_id)));
        const pending_index = self.findPending(id) orelse return .{ .unknown_response = value };
        if (self.completion_len == max_completions) return error.CompletionFull;
        const error_value = value.array[2];
        const result = value.array[3];
        for (value.array, 0..) |item, index| if (index != 2 and index != 3) msgpack.freeValue(item, self.allocator);
        self.allocator.free(value.array);
        self.removePending(pending_index);
        self.completions[self.completion_len] = .{ .id = id, .outcome = .{ .response = .{ .error_value = error_value, .result = result } } };
        self.completion_len += 1;
        return .{ .response_completed = id };
    }

    pub fn takeCompletion(self: *Transport) ?Completion {
        if (self.completion_len == 0) return null;
        const result = self.completions[0].?;
        std.mem.copyForwards(?Completion, self.completions[0 .. self.completion_len - 1], self.completions[1..self.completion_len]);
        self.completion_len -= 1;
        self.completions[self.completion_len] = null;
        return result;
    }

    pub fn cancel(self: *Transport, id: RequestId) bool {
        const index = self.findPending(id) orelse return false;
        self.removePending(index);
        var outbound_index: usize = 0;
        while (outbound_index < self.outbound_len) : (outbound_index += 1) {
            if (self.outbound[outbound_index].?.request_id != id or self.outbound[outbound_index].?.offset != 0) continue;
            var envelope = self.removeOutbound(outbound_index);
            envelope.deinit(self.allocator);
            break;
        }
        self.pushFailure(id, .canceled);
        return true;
    }

    /// Expire all deadlines at or before `now_ns`. Returns the number expired.
    pub fn expire(self: *Transport, now_ns: i128) usize {
        var expired: usize = 0;
        var index: usize = 0;
        while (index < self.pending_len) {
            const entry = self.pending[index].?;
            if (entry.deadline_ns == null or entry.deadline_ns.? > now_ns) {
                index += 1;
                continue;
            }
            self.removePending(index);
            self.removeUnsentEnvelope(entry.id);
            self.pushFailure(entry.id, .timeout);
            expired += 1;
        }
        return expired;
    }

    fn findPending(self: *Transport, id: RequestId) ?usize {
        for (self.pending[0..self.pending_len], 0..) |entry, index| if (entry.?.id == id) return index;
        return null;
    }
    fn removePending(self: *Transport, index: usize) void {
        std.mem.copyForwards(?Pending, self.pending[index .. self.pending_len - 1], self.pending[index + 1 .. self.pending_len]);
        self.pending_len -= 1;
        self.pending[self.pending_len] = null;
    }
    fn removeOutbound(self: *Transport, index: usize) Envelope {
        const result = self.outbound[index].?;
        std.mem.copyForwards(?Envelope, self.outbound[index .. self.outbound_len - 1], self.outbound[index + 1 .. self.outbound_len]);
        self.outbound_len -= 1;
        self.outbound[self.outbound_len] = null;
        self.outbound_bytes -= result.bytes.len;
        return result;
    }
    fn removeUnsentEnvelope(self: *Transport, id: RequestId) void {
        var index: usize = 0;
        while (index < self.outbound_len) : (index += 1) {
            const envelope = self.outbound[index].?;
            if (envelope.request_id != id or envelope.offset != 0) continue;
            var removed = self.removeOutbound(index);
            removed.deinit(self.allocator);
            return;
        }
    }
    fn dropOutbound(self: *Transport) void {
        while (self.outbound_len != 0) {
            var envelope = self.removeOutbound(0);
            envelope.deinit(self.allocator);
        }
    }
    fn pushFailure(self: *Transport, id: RequestId, reason: FailureReason) void {
        std.debug.assert(self.completion_len < max_completions);
        self.completions[self.completion_len] = .{ .id = id, .outcome = .{ .failed = reason } };
        self.completion_len += 1;
    }
    fn failAllPending(self: *Transport, reason: FailureReason) void {
        for (self.pending[0..self.pending_len]) |entry| {
            self.pushFailure(entry.?.id, reason);
        }
        self.pending = [_]?Pending{null} ** max_pending_requests;
        self.pending_len = 0;
    }
};

fn appendWriter(output: *std.array_list.Managed(u8), bytes: []const u8) !usize {
    try output.appendSlice(bytes);
    return bytes.len;
}

test "partial writes retain offsets and strict FIFO ordering" {
    var transport = Transport.init(std.testing.allocator);
    defer transport.deinit();
    try transport.queueNotification("one", &.{});
    try transport.queueNotification("two", &.{});
    var output = std.array_list.Managed(u8).init(std.testing.allocator);
    defer output.deinit();
    const Limited = struct {
        fn write(out: *std.array_list.Managed(u8), bytes: []const u8) !usize {
            const count = @min(bytes.len, 2);
            try out.appendSlice(bytes[0..count]);
            return count;
        }
    };
    while (transport.wantsWrite()) _ = try transport.flushOne(&output, Limited.write);
    var decoder = incremental.Decoder.init(std.testing.allocator);
    defer decoder.deinit();
    try decoder.feed(output.items);
    const first = (try decoder.next()).?;
    defer msgpack.freeValue(first, std.testing.allocator);
    const second = (try decoder.next()).?;
    defer msgpack.freeValue(second, std.testing.allocator);
    try std.testing.expectEqualStrings("one", first.array[1].string);
    try std.testing.expectEqualStrings("two", second.array[1].string);
}

test "request IDs pending completion unknown duplicate cancellation and EOF" {
    var transport = Transport.init(std.testing.allocator);
    defer transport.deinit();
    const id = try transport.queueRequest("x", &.{});
    try std.testing.expectEqual(@as(usize, 1), transport.pendingCount());
    var response_items = [_]msgpack.Value{ .{ .integer = 1 }, .{ .integer = @intFromEnum(id) }, .nil, .{ .integer = 9 } };
    var writer = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer writer.deinit();
    try msgpack.encode(&writer.writer, .{ .array = &response_items });
    try transport.feed(writer.written());
    var resolved = (try transport.nextInbound()).?;
    defer resolved.deinit(std.testing.allocator);
    try std.testing.expectEqual(id, resolved.response_completed);
    var completion = transport.takeCompletion().?;
    defer completion.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(i64, 9), completion.outcome.response.result.integer);
    try transport.feed(writer.written());
    var duplicate = (try transport.nextInbound()).?;
    defer duplicate.deinit(std.testing.allocator);
    try std.testing.expect(duplicate == .unknown_response);
    const cancel_id = try transport.queueRequest("y", &.{});
    try std.testing.expect(transport.cancel(cancel_id));
    transport.finish();
    try std.testing.expectEqual(@as(usize, 0), transport.pendingCount());
}

test "bounded admission and allocation failures retain ownership" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, struct {
        fn run(allocator: std.mem.Allocator) !void {
            var transport = Transport.init(allocator);
            defer transport.deinit();
            try transport.queueNotification("method", &.{.{ .string = "payload" }});
        }
    }.run, .{});
    var transport = Transport.init(std.testing.allocator);
    defer transport.deinit();
    for (0..max_outbound_messages - protocol_reply_reserved_messages) |_| try transport.queueNotification("x", &.{});
    try std.testing.expectError(error.OutboundFull, transport.queueNotification("overflow", &.{}));
}

test "EOF fails every pending request exactly once" {
    var transport = Transport.init(std.testing.allocator);
    defer transport.deinit();
    const first = try transport.queueRequest("one", &.{});
    const second = try transport.queueRequest("two", &.{});
    transport.finish();
    try std.testing.expect(try transport.nextInbound() == null);
    try std.testing.expectEqual(@as(usize, 0), transport.pendingCount());
    var completion_one = transport.takeCompletion().?;
    defer completion_one.deinit(std.testing.allocator);
    var completion_two = transport.takeCompletion().?;
    defer completion_two.deinit(std.testing.allocator);
    try std.testing.expectEqual(first, completion_one.id);
    try std.testing.expectEqual(second, completion_two.id);
    try std.testing.expectEqual(.eof, completion_one.outcome.failed);
    try std.testing.expectEqual(.eof, completion_two.outcome.failed);
    try std.testing.expect(transport.takeCompletion() == null);
}

test "request ID exhaustion and dual transports are independent" {
    var editor = Transport.init(std.testing.allocator);
    defer editor.deinit();
    var terminal = Transport.init(std.testing.allocator);
    defer terminal.deinit();
    editor.next_request_id = std.math.maxInt(u32);
    const last = try editor.queueRequest("last", &.{});
    try std.testing.expectEqual(@as(u32, std.math.maxInt(u32)), @intFromEnum(last));
    try std.testing.expectError(error.RequestIdExhausted, editor.queueRequest("wrapped", &.{}));
    const terminal_first = try terminal.queueRequest("first", &.{});
    try std.testing.expectEqual(@as(u32, 1), @intFromEnum(terminal_first));
    try std.testing.expectEqual(@as(usize, 1), editor.pendingCount());
    try std.testing.expectEqual(@as(usize, 1), terminal.pendingCount());
}

test "cancel removes an unsent request envelope" {
    var transport = Transport.init(std.testing.allocator);
    defer transport.deinit();
    const id = try transport.queueRequest("cancel", &.{});
    try std.testing.expect(transport.wantsWrite());
    try std.testing.expect(transport.cancel(id));
    try std.testing.expect(!transport.wantsWrite());
    try std.testing.expectEqual(@as(usize, 0), transport.pendingCount());
    var completion = transport.takeCompletion().?;
    defer completion.deinit(std.testing.allocator);
    try std.testing.expectEqual(.canceled, completion.outcome.failed);
    try std.testing.expect(!transport.cancel(id));
}

test "cancel never removes a partially written envelope" {
    var transport = Transport.init(std.testing.allocator);
    defer transport.deinit();
    const id = try transport.queueRequest("partial", &.{});
    const One = struct {
        fn write(_: void, bytes: []const u8) !usize {
            return @min(bytes.len, 1);
        }
    };
    _ = try transport.flushOne({}, One.write);
    try std.testing.expect(transport.cancel(id));
    try std.testing.expect(transport.wantsWrite());
    try std.testing.expectEqual(@as(usize, 0), transport.pendingCount());
    var completion = transport.takeCompletion().?;
    defer completion.deinit(std.testing.allocator);
    try std.testing.expectEqual(.canceled, completion.outcome.failed);
}

test "deadlines remove unsent requests and retain partially written envelopes" {
    var transport = Transport.init(std.testing.allocator);
    defer transport.deinit();
    const unsent = try transport.queueRequestWithDeadline("unsent", &.{}, 10);
    try std.testing.expectEqual(@as(usize, 0), transport.expire(9));
    try std.testing.expectEqual(@as(usize, 1), transport.expire(10));
    try std.testing.expect(!transport.wantsWrite());
    var unsent_completion = transport.takeCompletion().?;
    defer unsent_completion.deinit(std.testing.allocator);
    try std.testing.expectEqual(unsent, unsent_completion.id);
    try std.testing.expectEqual(.timeout, unsent_completion.outcome.failed);

    const partial = try transport.queueRequestWithDeadline("partial", &.{}, 20);
    const One = struct {
        fn write(_: void, bytes: []const u8) !usize {
            return @min(bytes.len, 1);
        }
    };
    _ = try transport.flushOne({}, One.write);
    try std.testing.expectEqual(@as(usize, 1), transport.expire(20));
    try std.testing.expect(transport.wantsWrite());
    var partial_completion = transport.takeCompletion().?;
    defer partial_completion.deinit(std.testing.allocator);
    try std.testing.expectEqual(partial, partial_completion.id);
    try std.testing.expectEqual(.timeout, partial_completion.outcome.failed);
}

test "terminal failure drains complete responses before failing unresolved requests" {
    var transport = Transport.init(std.testing.allocator);
    defer transport.deinit();
    const resolved_id = try transport.queueRequest("resolved", &.{});
    const failed_id = try transport.queueRequest("failed", &.{});
    var response = [_]msgpack.Value{ .{ .integer = 1 }, .{ .integer = @intFromEnum(resolved_id) }, .nil, .{ .integer = 7 } };
    var encoded = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer encoded.deinit();
    try msgpack.encode(&encoded.writer, .{ .array = &response });
    try transport.feed(encoded.written());
    transport.finishWithReason(.child_failed);
    var inbound = (try transport.nextInbound()).?;
    defer inbound.deinit(std.testing.allocator);
    try std.testing.expectEqual(resolved_id, inbound.response_completed);
    try std.testing.expect(try transport.nextInbound() == null);
    var resolved = transport.takeCompletion().?;
    defer resolved.deinit(std.testing.allocator);
    var failed = transport.takeCompletion().?;
    defer failed.deinit(std.testing.allocator);
    try std.testing.expectEqual(resolved_id, resolved.id);
    try std.testing.expectEqual(failed_id, failed.id);
    try std.testing.expectEqual(.child_failed, failed.outcome.failed);
}

test "cancellation completion remains ordered before a later response" {
    var transport = Transport.init(std.testing.allocator);
    defer transport.deinit();
    const canceled_id = try transport.queueRequest("canceled", &.{});
    const response_id = try transport.queueRequest("response", &.{});
    try std.testing.expect(transport.cancel(canceled_id));
    var response = [_]msgpack.Value{ .{ .integer = 1 }, .{ .integer = @intFromEnum(response_id) }, .nil, .{ .integer = 11 } };
    var encoded = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer encoded.deinit();
    try msgpack.encode(&encoded.writer, .{ .array = &response });
    try transport.feed(encoded.written());
    var inbound = (try transport.nextInbound()).?;
    defer inbound.deinit(std.testing.allocator);
    var canceled = transport.takeCompletion().?;
    defer canceled.deinit(std.testing.allocator);
    var resolved = transport.takeCompletion().?;
    defer resolved.deinit(std.testing.allocator);
    try std.testing.expectEqual(canceled_id, canceled.id);
    try std.testing.expectEqual(.canceled, canceled.outcome.failed);
    try std.testing.expectEqual(response_id, resolved.id);
    try std.testing.expectEqual(@as(i64, 11), resolved.outcome.response.result.integer);
}

test "shutdown disposes queued traffic and completes every pending state once" {
    var transport = Transport.init(std.testing.allocator);
    defer transport.deinit();
    const resolved_id = try transport.queueRequest("resolved", &.{});
    var response = [_]msgpack.Value{ .{ .integer = 1 }, .{ .integer = @intFromEnum(resolved_id) }, .nil, .{ .integer = 8 } };
    var encoded = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer encoded.deinit();
    try msgpack.encode(&encoded.writer, .{ .array = &response });
    try transport.feed(encoded.written());
    var inbound = (try transport.nextInbound()).?;
    defer inbound.deinit(std.testing.allocator);
    try transport.queueNotification("notification", &.{});
    const first = try transport.queueRequest("first", &.{});
    const second = try transport.queueRequest("second", &.{});
    const One = struct {
        fn write(_: void, bytes: []const u8) !usize {
            return @min(bytes.len, 1);
        }
    };
    _ = try transport.flushOne({}, One.write);
    transport.shutdown();
    try std.testing.expect(!transport.wantsWrite());
    try std.testing.expectEqual(@as(usize, 0), transport.queuedBytes());
    try std.testing.expectEqual(@as(usize, 0), transport.pendingCount());
    try std.testing.expectError(error.Closed, transport.queueNotification("closed", &.{}));
    var resolved = transport.takeCompletion().?;
    defer resolved.deinit(std.testing.allocator);
    var one = transport.takeCompletion().?;
    defer one.deinit(std.testing.allocator);
    var two = transport.takeCompletion().?;
    defer two.deinit(std.testing.allocator);
    try std.testing.expectEqual(resolved_id, resolved.id);
    try std.testing.expectEqual(@as(i64, 8), resolved.outcome.response.result.integer);
    try std.testing.expectEqual(first, one.id);
    try std.testing.expectEqual(second, two.id);
    try std.testing.expectEqual(.shutdown, one.outcome.failed);
    try std.testing.expectEqual(.shutdown, two.outcome.failed);
    try std.testing.expect(transport.takeCompletion() == null);
}

test "deadline cancellation and shutdown are allocation-failure safe" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, struct {
        fn run(allocator: std.mem.Allocator) !void {
            var transport = Transport.init(allocator);
            defer transport.deinit();
            const id = try transport.queueRequestWithDeadline("bounded", &.{.{ .string = "payload" }}, 1);
            try std.testing.expectEqual(@as(usize, 1), transport.expire(1));
            try std.testing.expect(!transport.cancel(id));
            transport.shutdown();
        }
    }.run, .{});
}

test "protocol reply reserve survives saturated normal traffic" {
    var transport = Transport.init(std.testing.allocator);
    defer transport.deinit();
    for (0..max_outbound_messages - protocol_reply_reserved_messages) |_| try transport.queueNotification("normal", &.{});
    try std.testing.expectError(error.OutboundFull, transport.queueNotification("rejected", &.{}));
    for (0..protocol_reply_reserved_messages) |index| try transport.queueReply(@enumFromInt(index + 1), .nil, .nil);
    try std.testing.expectError(error.OutboundFull, transport.queueReply(@enumFromInt(99), .nil, .nil));
}

test "EOF remains logically open until more than 250 buffered frames and response drain" {
    var transport = Transport.init(std.testing.allocator);
    defer transport.deinit();
    const request_id = try transport.queueRequest("pending", &.{});
    var encoded = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer encoded.deinit();
    for (0..300) |_| {
        var notification = [_]msgpack.Value{ .{ .integer = 2 }, .{ .string = "tick" }, .{ .array = &.{} } };
        try msgpack.encode(&encoded.writer, .{ .array = &notification });
    }
    var response = [_]msgpack.Value{ .{ .integer = 1 }, .{ .integer = @intFromEnum(request_id) }, .nil, .{ .integer = 42 } };
    try msgpack.encode(&encoded.writer, .{ .array = &response });
    try transport.feed(encoded.written());
    transport.finish();
    for (0..250) |_| {
        var inbound = (try transport.nextInbound()).?;
        inbound.deinit(std.testing.allocator);
    }
    try std.testing.expect(!transport.isEofDrained());
    try std.testing.expectEqual(@as(usize, 1), transport.pendingCount());
    while (!transport.isEofDrained()) {
        if (try transport.nextInbound()) |value| {
            var inbound = value;
            inbound.deinit(std.testing.allocator);
        }
    }
    try std.testing.expectEqual(@as(usize, 0), transport.pendingCount());
    var completion = transport.takeCompletion().?;
    defer completion.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(i64, 42), completion.outcome.response.result.integer);
}
