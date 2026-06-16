const std = @import("std");
const renderer = @import("../renderer.zig");
const Color = renderer.Color;
const Rect = @import("../layout.zig").Rect;
const RpcClient = @import("../../nvim/rpc.zig").RpcClient;
const Value = @import("../../nvim/msgpack.zig").Value;

pub fn LogConsole(comptime get_lines_script: []const u8, comptime highlight_errors: bool) type {
    return struct {
        allocator: std.mem.Allocator,
        lines: std.ArrayList([]const u8),
        scroll_y: usize = 0,

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
                .lines = .{ .items = &[_][]const u8{}, .capacity = 0 },
            };
        }

        pub fn deinit(self: *Self) void {
            for (self.lines.items) |line| {
                self.allocator.free(line);
            }
            self.lines.deinit(self.allocator);
        }

        pub fn refresh(self: *Self, rpc: *RpcClient) void {
            var params = self.allocator.alloc(Value, 2) catch return;
            defer self.allocator.free(params);
            params[0] = .{ .string = get_lines_script };
            params[1] = .{ .array = &[_]Value{} };

            if (rpc.call("nvim_exec_lua", params)) |res| {
                defer @import("../../nvim/msgpack.zig").freeValue(res, self.allocator);
                if (res == .string) {
                    // Clear old lines
                    for (self.lines.items) |line| {
                        self.allocator.free(line);
                    }
                    self.lines.clearRetainingCapacity();

                    var it = std.mem.splitSequence(u8, res.string, "\n");
                    while (it.next()) |line| {
                        if (self.allocator.dupe(u8, line)) |dup| {
                            self.lines.append(self.allocator, dup) catch {};
                        } else |_| {}
                    }
                    
                    // Auto scroll to bottom
                    if (self.lines.items.len > 0) {
                        self.scroll_y = self.lines.items.len;
                    }
                }
            } else |_| {}
        }

        pub fn draw(self: *Self, rend: *renderer.Renderer, rect: Rect, colors: anytype) void {
            rend.drawRect(rect, " ", colors.fg_primary, colors.bg_terminal);
            
            const max_scroll = if (self.lines.items.len > rect.h) self.lines.items.len - rect.h else 0;
            if (self.scroll_y > max_scroll) self.scroll_y = max_scroll;

            var y: u16 = 0;
            var i: usize = self.scroll_y;
            while (y < rect.h and i < self.lines.items.len) : ({y += 1; i += 1;}) {
                const line = self.lines.items[i];
                
                var fg = colors.fg_secondary;
                if (highlight_errors) {
                    if (std.mem.indexOf(u8, line, "error") != null or std.mem.indexOf(u8, line, "Error") != null) {
                        fg = colors.fg_accent; // usually red/orange
                    }
                }
                
                // Basic wrapping for extremely long lines
                var drawn_len: usize = 0;
                if (line.len > rect.w) {
                    drawn_len = @intCast(rect.w);
                } else {
                    drawn_len = line.len;
                }
                
                rend.drawText(rect.x, rect.y + y, line[0..drawn_len], fg, colors.bg_terminal, false, false);
            }
        }

        pub fn handleScroll(self: *Self, dir: i32) void {
            if (dir < 0) { // Up
                if (self.scroll_y > 0) self.scroll_y -= 1;
            } else if (dir > 0) { // Down
                self.scroll_y += 1;
            }
        }
    };
}
