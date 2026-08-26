const std = @import("std");

pub const Region = enum { chrome, sidebar, editor, drawer, overlay };
pub const ForcedFullRedraw = enum { startup, terminal_resize, terminal_resume, theme_change, recovery };

pub const CompositionDamage = packed struct {
    chrome: bool = false,
    sidebar: bool = false,
    editor: bool = false,
    drawer: bool = false,
    overlay: bool = false,

    pub fn any(self: CompositionDamage) bool {
        return self.chrome or self.sidebar or self.editor or self.drawer or self.overlay;
    }
};

/// Independent reasons for doing work in a frame. Damage is intentionally
/// coarse until retained composition is introduced by Prompt 07.
pub const Invalidations = struct {
    layout: bool = true,
    composition: CompositionDamage = .{ .chrome = true, .sidebar = true, .editor = true, .drawer = true, .overlay = true },
    physical_terminal_size: bool = true,
    editor_nvim_size: bool = true,
    terminal_nvim_size: bool = true,
    cursor: bool = true,
    forced_full_redraw: ?ForcedFullRedraw = .startup,

    pub fn damage(self: *Invalidations, region: Region) void {
        switch (region) {
            .chrome => self.composition.chrome = true,
            .sidebar => self.composition.sidebar = true,
            .editor => self.composition.editor = true,
            .drawer => self.composition.drawer = true,
            .overlay => self.composition.overlay = true,
        }
    }

    pub fn damageAll(self: *Invalidations) void {
        self.composition = .{ .chrome = true, .sidebar = true, .editor = true, .drawer = true, .overlay = true };
    }

    pub fn invalidateLayout(self: *Invalidations) void {
        self.layout = true;
        self.editor_nvim_size = true;
        self.terminal_nvim_size = true;
        self.damageAll();
    }

    pub fn forceFull(self: *Invalidations, cause: ForcedFullRedraw) void {
        self.forced_full_redraw = cause;
        self.damageAll();
        if (cause == .terminal_resize) self.physical_terminal_size = true;
    }

    pub fn consumePaint(self: *Invalidations) CompositionDamage {
        const result = self.composition;
        self.composition = .{};
        self.cursor = false;
        self.forced_full_redraw = null;
        return result;
    }
};

pub const Dimensions = struct { cols: u16, rows: u16 };

/// Returns true exactly when a child UI must receive nvim_ui_try_resize. The
/// caller records `next` only after the request has entered the RPC queue.
pub fn dimensionsChanged(last: ?Dimensions, next: Dimensions) bool {
    if (last) |previous| {
        if (previous.cols == next.cols and previous.rows == next.rows) return false;
    }
    return true;
}

test "ordinary paint and cursor invalidation do not change child dimensions" {
    var last: ?Dimensions = null;
    try std.testing.expect(dimensionsChanged(last, .{ .cols = 80, .rows = 24 }));
    last = .{ .cols = 80, .rows = 24 };
    var invalidations = Invalidations{};
    _ = invalidations.consumePaint();
    invalidations.damage(.chrome);
    invalidations.cursor = true;
    try std.testing.expect(!dimensionsChanged(last, .{ .cols = 80, .rows = 24 }));
    try std.testing.expect(dimensionsChanged(last, .{ .cols = 79, .rows = 24 }));
}

test "sidebar drawer orientation and mode changes resize only affected child UIs" {
    var editor: ?Dimensions = null;
    var terminal: ?Dimensions = null;
    try std.testing.expect(dimensionsChanged(editor, .{ .cols = 90, .rows = 30 }));
    try std.testing.expect(dimensionsChanged(terminal, .{ .cols = 90, .rows = 8 }));
    editor = .{ .cols = 90, .rows = 30 };
    terminal = .{ .cols = 90, .rows = 8 };

    // Sidebar width changes only the editor dimensions.
    try std.testing.expect(dimensionsChanged(editor, .{ .cols = 75, .rows = 30 }));
    try std.testing.expect(!dimensionsChanged(terminal, .{ .cols = 90, .rows = 8 }));
    editor = .{ .cols = 75, .rows = 30 };
    // Moving the drawer to the right changes both child rectangles.
    try std.testing.expect(dimensionsChanged(editor, .{ .cols = 45, .rows = 38 }));
    try std.testing.expect(dimensionsChanged(terminal, .{ .cols = 30, .rows = 37 }));
    editor = .{ .cols = 45, .rows = 38 };
    terminal = .{ .cols = 30, .rows = 37 };
    // A mode transition without a dimension change sends no resize.
    try std.testing.expect(!dimensionsChanged(editor, .{ .cols = 45, .rows = 38 }));
    try std.testing.expect(!dimensionsChanged(terminal, .{ .cols = 30, .rows = 37 }));
}

test "layout paint cursor and sizing domains are independent" {
    var invalidations = Invalidations{};
    _ = invalidations.consumePaint();
    invalidations.layout = false;
    invalidations.editor_nvim_size = false;
    invalidations.terminal_nvim_size = false;
    invalidations.physical_terminal_size = false;
    invalidations.damage(.overlay);
    try std.testing.expect(invalidations.composition.overlay);
    try std.testing.expect(!invalidations.layout);
    try std.testing.expect(!invalidations.editor_nvim_size);
    try std.testing.expect(!invalidations.terminal_nvim_size);
    try std.testing.expect(!invalidations.physical_terminal_size);
}
