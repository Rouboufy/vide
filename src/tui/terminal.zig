const std = @import("std");
const posix = std.posix;

pub const TerminalWriter = struct {
    writer: std.Io.Writer,
    tty_fd: posix.fd_t,

    pub const vtable = std.Io.Writer.VTable{
        .drain = drain,
    };

    pub fn init(tty_fd: posix.fd_t) TerminalWriter {
        return .{
            .tty_fd = tty_fd,
            .writer = .{
                .vtable = &vtable,
                .buffer = &[_]u8{},
            },
        };
    }

    fn drain(w: *std.Io.Writer, data: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
        const self: *TerminalWriter = @alignCast(@fieldParentPtr("writer", w));
        var total_written: usize = 0;

        // 1. Consume any bytes currently in the writer's buffer.
        if (w.end > 0) {
            var written: usize = 0;
            while (written < w.end) {
                const sub = w.buffer[written..w.end];
                const rc = posix.system.write(self.tty_fd, sub.ptr, sub.len);
                const err = posix.errno(rc);
                switch (err) {
                    .SUCCESS => written += @as(usize, @intCast(rc)),
                    .INTR => continue,
                    else => return error.WriteFailed,
                }
            }
            w.end = 0;
        }

        // 2. Write all slices of `data` except the last one.
        if (data.len > 1) {
            for (data[0 .. data.len - 1]) |slice| {
                var slice_written: usize = 0;
                while (slice_written < slice.len) {
                    const sub = slice[slice_written..];
                    const rc = posix.system.write(self.tty_fd, sub.ptr, sub.len);
                    const err = posix.errno(rc);
                    switch (err) {
                        .SUCCESS => {
                            slice_written += @as(usize, @intCast(rc));
                            total_written += @as(usize, @intCast(rc));
                        },
                        .INTR => continue,
                        else => return error.WriteFailed,
                    }
                }
            }
        }

        // 3. Write the last slice of `data` `splat` times.
        if (data.len > 0) {
            const last_slice = data[data.len - 1];
            var i: usize = 0;
            while (i < splat) : (i += 1) {
                var slice_written: usize = 0;
                while (slice_written < last_slice.len) {
                    const sub = last_slice[slice_written..];
                    const rc = posix.system.write(self.tty_fd, sub.ptr, sub.len);
                    const err = posix.errno(rc);
                    switch (err) {
                        .SUCCESS => {
                            slice_written += @as(usize, @intCast(rc));
                            total_written += @as(usize, @intCast(rc));
                        },
                        .INTR => continue,
                        else => return error.WriteFailed,
                    }
                }
            }
        }

        return total_written;
    }
};

pub const Terminal = struct {
    orig_termios: posix.termios,
    tty_fd: posix.fd_t,
    tty_writer: TerminalWriter,

    pub fn writer(self: *Terminal) *std.Io.Writer {
        return &self.tty_writer.writer;
    }

    pub fn init() !Terminal {
        // Open /dev/tty directly using openat
        const tty_fd = try posix.openat(posix.AT.FDCWD, "/dev/tty", .{ .ACCMODE = .RDWR }, 0);

        const orig = try posix.tcgetattr(tty_fd);
        var raw = orig;

        // Apply raw mode flags: disable echo, canonical input, signals, and control flows
        raw.lflag.ECHO = false;
        raw.lflag.ICANON = false;
        raw.lflag.ISIG = false;
        raw.lflag.IEXTEN = false;
        raw.iflag.IXON = false;
        raw.iflag.ICRNL = false;
        raw.oflag.OPOST = false;
        
        // VMIN and VTIME settings
        raw.cc[@intFromEnum(posix.V.MIN)] = 1;
        raw.cc[@intFromEnum(posix.V.TIME)] = 0;

        try posix.tcsetattr(tty_fd, .FLUSH, raw);

        var term = Terminal{
            .orig_termios = orig,
            .tty_fd = tty_fd,
            .tty_writer = TerminalWriter.init(tty_fd),
        };

        // Enable alternate screen, hide cursor, enable mouse tracking, enable bracketed paste
        try term.writer().writeAll("\x1b[?1049h\x1b[?25l\x1b[?1002h\x1b[?1006h\x1b[?2004h");

        return term;
    }

    pub fn deinit(self: *Terminal) void {
        // Disable bracketed paste, disable mouse tracking, show cursor, disable alternate screen
        self.writer().writeAll("\x1b[?2004l\x1b[?1002l\x1b[?1006l\x1b[?25h\x1b[?1049l") catch {};

        // Restore original terminal attributes
        posix.tcsetattr(self.tty_fd, .FLUSH, self.orig_termios) catch {};
        _ = posix.system.close(self.tty_fd);
    }

    pub fn getSize(self: Terminal) ![2]u16 {
        var ws: posix.winsize = undefined;
        // Query terminal size using system ioctl
        const rc = posix.system.ioctl(self.tty_fd, posix.T.IOCGWINSZ, @intFromPtr(&ws));
        if (posix.errno(rc) != .SUCCESS) {
            return error.IoctlFailed;
        }
        return .{ ws.col, ws.row };
    }
};
