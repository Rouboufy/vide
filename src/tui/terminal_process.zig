const std = @import("std");
const posix = std.posix;

pub const TerminalProcess = struct {
    child: std.process.Child,
    stdin: std.Io.File,
    stdout: std.Io.File,
    master_fd: posix.fd_t,

    pub fn spawn(allocator: std.mem.Allocator) !TerminalProcess {
        // Create a pseudo-terminal (PTY)
        const master_fd = try posix.posix_openpt(posix.O.RDWR | posix.O.NOCTTY);
        errdefer posix.close(master_fd);
        
        try posix.grantpt(master_fd);
        try posix.unlockpt(master_fd);
        
        var pts_name_buf: [256]u8 = undefined;
        const pts_name = try posix.ptsname_r(master_fd, &pts_name_buf);
        
        const slave_fd = try posix.open(pts_name, posix.O.RDWR | posix.O.NOCTTY, 0);
        errdefer posix.close(slave_fd);

        const argv = [_][]const u8{ "/bin/bash", "--login" };
        var child = std.process.Child.init(&argv, allocator);
        
        child.stdin_behavior = .inherit;
        child.stdout_behavior = .inherit;
        child.stderr_behavior = .inherit;
        
        // This is a bit tricky with std.process.Child. 
        // We'll use a simpler approach for the prototype: pipe-based or simple fork.
        // For now, let's use standard pipes to keep it robust within the current architecture.
        
        child.stdin_behavior = .pipe;
        child.stdout_behavior = .pipe;
        child.stderr_behavior = .pipe;

        try child.spawn();

        return TerminalProcess{
            .child = child,
            .stdin = child.stdin.?,
            .stdout = child.stdout.?,
            .master_fd = -1, // Not using PTY for now for simplicity
        };
    }

    pub fn deinit(self: *TerminalProcess) void {
        _ = self.child.kill() catch {};
    }
};
