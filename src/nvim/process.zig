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
            .stderr = .ignore,
        });
        errdefer {
            if (child.id != null) {
                child.kill(io);
            }
        }

        const stdin = child.stdin orelse return error.StdinPipeFailed;
        const stdout = child.stdout orelse return error.StdoutPipeFailed;

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
