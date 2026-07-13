const std = @import("std");

pub const NvimProcess = struct {
    child: std.process.Child,
    stdin: std.Io.File,
    stdout: std.Io.File,

    pub fn spawn(io: std.Io, environ_map: *const std.process.Environ.Map) !NvimProcess {
        const argv = [_][]const u8{ "nvim", "--clean", "--embed", "--headless" };
        var child = try std.process.spawn(io, .{
            .argv = &argv,
            .environ_map = environ_map,
            .stdin = .pipe,
            .stdout = .pipe,
            .stderr = .inherit,
        });
        errdefer {
            if (child.id != null) {
                child.kill(io);
            }
        }

        const stdin = child.stdin orelse return error.StdinPipeFailed;
        const stdout = child.stdout orelse return error.StdoutPipeFailed;

        const flags_in_val = std.posix.system.fcntl(stdin.handle, std.posix.F.GETFL, @as(usize, 0));
        const flags_in = @as(usize, @intCast(flags_in_val));
        _ = std.posix.system.fcntl(stdin.handle, std.posix.F.SETFL, flags_in | @as(usize, @as(u32, @bitCast(std.posix.O{ .NONBLOCK = true }))));

        const flags_out_val = std.posix.system.fcntl(stdout.handle, std.posix.F.GETFL, @as(usize, 0));
        const flags_out = @as(usize, @intCast(flags_out_val));
        _ = std.posix.system.fcntl(stdout.handle, std.posix.F.SETFL, flags_out | @as(usize, @as(u32, @bitCast(std.posix.O{ .NONBLOCK = true }))));

        return NvimProcess{
            .child = child,
            .stdin = stdin,
            .stdout = stdout,
        };
    }

    pub fn deinit(self: *NvimProcess, io: std.Io) void {
        if (self.child.id != null) {
            self.child.kill(io);
        }
    }
};
