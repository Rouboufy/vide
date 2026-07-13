const std = @import("std");

pub const Capabilities = struct {
    true_color: bool,
    mouse: bool,
    bracketed_paste: bool,
    nerd_fonts_recommended: bool,
    distinct_modifiers: bool,

    pub fn detect(environ: *const std.process.Environ.Map) Capabilities {
        const term = environ.get("TERM") orelse "";
        const colorterm = environ.get("COLORTERM") orelse "";
        const term_program = environ.get("TERM_PROGRAM") orelse "";
        const dumb = std.mem.eql(u8, term, "dumb") or term.len == 0;
        const linux_console = std.mem.eql(u8, term, "linux");
        const tmux = environ.get("TMUX") != null or std.mem.startsWith(u8, term, "screen");
        const ssh = environ.get("SSH_CONNECTION") != null or environ.get("SSH_TTY") != null;
        const wsl = environ.get("WSL_DISTRO_NAME") != null or environ.get("WSL_INTEROP") != null;
        const modern_program = std.mem.eql(u8, term_program, "WezTerm") or
            std.ascii.eqlIgnoreCase(term_program, "ghostty") or
            std.mem.eql(u8, term_program, "iTerm.app") or
            std.ascii.eqlIgnoreCase(term_program, "kitty") or
            std.ascii.eqlIgnoreCase(term_program, "Alacritty") or
            std.mem.eql(u8, term_program, "Apple_Terminal") or
            environ.get("KONSOLE_VERSION") != null or
            environ.get("VTE_VERSION") != null or
            environ.get("WT_SESSION") != null;
        const true_color = !dumb and !linux_console and
            (std.ascii.eqlIgnoreCase(colorterm, "truecolor") or
                std.ascii.eqlIgnoreCase(colorterm, "24bit") or
                std.mem.indexOf(u8, term, "direct") != null or modern_program);
        return .{
            .true_color = true_color,
            .mouse = !dumb and !linux_console,
            .bracketed_paste = !dumb,
            .nerd_fonts_recommended = !dumb and !linux_console and !tmux,
            .distinct_modifiers = !dumb and !linux_console and !tmux and !ssh and !wsl,
        };
    }
};

test "dumb and Linux console terminals use conservative capabilities" {
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    try env.put("TERM", "dumb");
    var caps = Capabilities.detect(&env);
    try std.testing.expect(!caps.true_color);
    try std.testing.expect(!caps.mouse);
    try std.testing.expect(!caps.bracketed_paste);
    try env.put("TERM", "linux");
    caps = Capabilities.detect(&env);
    try std.testing.expect(!caps.true_color);
    try std.testing.expect(!caps.mouse);
    try std.testing.expect(caps.bracketed_paste);
}

test "known modern terminal profiles enable color without font assumptions" {
    const profiles = [_]struct { key: []const u8, value: []const u8 }{
        .{ .key = "TERM_PROGRAM", .value = "Alacritty" },
        .{ .key = "TERM_PROGRAM", .value = "kitty" },
        .{ .key = "TERM_PROGRAM", .value = "ghostty" },
        .{ .key = "TERM_PROGRAM", .value = "WezTerm" },
        .{ .key = "TERM_PROGRAM", .value = "Apple_Terminal" },
        .{ .key = "TERM_PROGRAM", .value = "iTerm.app" },
        .{ .key = "VTE_VERSION", .value = "7600" },
        .{ .key = "KONSOLE_VERSION", .value = "240800" },
        .{ .key = "WT_SESSION", .value = "test-session" },
    };
    for (profiles) |profile| {
        var env = std.process.Environ.Map.init(std.testing.allocator);
        defer env.deinit();
        try env.put("TERM", "xterm-256color");
        try env.put(profile.key, profile.value);
        const caps = Capabilities.detect(&env);
        try std.testing.expect(caps.true_color);
        try std.testing.expect(caps.mouse);
        try std.testing.expect(caps.bracketed_paste);
    }
}

test "SSH and WSL keep portable modifier fallbacks" {
    {
        var env = std.process.Environ.Map.init(std.testing.allocator);
        defer env.deinit();
        try env.put("TERM", "xterm-256color");
        try env.put("COLORTERM", "truecolor");
        try env.put("SSH_CONNECTION", "127.0.0.1 1 127.0.0.1 2");
        const caps = Capabilities.detect(&env);
        try std.testing.expect(caps.true_color);
        try std.testing.expect(!caps.distinct_modifiers);
    }
    {
        var env = std.process.Environ.Map.init(std.testing.allocator);
        defer env.deinit();
        try env.put("TERM", "xterm-256color");
        try env.put("COLORTERM", "truecolor");
        try env.put("WSL_DISTRO_NAME", "Ubuntu");
        const caps = Capabilities.detect(&env);
        try std.testing.expect(!caps.distinct_modifiers);
    }
}

test "true color survives tmux while modifier assumptions do not" {
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    try env.put("TERM", "xterm-256color");
    try env.put("COLORTERM", "truecolor");
    var caps = Capabilities.detect(&env);
    try std.testing.expect(caps.true_color);
    try std.testing.expect(caps.distinct_modifiers);
    try env.put("TMUX", "/tmp/tmux/default,1,0");
    caps = Capabilities.detect(&env);
    try std.testing.expect(caps.true_color);
    try std.testing.expect(!caps.distinct_modifiers);
    try std.testing.expect(!caps.nerd_fonts_recommended);
}
