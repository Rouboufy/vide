const std = @import("std");
const input = @import("../input.zig");
const renderer = @import("../renderer.zig");
const Rect = @import("../layout.zig").Rect;

const Agent = struct {
    label: []const u8,
    command: []const u8,
    icon: []const u8,
    fallback_icon: []const u8,
    launch: []const u8,
    missing: []const u8,
};

const agents = [_]Agent{
    .{ .label = "Antigravity", .command = "agy", .icon = " ", .fallback_icon = "A ", .launch = "__CMD__:lua _G.OpenAITerminal('agy')", .missing = "__CMD__:lua _G.NotifyAIMissing('agy')" },
    .{ .label = "Claude Code", .command = "claude", .icon = "󰚩 ", .fallback_icon = "C ", .launch = "__CMD__:lua _G.OpenAITerminal('claude')", .missing = "__CMD__:lua _G.NotifyAIMissing('claude')" },
    .{ .label = "Codex", .command = "codex", .icon = "󰧑 ", .fallback_icon = "X ", .launch = "__CMD__:lua _G.OpenAITerminal('codex')", .missing = "__CMD__:lua _G.NotifyAIMissing('codex')" },
    .{ .label = "Gemini", .command = "gemini", .icon = "󰢚 ", .fallback_icon = "G ", .launch = "__CMD__:lua _G.OpenAITerminal('gemini')", .missing = "__CMD__:lua _G.NotifyAIMissing('gemini')" },
    .{ .label = "OpenCode", .command = "opencode", .icon = "󰊤 ", .fallback_icon = "O ", .launch = "__CMD__:lua _G.OpenAITerminal('opencode')", .missing = "__CMD__:lua _G.NotifyAIMissing('opencode')" },
    .{ .label = "Copilot", .command = "copilot", .icon = " ", .fallback_icon = "P ", .launch = "__CMD__:lua _G.OpenAITerminal('copilot')", .missing = "__CMD__:lua _G.NotifyAIMissing('copilot')" },
};

pub const AiPanel = struct {
    available: [agents.len]bool = @splat(false),
    active_agent: ?usize = null,
    chosen: usize = 2,
    session_state: SessionState = .idle,
    sessions: [agents.len]SessionState = @splat(.idle),
    choosing: bool = false,
    selected: usize = 1,
    scroll: usize = 0,
    pub const SessionState = enum { idle, running, stopped };

    pub fn init(allocator: std.mem.Allocator, io: std.Io, environ: *const std.process.Environ.Map) AiPanel {
        var self = AiPanel{};
        for (agents, 0..) |agent, idx| {
            var dirs = std.mem.splitScalar(u8, environ.get("PATH") orelse "", ':');
            while (dirs.next()) |dir| {
                const path = std.fs.path.join(allocator, &.{ if (dir.len == 0) "." else dir, agent.command }) catch continue;
                defer allocator.free(path);
                std.Io.Dir.cwd().access(io, path, .{ .execute = true }) catch continue;
                self.available[idx] = true;
                break;
            }
        }
        for ([_]usize{ 2, 1, 3, 4, 0, 5 }) |idx| {
            if (self.available[idx]) {
                self.chosen = idx;
                break;
            }
        }
        return self;
    }
    pub fn deinit(_: *AiPanel) void {}
    pub fn updateSession(self: *AiPanel, command: []const u8, state: []const u8, active: bool) void {
        const status: SessionState = if (std.mem.eql(u8, state, "running")) .running else if (std.mem.eql(u8, state, "stopped")) .stopped else .idle;
        for (agents, 0..) |agent, idx| {
            if (std.mem.eql(u8, agent.command, command)) {
                self.sessions[idx] = status;
                if (active) {
                    self.active_agent = idx;
                    self.session_state = status;
                }
                break;
            }
        }
    }
    fn itemCount(self: *const AiPanel) usize {
        return if (self.choosing) agents.len + 1 else if (self.active_agent == self.chosen) 7 else 2;
    }
    fn activate(self: *AiPanel) ?[]const u8 {
        if (self.choosing) {
            if (self.selected < agents.len) self.chosen = self.selected;
            self.choosing = false;
            self.selected = 1;
            self.scroll = 0;
            return null;
        }
        switch (self.selected) {
            0 => {
                self.choosing = true;
                self.selected = self.chosen;
                self.scroll = 0;
                return null;
            },
            1 => return if (self.available[self.chosen]) agents[self.chosen].launch else agents[self.chosen].missing,
            2 => return "__CMD__:lua _G.SendSelectionToAI()",
            3 => return "__CMD__:lua _G.SendFileContentToAI()",
            4 => return "__CMD__:lua _G.RunAIAction('review_changes')",
            5 => return "__CMD__:lua _G.RestartAITerminal()",
            6 => return "__CMD__:lua _G.StopAITerminal()",
            else => return null,
        }
    }
    pub fn handleKey(self: *AiPanel, key: []const u8) ?[]const u8 {
        if (std.mem.eql(u8, key, "j") or std.mem.eql(u8, key, "<Down>") or std.mem.eql(u8, key, "<Tab>")) {
            self.selected = @min(self.selected + 1, self.itemCount() - 1);
        } else if (std.mem.eql(u8, key, "k") or std.mem.eql(u8, key, "<Up>") or std.mem.eql(u8, key, "<S-Tab>")) {
            self.selected -|= 1;
        } else if (std.mem.eql(u8, key, "<Enter>") or std.mem.eql(u8, key, "<Space>") or std.mem.eql(u8, key, "o")) {
            return self.activate();
        }
        return null;
    }
    pub fn handleMouse(self: *AiPanel, m: input.MouseEvent, rect: Rect) ?[]const u8 {
        if (rect.w < 12 or rect.h < 5 or m.col < rect.x or m.col >= rect.x + rect.w - 1 or m.row < rect.y or m.row >= rect.y + rect.h) return null;
        if (m.button == .wheel_up) return self.handleKey("<Up>");
        if (m.button == .wheel_down) return self.handleKey("<Down>");
        if (m.button != .left or m.action != .press or m.row < rect.y + 3) return null;
        const idx = self.scroll + m.row - rect.y - 3;
        if (idx >= self.itemCount()) return null;
        self.selected = idx;
        return self.activate();
    }
    pub fn draw(self: *AiPanel, ren: *renderer.Renderer, rect: Rect, colors: anytype) void {
        ren.drawRect(rect, " ", colors.fg_primary, colors.bg_sidebar);
        if (rect.w < 12 or rect.h < 5) return;
        ren.drawTextClipped(rect.x + 2, rect.y, rect.w - 4, if (self.choosing) "CHOOSE AGENT" else "AI CHAT", colors.fg_primary, colors.bg_sidebar, true, false);
        const status = if (!self.available[self.chosen]) "Not installed" else switch (self.sessions[self.chosen]) {
            .idle => "New chat",
            .running => "Chat open",
            .stopped => "Chat stopped",
        };
        ren.drawTextClipped(rect.x + 2, rect.y + 1, rect.w - 4, if (self.choosing) "" else status, colors.fg_secondary, colors.bg_sidebar, false, false);
        self.selected = @min(self.selected, self.itemCount() - 1);
        const rows: usize = rect.h - 3;
        if (self.selected < self.scroll) self.scroll = self.selected;
        if (self.selected >= self.scroll + rows) self.scroll = self.selected - rows + 1;
        self.scroll = @min(self.scroll, self.itemCount() -| rows);
        const labels = [_][]const u8{ "", "Open chat", "Send selection", "Send file", "Review changes", "Restart chat", "Stop chat" };
        for (0..@min(rows, self.itemCount() - self.scroll)) |row| {
            const idx = row + self.scroll;
            const y = rect.y + 3 + @as(u16, @intCast(row));
            const selected = self.selected == idx;
            const primary = !self.choosing and idx == 1;
            const bg = if (selected or primary) colors.bg_accent else colors.bg_sidebar;
            const fg = @import("../theme.zig").readableForeground(colors.fg_primary, bg, 4.5);
            ren.drawRect(.{ .x = rect.x + 1, .y = y, .w = rect.w - 2, .h = 1 }, " ", fg, bg);
            var buf: [64]u8 = undefined;
            const label = if (self.choosing)
                (if (idx < agents.len) agents[idx].label else "Cancel")
            else if (idx == 0)
                (std.fmt.bufPrint(&buf, "{s} v", .{agents[self.chosen].label}) catch "")
            else if (idx == 1 and self.sessions[self.chosen] == .running)
                "Return to chat"
            else
                labels[idx];
            ren.drawTextClipped(rect.x + 3, y, rect.w - 6, label, fg, bg, primary or selected, false);
            if (selected) ren.drawText(rect.x + 1, y, ">", fg, bg, true, false);
            if (self.choosing and idx < agents.len) {
                ren.drawTextClipped(rect.x + rect.w - 3, y, 1, if (!self.available[idx]) "-" else if (self.sessions[idx] == .running) "*" else "+", fg, bg, false, false);
            }
        }
        for (0..rect.h) |row| ren.drawTextClipped(rect.x + rect.w - 1, rect.y + @as(u16, @intCast(row)), 1, "│", colors.border_color, colors.bg_sidebar, false, false);
    }
};

test "AI chooser selects without starting and scopes actions to the open chat" {
    var panel = AiPanel{};
    panel.available[2] = true;
    try std.testing.expectEqualStrings(agents[2].launch, panel.handleKey("<Enter>").?);
    panel.updateSession("codex", "running", true);
    try std.testing.expectEqual(@as(usize, 7), panel.itemCount());
    _ = panel.handleKey("<Up>");
    try std.testing.expect(panel.handleKey("<Enter>") == null);
    _ = panel.handleKey("<Up>");
    try std.testing.expect(panel.handleKey("<Enter>") == null);
    try std.testing.expectEqual(@as(usize, 1), panel.chosen);
    try std.testing.expectEqual(@as(usize, 2), panel.itemCount());
    panel.updateSession("codex", "stopped", false);
    try std.testing.expectEqual(@as(usize, 1), panel.chosen);
}
