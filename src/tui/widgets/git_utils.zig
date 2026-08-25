const std = @import("std");
const metrics = @import("../../metrics.zig");

pub fn runGitCommand(allocator: std.mem.Allocator, io: std.Io, argv: []const []const u8) ![]const u8 {
    var timer = metrics.ScopedTimer.start(&metrics.global, &metrics.global.blocking_io_git);
    defer timer.stop();
    var child = try std.process.spawn(io, .{
        .argv = argv,
        .stdout = .pipe,
        .stderr = .ignore,
    });
    errdefer {
        if (child.id != null) {
            child.kill(io);
        }
    }

    var stdout = std.array_list.Managed(u8).init(allocator);
    errdefer stdout.deinit();

    if (child.stdout) |out| {
        while (true) {
            var chunk: [1024]u8 = undefined;
            const len = std.posix.read(out.handle, &chunk) catch 0;
            if (len == 0) break;
            try stdout.appendSlice(chunk[0..len]);
        }
    }

    _ = try child.wait(io);
    return try stdout.toOwnedSlice();
}
