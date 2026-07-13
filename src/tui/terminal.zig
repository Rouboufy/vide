const std = @import("std");
const posix = std.posix;
const Capabilities = @import("capabilities.zig").Capabilities;

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
    owns_tty_fd: bool,
    tty_writer: TerminalWriter,
    mouse_enabled: bool,
    paste_enabled: bool,

    pub fn writer(self: *Terminal) *std.Io.Writer {
        return &self.tty_writer.writer;
    }

    pub fn init(capabilities: Capabilities) !Terminal {
        // Prefer the controlling terminal, but stdin is a valid interactive
        // PTY in containers, CI runners, SSH wrappers, and some multiplexers
        // where /dev/tty is unavailable.
        const opened_tty = posix.openat(posix.AT.FDCWD, "/dev/tty", .{ .ACCMODE = .RDWR }, 0) catch null;
        const tty_fd: posix.fd_t = opened_tty orelse 0;
        const output_fd: posix.fd_t = opened_tty orelse 1;

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
            .owns_tty_fd = opened_tty != null,
            .tty_writer = TerminalWriter.init(output_fd),
            .mouse_enabled = capabilities.mouse,
            .paste_enabled = capabilities.bracketed_paste,
        };

        try term.writer().writeAll("\x1b[?1049h\x1b[?25l");
        if (term.mouse_enabled) try term.writer().writeAll("\x1b[?1002h\x1b[?1006h");
        if (term.paste_enabled) try term.writer().writeAll("\x1b[?2004h");

        return term;
    }

    pub fn deinit(self: *Terminal) void {
        // Disable bracketed paste, disable mouse tracking, show cursor, disable alternate screen
        if (self.paste_enabled) self.writer().writeAll("\x1b[?2004l") catch {};
        if (self.mouse_enabled) self.writer().writeAll("\x1b[?1002l\x1b[?1006l") catch {};
        self.writer().writeAll("\x1b[?25h\x1b[?1049l") catch {};

        // Restore original terminal attributes
        posix.tcsetattr(self.tty_fd, .FLUSH, self.orig_termios) catch {};
        if (self.owns_tty_fd) _ = posix.system.close(self.tty_fd);
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
