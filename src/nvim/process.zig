const std = @import("std");

pub const NvimProcess = struct {
    child: std.process.Child,
    stdin: std.Io.File,
    stdout: std.Io.File,

    pub fn spawn(io: std.Io, allocator: std.mem.Allocator) !NvimProcess {
        _ = allocator;
        const argv = [_][]const u8{ "nvim", "--clean", "--embed", "--headless" };
        var child = try std.process.spawn(io, .{
            .argv = &argv,
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


        try setNonBlock(stdin.handle);
        try setNonBlock(stdout.handle);

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

fn setNonBlock(fd: std.posix.fd_t) !void {
    if (@hasDecl(std.posix, "fcntl")) {
        const flags = try std.posix.fcntl(fd, std.posix.F.GETFL, 0);
        _ = try std.posix.fcntl(fd, std.posix.F.SETFL, flags | @as(u32, @bitCast(std.posix.O{ .NONBLOCK = true })));
    } else {
        const rc = std.posix.system.fcntl(fd, std.posix.F.GETFL, @as(usize, 0));
        const err = std.posix.errno(rc);
        if (err != .SUCCESS) return error.FcntlGetFailed;
        
        const new_flags = @as(usize, @intCast(rc)) | @as(usize, @as(u32, @bitCast(std.posix.O{ .NONBLOCK = true })));
        const set_rc = std.posix.system.fcntl(fd, std.posix.F.SETFL, new_flags);
        const set_err = std.posix.errno(set_rc);
        if (set_err != .SUCCESS) return error.FcntlSetFailed;
    }
}
