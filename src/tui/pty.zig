const std = @import("std");
const posix = std.posix;

pub const Pty = struct {
    master_fd: i32,
    pid: usize,

    pub fn spawn(alloc: std.mem.Allocator, parent_envp: [:null]const ?[*:0]const u8) !Pty {
        const master_fd = try posix.posix_openpt(posix.O.RDWR | posix.O.NOCTTY);
        errdefer _ = posix.system.close(master_fd);

        try posix.grantpt(master_fd);
        try posix.unlockpt(master_fd);

        var pts_name_buf: [64]u8 = undefined;
        const pts_name = try posix.ptsname_r(master_fd, &pts_name_buf);

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

        const pid = posix.fork() catch {
            _ = posix.system.close(master_fd);
            return error.ForkFailed;
        };
        if (pid == 0) {
            // --- Child process: only use raw syscalls, never 'try' ---
            _ = posix.system.close(master_fd);

            // Create a new session BEFORE opening the slave (so it becomes the controlling terminal)
            _ = posix.system.setsid();

            // Open slave PTY using raw syscall (no 'try' after fork)
            const slave_rc = posix.system.openat(posix.AT.FDCWD, pts_name.ptr, .{ .ACCMODE = .RDWR }, 0);
            const slave_fd: i32 = @intCast(@as(isize, @bitCast(slave_rc)));
            if (slave_fd < 0) std.process.exit(1);

            // Set controlling terminal
            _ = posix.system.ioctl(slave_fd, posix.T.SCTTY, @as(usize, 0));

            _ = posix.system.dup2(slave_fd, 0);
            _ = posix.system.dup2(slave_fd, 1);
            _ = posix.system.dup2(slave_fd, 2);
            if (slave_fd > 2) _ = posix.system.close(slave_fd);

            const argv = [_:null]?[*:0]const u8{ "/bin/bash", "--login", null };
            _ = posix.system.execve(argv[0].?, &argv, envp.ptr);
            std.process.exit(1);
        }

        return Pty{
            .master_fd = master_fd,
            .pid = @as(usize, @intCast(pid)),
        };
    }

    pub fn deinit(self: *Pty) void {
        _ = posix.system.close(self.master_fd);
        _ = posix.waitpid(@as(posix.pid_t, @intCast(self.pid)), 0);
    }
};
