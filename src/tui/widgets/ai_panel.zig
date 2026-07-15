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

const Entry = struct {
    label: []const u8,
    icon: []const u8,
    fallback_icon: []const u8,
    command: []const u8,
};

const session_entries = [_]Entry{
    .{ .label = "Focus session", .icon = "󰋱 ", .fallback_icon = "> ", .command = "__CMD__:lua _G.FocusAITerminal()" },
    .{ .label = "Restart session", .icon = "󰑓 ", .fallback_icon = "R ", .command = "__CMD__:lua _G.RestartAITerminal()" },
    .{ .label = "Stop session", .icon = "󰓛 ", .fallback_icon = "S ", .command = "__CMD__:lua _G.StopAITerminal()" },
};

const context_entries = [_]Entry{
    .{ .label = "Selection + lines", .icon = "󰒅 ", .fallback_icon = "S ", .command = "__CMD__:lua _G.SendSelectionToAI()" },
    .{ .label = "Current file", .icon = "󰈚 ", .fallback_icon = "F ", .command = "__CMD__:lua _G.SendFilePathToAI()" },
    .{ .label = "File contents", .icon = "󰈙 ", .fallback_icon = "B ", .command = "__CMD__:lua _G.SendFileContentToAI()" },
    .{ .label = "Diagnostics", .icon = "󰀪 ", .fallback_icon = "D ", .command = "__CMD__:lua _G.SendDiagnosticsToAI()" },
    .{ .label = "Git diff", .icon = "󰊢 ", .fallback_icon = "G ", .command = "__CMD__:lua _G.SendGitDiffToAI()" },
};

const action_entries = [_]Entry{
    .{ .label = "Fix diagnostics", .icon = "󰁨 ", .fallback_icon = "F ", .command = "__CMD__:lua _G.RunAIAction('fix_diagnostics')" },
    .{ .label = "Explain selection", .icon = "󰌵 ", .fallback_icon = "E ", .command = "__CMD__:lua _G.RunAIAction('explain_selection')" },
    .{ .label = "Write tests", .icon = "󰙨 ", .fallback_icon = "T ", .command = "__CMD__:lua _G.RunAIAction('write_tests')" },
    .{ .label = "Review changes", .icon = "󰕢 ", .fallback_icon = "R ", .command = "__CMD__:lua _G.RunAIAction('review_changes')" },
    .{ .label = "Implement TODO", .icon = "󰄬 ", .fallback_icon = "I ", .command = "__CMD__:lua _G.RunAIAction('implement_todo')" },
};

pub const AiPanel = struct {
    available: [agents.len]bool = [_]bool{false} ** agents.len,
    active_agent: ?usize = null,
    session_state: SessionState = .idle,
    view: View = .actions,
    selected: [3]usize = [_]usize{0} ** 3,
    scroll: [3]usize = [_]usize{0} ** 3,

    pub const View = enum(u2) { agents, context, actions };
    pub const SessionState = enum { idle, running, stopped };

    pub fn init(allocator: std.mem.Allocator, io: std.Io, environ: *const std.process.Environ.Map) AiPanel {
        var self = AiPanel{};
        const path = environ.get("PATH") orelse "";
        for (agents, 0..) |agent, idx| {
            self.available[idx] = commandAvailable(allocator, io, path, agent.command);
        }
        return self;
    }

    pub fn deinit(self: *AiPanel) void {
        _ = self;
    }

    pub fn updateSession(self: *AiPanel, command: []const u8, state: []const u8) void {
        for (agents, 0..) |agent, idx| {
            if (std.mem.eql(u8, agent.command, command)) {
                self.active_agent = idx;
                break;
            }
        }
        if (std.mem.eql(u8, state, "running")) {
            self.session_state = .running;
        } else if (std.mem.eql(u8, state, "stopped")) {
            self.session_state = .stopped;
        } else {
            self.session_state = .idle;
        }
    }

    fn commandAvailable(allocator: std.mem.Allocator, io: std.Io, path: []const u8, command: []const u8) bool {
        var dirs = std.mem.splitScalar(u8, path, ':');
        while (dirs.next()) |dir| {
            const base = if (dir.len == 0) "." else dir;
            const candidate = std.fs.path.join(allocator, &.{ base, command }) catch continue;
            defer allocator.free(candidate);
            const result = if (std.fs.path.isAbsolute(candidate))
                std.Io.Dir.accessAbsolute(io, candidate, .{ .execute = true })
            else
                std.Io.Dir.cwd().access(io, candidate, .{ .execute = true });
            result catch continue;
            return true;
        }
        return false;
    }

    fn viewIndex(self: *const AiPanel) usize {
        return @intFromEnum(self.view);
    }

    fn preferredAgent(self: *const AiPanel) ?usize {
        const preference = [_]usize{ 2, 1, 3, 4, 0, 5 };
        for (preference) |idx| {
            if (self.available[idx]) return idx;
        }
        return null;
    }

    fn itemCount(self: *const AiPanel) usize {
        return switch (self.view) {
            .agents => agents.len + session_entries.len,
            .context => context_entries.len,
            .actions => action_entries.len,
        };
    }

    fn selectedIndex(self: *AiPanel) *usize {
        return &self.selected[self.viewIndex()];
    }

    fn changeView(self: *AiPanel, direction: i8) void {
        const current: i8 = @intCast(self.viewIndex());
        const next = @mod(current + direction, 3);
        self.view = @enumFromInt(@as(u2, @intCast(next)));
        if (self.selectedIndex().* >= self.itemCount()) self.selectedIndex().* = self.itemCount() -| 1;
    }

    fn entry(self: *const AiPanel, idx: usize) Entry {
        return switch (self.view) {
            .agents => if (idx < agents.len) blk: {
                const agent = agents[idx];
                break :blk .{
                    .label = agent.label,
                    .icon = agent.icon,
                    .fallback_icon = agent.fallback_icon,
                    .command = if (self.available[idx]) agent.launch else agent.missing,
                };
            } else session_entries[idx - agents.len],
            .context => context_entries[idx],
            .actions => action_entries[idx],
        };
    }

    fn activate(self: *AiPanel, idx: usize) ?[]const u8 {
        if (idx >= self.itemCount()) return null;
        if (self.view == .agents) {
            if (idx < agents.len) {
                if (self.available[idx]) {
                    self.active_agent = idx;
                    self.session_state = .running;
                }
            } else switch (idx - agents.len) {
                1 => if (self.active_agent != null) {
                    self.session_state = .running;
                },
                2 => if (self.active_agent != null) {
                    self.session_state = .stopped;
                },
                else => {},
            }
        }
        return self.entry(idx).command;
    }

    pub fn handleKey(self: *AiPanel, key: []const u8) ?[]const u8 {
        if (std.mem.eql(u8, key, "1")) {
            self.view = .agents;
        } else if (std.mem.eql(u8, key, "2")) {
            self.view = .context;
        } else if (std.mem.eql(u8, key, "3")) {
            self.view = .actions;
        } else if (std.mem.eql(u8, key, "h") or std.mem.eql(u8, key, "<Left>")) {
            self.changeView(-1);
        } else if (std.mem.eql(u8, key, "l") or std.mem.eql(u8, key, "<Right>") or std.mem.eql(u8, key, "<Tab>")) {
            self.changeView(1);
        } else if (std.mem.eql(u8, key, "j") or std.mem.eql(u8, key, "<Down>")) {
            const selected = self.selectedIndex();
            if (selected.* + 1 < self.itemCount()) selected.* += 1;
        } else if (std.mem.eql(u8, key, "k") or std.mem.eql(u8, key, "<Up>")) {
            const selected = self.selectedIndex();
            selected.* -|= 1;
        } else if (std.mem.eql(u8, key, "<Enter>") or std.mem.eql(u8, key, "o") or std.mem.eql(u8, key, "<Space>")) {
            return self.activate(self.selectedIndex().*);
        }
        return null;
    }

    pub fn handleMouse(self: *AiPanel, m: input.MouseEvent, rect: Rect) ?[]const u8 {
        if (m.col < rect.x or m.col >= rect.x + rect.w or m.row < rect.y or m.row >= rect.y + rect.h) return null;

        if (m.button == .wheel_up or m.button == .wheel_down) {
            const selected = self.selectedIndex();
            if (m.button == .wheel_up) {
                selected.* -|= 1;
            } else if (selected.* + 1 < self.itemCount()) {
                selected.* += 1;
            }
            return null;
        }
        if (m.button != .left or m.action != .press) return null;

        if (m.row == rect.y + 4) {
            const usable_w = rect.w -| 1;
            const third = @max(@as(u16, 1), usable_w / 3);
            const relative_x = m.col - rect.x;
            const tab_idx: usize = @min(@as(usize, 2), relative_x / third);
            self.view = @enumFromInt(@as(u2, @intCast(tab_idx)));
            return null;
        }

        const list_y = rect.y + 6;
        const scroll_offset = self.scroll[self.viewIndex()];
        if (m.row >= list_y and m.row < rect.y + rect.h -| 1) {
            const idx: usize = scroll_offset + (m.row - list_y);
            if (idx < self.itemCount()) {
                self.selectedIndex().* = idx;
                return self.activate(idx);
            }
        }
        return null;
    }

    pub fn draw(self: *AiPanel, ren: *renderer.Renderer, rect: Rect, colors: anytype) void {
        ren.drawRect(rect, " ", colors.fg_secondary, colors.bg_sidebar);
        if (rect.w < 12 or rect.h < 8) return;

        ren.drawText(rect.x + 1, rect.y, " AI WORKSPACE", colors.fg_primary, colors.bg_sidebar, true, false);
        const status_fg = if (self.session_state == .running) colors.fg_accent else colors.fg_secondary;
        const status_icon = if (self.session_state == .running) "●" else "○";
        const status_label = if (self.active_agent) |idx| agents[idx].label else "No active agent";
        ren.drawText(rect.x + 2, rect.y + 2, status_icon, status_fg, colors.bg_sidebar, true, false);
        ren.drawTextClipped(rect.x + 4, rect.y + 2, rect.w -| 6, status_label, colors.fg_primary, colors.bg_sidebar, true, false);
        var state_buf: [64]u8 = undefined;
        const state_label: []const u8 = switch (self.session_state) {
            .idle => if (self.preferredAgent()) |idx|
                std.fmt.bufPrint(&state_buf, "Actions auto-start {s}", .{agents[idx].label}) catch "Choose an installed agent"
            else
                "Install an agent to begin",
            .running => "Ready — choose an action",
            .stopped => "Actions restart this agent",
        };
        ren.drawTextClipped(rect.x + 4, rect.y + 3, rect.w -| 6, state_label, colors.fg_secondary, colors.bg_sidebar, false, false);

        const tab_w = @max(@as(u16, 1), (rect.w -| 1) / 3);
        const tab_labels = [_][]const u8{ "1 Agents", "2 Context", "3 Actions" };
        for (tab_labels, 0..) |label, idx| {
            const active = idx == self.viewIndex();
            const tab_x = rect.x + @as(u16, @intCast(idx)) * tab_w;
            ren.drawTextClipped(tab_x + 1, rect.y + 4, tab_w -| 1, label, if (active) colors.fg_primary else colors.fg_secondary, if (active) colors.bg_accent else colors.bg_sidebar, active, false);
        }

        const list_y = rect.y + 6;
        const available_rows: usize = rect.h -| 7;
        const view_idx = self.viewIndex();
        const selected_idx = self.selected[view_idx];
        if (selected_idx < self.scroll[view_idx]) {
            self.scroll[view_idx] = selected_idx;
        } else if (available_rows > 0 and selected_idx >= self.scroll[view_idx] + available_rows) {
            self.scroll[view_idx] = selected_idx - available_rows + 1;
        }
        const max_scroll = self.itemCount() -| available_rows;
        self.scroll[view_idx] = @min(self.scroll[view_idx], max_scroll);
        const count = @min(self.itemCount() -| self.scroll[view_idx], available_rows);
        var row: usize = 0;
        while (row < count) : (row += 1) {
            const idx = self.scroll[view_idx] + row;
            const item = self.entry(idx);
            const selected = idx == selected_idx;
            const row_y = list_y + @as(u16, @intCast(row));
            const row_bg = if (selected) colors.bg_editor else colors.bg_sidebar;
            const disabled = self.view == .agents and ((idx < agents.len and !self.available[idx]) or (idx >= agents.len and self.active_agent == null));
            const row_fg = if (disabled) colors.border_color else if (selected) colors.fg_primary else colors.fg_secondary;
            ren.drawRect(.{ .x = rect.x, .y = row_y, .w = rect.w -| 1, .h = 1 }, " ", row_fg, row_bg);
            if (selected) ren.drawText(rect.x, row_y, "▋", colors.fg_accent, row_bg, true, false);
            const icon = if (colors.nerd_fonts) item.icon else item.fallback_icon;
            ren.drawText(rect.x + 2, row_y, icon, row_fg, row_bg, false, false);
            ren.drawTextClipped(rect.x + 5, row_y, rect.w -| 8, item.label, row_fg, row_bg, false, false);
            if (self.view == .agents and idx < agents.len) {
                ren.drawText(rect.x + rect.w - 3, row_y, if (self.available[idx]) "●" else "○", if (self.available[idx]) colors.fg_accent else colors.border_color, row_bg, false, false);
            }
        }

        if (self.scroll[view_idx] > 0) ren.drawText(rect.x + rect.w - 3, list_y, "▲", colors.fg_accent, colors.bg_sidebar, false, false);
        if (self.scroll[view_idx] + count < self.itemCount() and count > 0) ren.drawText(rect.x + rect.w - 3, list_y + @as(u16, @intCast(count - 1)), "▼", colors.fg_accent, colors.bg_sidebar, false, false);

        if (rect.h >= 2) {
            ren.drawTextClipped(rect.x + 2, rect.y + rect.h - 1, rect.w -| 4, "1-3 section · ↑↓ · Enter", colors.fg_secondary, colors.bg_sidebar, false, false);
        }
        var by: u16 = 0;
        while (by < rect.h) : (by += 1) {
            var cell = renderer.Cell{ .fg = colors.border_color, .bg = colors.bg_sidebar };
            cell.setChar("│");
            ren.setCell(rect.x + rect.w - 1, rect.y + by, cell);
        }
    }
};

test "AI panel navigation keeps independent selections per section" {
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    try env.put("PATH", "");
    var panel = AiPanel.init(std.testing.allocator, std.testing.io, &env);

    try std.testing.expectEqual(AiPanel.View.actions, panel.view);
    _ = panel.handleKey("1");
    _ = panel.handleKey("<Down>");
    try std.testing.expectEqual(@as(usize, 1), panel.selected[0]);
    _ = panel.handleKey("<Right>");
    try std.testing.expectEqual(AiPanel.View.context, panel.view);
    try std.testing.expectEqual(@as(usize, 0), panel.selected[1]);
    _ = panel.handleKey("<Down>");
    _ = panel.handleKey("1");
    try std.testing.expectEqual(AiPanel.View.agents, panel.view);
    try std.testing.expectEqual(@as(usize, 1), panel.selected[0]);

    panel.updateSession("codex", "running");
    try std.testing.expectEqual(@as(?usize, 2), panel.active_agent);
    try std.testing.expectEqual(AiPanel.SessionState.running, panel.session_state);
}
