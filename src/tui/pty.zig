const std = @import("std");
const posix = std.posix;

pub const Pty = struct {
    master_fd: i32,
    pid: usize,

    pub fn spawn(alloc: std.mem.Allocator, parent_envp: [:null]const ?[*:0]const u8) !Pty {
        const master_fd = try posix.openat(posix.AT.FDCWD, "/dev/ptmx", .{ .ACCMODE = .RDWR, .NOCTTY = true }, 0);
        errdefer _ = posix.system.close(master_fd);

        // Unlock the slave PTY - must pass a pointer to int(0), not a null pointer
        var unlock: i32 = 0;
        _ = posix.system.ioctl(master_fd, 0x40045431, @intFromPtr(&unlock));
        var pty_num: u32 = 0;
        _ = posix.system.ioctl(master_fd, 0x80045430, @intFromPtr(&pty_num));

        var pts_name_buf: [64]u8 = undefined;
        const pts_name = try std.fmt.bufPrintZ(&pts_name_buf, "/dev/pts/{d}", .{pty_num});

        // Build envp: inherit parent environment, but filter out terminal-specific vars
        // and override TERM
        var env_count: usize = 0;
        for (parent_envp) |entry| {
            if (entry) |e| {
                const s = std.mem.span(e);
                if (std.mem.startsWith(u8, s, "TERM=")) continue;
                if (std.mem.startsWith(u8, s, "WEZTERM_")) continue;
                if (std.mem.startsWith(u8, s, "ALACRITTY_")) continue;
                if (std.mem.startsWith(u8, s, "KITTY_")) continue;
                if (std.mem.startsWith(u8, s, "TERM_PROGRAM")) continue;
                if (std.mem.startsWith(u8, s, "COLORTERM=")) continue;
                if (std.mem.startsWith(u8, s, "TMUX")) continue;
                if (std.mem.startsWith(u8, s, "PROMPT_COMMAND=")) continue;
                if (std.mem.startsWith(u8, s, "PS1=")) continue;
                if (std.mem.startsWith(u8, s, "BASH_FUNC_")) continue;
                env_count += 1;
            } else break;
        }
        env_count += 1; // for TERM=xterm-256color

        const envp = try alloc.allocSentinel(?[*:0]const u8, env_count, null);
        defer alloc.free(envp);

        var idx: usize = 0;
        for (parent_envp) |entry| {
            if (entry) |e| {
                const s = std.mem.span(e);
                if (std.mem.startsWith(u8, s, "TERM=")) continue;
                if (std.mem.startsWith(u8, s, "WEZTERM_")) continue;
                if (std.mem.startsWith(u8, s, "ALACRITTY_")) continue;
                if (std.mem.startsWith(u8, s, "KITTY_")) continue;
                if (std.mem.startsWith(u8, s, "TERM_PROGRAM")) continue;
                if (std.mem.startsWith(u8, s, "COLORTERM=")) continue;
                if (std.mem.startsWith(u8, s, "TMUX")) continue;
                if (std.mem.startsWith(u8, s, "PROMPT_COMMAND=")) continue;
                if (std.mem.startsWith(u8, s, "PS1=")) continue;
                if (std.mem.startsWith(u8, s, "BASH_FUNC_")) continue;
                envp[idx] = entry;
                idx += 1;
            } else break;
        }
        envp[idx] = "TERM=xterm-256color";
        idx += 1;

        const pid = std.os.linux.fork();
        if (pid == 0) {
            // --- Child process: only use raw syscalls, never 'try' ---
            _ = posix.system.close(master_fd);

            // Create a new session BEFORE opening the slave (so it becomes the controlling terminal)
            _ = std.os.linux.setsid();

            // Open slave PTY using raw syscall (no 'try' after fork)
            const slave_rc = posix.system.openat(posix.AT.FDCWD, pts_name, .{ .ACCMODE = .RDWR }, 0);
            const slave_fd: i32 = @intCast(@as(isize, @bitCast(slave_rc)));
            if (slave_fd < 0) std.process.exit(1);

            // Set controlling terminal
            _ = posix.system.ioctl(0, 0x540E, @as(usize, 0));

            _ = std.os.linux.dup2(slave_fd, 0);
            _ = std.os.linux.dup2(slave_fd, 1);
            _ = std.os.linux.dup2(slave_fd, 2);
            if (slave_fd > 2) _ = posix.system.close(slave_fd);

            const argv = [_:null]?[*:0]const u8{ "/bin/bash", "--login", null };
            _ = std.os.linux.execve(argv[0].?, &argv, envp.ptr);
            std.process.exit(1);
        }

        return Pty{
            .master_fd = master_fd,
            .pid = pid,
        };
    }

    pub fn deinit(self: *Pty) void {
        _ = posix.system.close(self.master_fd);
        var status: u32 = 0;
        _ = std.os.linux.waitpid(@as(i32, @intCast(self.pid)), &status, 0);
    }
};
