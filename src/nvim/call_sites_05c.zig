const std = @import("std");
const transport = @import("async_transport.zig");

pub const DeferredExit = enum { none, zen_handoff, reload };

pub fn succeeded(completion: *const transport.Completion) bool {
    return switch (completion.outcome) {
        .response => |response| response.error_value == .nil,
        .failed => false,
    };
}

pub fn applyTerminalDelta(count: *usize, delta: i2, completion: *const transport.Completion) bool {
    if (!succeeded(completion)) return false;
    if (delta > 0) count.* += 1 else if (count.* > 1) count.* -= 1;
    return true;
}

pub fn applyDeferredExit(target: *DeferredExit, desired: DeferredExit, completion: *const transport.Completion) bool {
    if (!succeeded(completion)) return false;
    target.* = desired;
    return true;
}

test "terminal bookkeeping commits only successful completions" {
    var count: usize = 1;
    var failure: transport.Completion = .{ .id = @enumFromInt(1), .outcome = .{ .failed = .eof } };
    try std.testing.expect(!applyTerminalDelta(&count, 1, &failure));
    try std.testing.expectEqual(@as(usize, 1), count);
    var rpc_error: transport.Completion = .{ .id = @enumFromInt(2), .outcome = .{ .response = .{ .error_value = .{ .string = "bad" }, .result = .nil } } };
    try std.testing.expect(!applyTerminalDelta(&count, 1, &rpc_error));
    var success: transport.Completion = .{ .id = @enumFromInt(3), .outcome = .{ .response = .{ .error_value = .nil, .result = .nil } } };
    try std.testing.expect(applyTerminalDelta(&count, 1, &success));
    try std.testing.expectEqual(@as(usize, 2), count);
    try std.testing.expect(applyTerminalDelta(&count, -1, &success));
    try std.testing.expectEqual(@as(usize, 1), count);
}

test "RPC errors are not successful effects" {
    var error_completion: transport.Completion = .{ .id = @enumFromInt(1), .outcome = .{ .response = .{ .error_value = .{ .integer = 1 }, .result = .nil } } };
    try std.testing.expect(!succeeded(&error_completion));
}

test "deferred exit is published only after save completion" {
    var exit: DeferredExit = .none;
    var failed: transport.Completion = .{ .id = @enumFromInt(1), .outcome = .{ .failed = .shutdown } };
    try std.testing.expect(!applyDeferredExit(&exit, .zen_handoff, &failed));
    try std.testing.expectEqual(.none, exit);
    var success: transport.Completion = .{ .id = @enumFromInt(2), .outcome = .{ .response = .{ .error_value = .nil, .result = .nil } } };
    try std.testing.expect(applyDeferredExit(&exit, .zen_handoff, &success));
    try std.testing.expectEqual(.zen_handoff, exit);
}
