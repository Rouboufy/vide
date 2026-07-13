const std = @import("std");
const nvim = @import("../nvim/msgpack.zig");

pub const Color = @import("renderer.zig").Color;

pub const Theme = struct {
    bg_editor: Color = Color{ .rgb = .{ .r = 30, .g = 30, .b = 30 } },
    bg_sidebar: Color = Color{ .rgb = .{ .r = 37, .g = 37, .b = 38 } },
    bg_tab_active: Color = Color{ .rgb = .{ .r = 30, .g = 30, .b = 30 } },
    bg_tab_inactive: Color = Color{ .rgb = .{ .r = 45, .g = 45, .b = 45 } },
    bg_statusbar: Color = Color{ .rgb = .{ .r = 0, .g = 122, .b = 204 } },
    fg_statusbar: Color = Color{ .rgb = .{ .r = 255, .g = 255, .b = 255 } },
    bg_terminal: Color = Color{ .rgb = .{ .r = 30, .g = 30, .b = 30 } },
    bg_accent: Color = Color{ .rgb = .{ .r = 9, .g = 71, .b = 113 } },
    fg_primary: Color = Color{ .rgb = .{ .r = 212, .g = 212, .b = 212 } },
    fg_secondary: Color = Color{ .rgb = .{ .r = 133, .g = 133, .b = 133 } },
    fg_accent: Color = Color{ .rgb = .{ .r = 255, .g = 255, .b = 255 } },
    border_color: Color = Color{ .rgb = .{ .r = 60, .g = 60, .b = 60 } },

    pub fn parseHexColor(hex: []const u8) ?Color {
        if (hex.len != 7 or hex[0] != '#') return null;
        const r = std.fmt.parseInt(u8, hex[1..3], 16) catch return null;
        const g = std.fmt.parseInt(u8, hex[3..5], 16) catch return null;
        const b = std.fmt.parseInt(u8, hex[5..7], 16) catch return null;
        return Color{ .rgb = .{ .r = r, .g = g, .b = b } };
    }

    pub fn updateFromConfig(self: *Theme, map: []nvim.Value.MapEntry) void {
        for (map) |kv| {
            if (kv.key == .string and kv.value == .string) {
                const k = kv.key.string;
                const v = kv.value.string;
                if (parseHexColor(v)) |c| {
                    if (std.mem.eql(u8, k, "bg_editor")) self.bg_editor = c;
                    if (std.mem.eql(u8, k, "bg_sidebar")) self.bg_sidebar = c;
                    if (std.mem.eql(u8, k, "bg_tab_active")) self.bg_tab_active = c;
                    if (std.mem.eql(u8, k, "bg_tab_inactive")) self.bg_tab_inactive = c;
                    if (std.mem.eql(u8, k, "bg_statusbar")) self.bg_statusbar = c;
                    if (std.mem.eql(u8, k, "fg_statusbar")) self.fg_statusbar = c;
                    if (std.mem.eql(u8, k, "bg_terminal")) self.bg_terminal = c;
                    if (std.mem.eql(u8, k, "bg_accent")) self.bg_accent = c;
                    if (std.mem.eql(u8, k, "fg_primary")) self.fg_primary = c;
                    if (std.mem.eql(u8, k, "fg_secondary")) self.fg_secondary = c;
                    if (std.mem.eql(u8, k, "fg_accent")) self.fg_accent = c;
                    if (std.mem.eql(u8, k, "border_color")) self.border_color = c;
                }
            }
        }
    }
};

fn linearChannel(value: u8) f32 {
    const channel = @as(f32, @floatFromInt(value)) / 255.0;
    return if (channel <= 0.04045) channel / 12.92 else std.math.pow(f32, (channel + 0.055) / 1.055, 2.4);
}

fn luminance(color: Color) f32 {
    return switch (color) {
        .rgb => |rgb| 0.2126 * linearChannel(rgb.r) + 0.7152 * linearChannel(rgb.g) + 0.0722 * linearChannel(rgb.b),
        else => 0,
    };
}

fn contrastRatio(a: Color, b: Color) f32 {
    const a_lum = luminance(a);
    const b_lum = luminance(b);
    const lighter = @max(a_lum, b_lum);
    const darker = @min(a_lum, b_lum);
    return (lighter + 0.05) / (darker + 0.05);
}

test "default theme keeps text and focus contrast readable" {
    const t = Theme{};
    try std.testing.expect(contrastRatio(t.fg_primary, t.bg_editor) >= 7.0);
    try std.testing.expect(contrastRatio(t.fg_secondary, t.bg_sidebar) >= 4.0);
    try std.testing.expect(contrastRatio(t.fg_statusbar, t.bg_statusbar) >= 4.0);
    try std.testing.expect(contrastRatio(t.fg_accent, t.bg_accent) >= 7.0);
}
