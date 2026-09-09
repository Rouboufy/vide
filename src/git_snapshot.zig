//! Independently-owned, read-only Git refresh result.
//!
//! This module deliberately contains no widget or RPC references. A worker
//! constructs a snapshot and the reactor transfers it into `GitPanel`.
const std = @import("std");
const posix = std.posix;

pub const ChildLifecycle = struct {
    context: *anyopaque,
    publishFn: *const fn (*anyopaque, i32) anyerror!void,
    canceledFn: *const fn (*anyopaque) bool,
    reapedFn: *const fn (*anyopaque) void,
};

pub const Status = struct {
    path: []const u8,
    code: [2]u8,
    staged: bool,
};

pub const GitSnapshot = struct {
    arena: std.heap.ArenaAllocator,
    branch: ?[]const u8,
    commits: []const []const u8,
    status: []const Status,

    pub fn parse(allocator: std.mem.Allocator, branch_output: []const u8, log_output: []const u8, status_output: []const u8) !GitSnapshot {
        var arena = std.heap.ArenaAllocator.init(allocator);
        errdefer arena.deinit();
        const owned = arena.allocator();

        const branch_text = std.mem.trim(u8, branch_output, " \r\n");
        const branch = if (branch_text.len == 0) null else try owned.dupe(u8, branch_text);

        var commits = std.array_list.Managed([]const u8).init(owned);
        var log_lines = std.mem.splitScalar(u8, log_output, '\n');
        while (log_lines.next()) |raw| {
            const line = std.mem.trimEnd(u8, raw, " \r");
            if (line.len != 0) try commits.append(try owned.dupe(u8, line));
        }

        var statuses = std.array_list.Managed(Status).init(owned);
        const separator: u8 = if (std.mem.indexOfScalar(u8, status_output, 0) != null) 0 else '\n';
        var status_lines = std.mem.splitScalar(u8, status_output, separator);
        while (status_lines.next()) |line| {
            if (line.len < 4) continue;
            const path = line[3..];
            const code: [2]u8 = line[0..2].*;
            if (code[0] != ' ' and code[0] != '?') try statuses.append(.{ .path = try owned.dupe(u8, path), .code = .{ code[0], ' ' }, .staged = true });
            if (code[1] != ' ') try statuses.append(.{ .path = try owned.dupe(u8, path), .code = .{ ' ', code[1] }, .staged = false });
            // In porcelain v1 -z, rename/copy records store the destination in
            // this record and the source as the immediately following field.
            if (code[0] == 'R' or code[0] == 'C') _ = status_lines.next();
        }
        std.sort.block(Status, statuses.items, {}, struct {
            fn lessThan(_: void, a: Status, b: Status) bool {
                if (a.staged != b.staged) return a.staged;
                return std.mem.lessThan(u8, a.path, b.path);
            }
        }.lessThan);

        return .{ .arena = arena, .branch = branch, .commits = try commits.toOwnedSlice(), .status = try statuses.toOwnedSlice() };
    }

    pub fn deinit(self: *GitSnapshot) void {
        self.arena.deinit();
        self.* = undefined;
    }

    pub fn capture(allocator: std.mem.Allocator, io: std.Io) !GitSnapshot {
        return captureManaged(allocator, io, null);
    }

    pub fn captureManaged(allocator: std.mem.Allocator, io: std.Io, lifecycle: ?ChildLifecycle) !GitSnapshot {
        const branch = try runCommandManaged(allocator, io, lifecycle, &.{ "git", "branch", "--show-current" });
        defer allocator.free(branch);
        const log = try runCommandManaged(allocator, io, lifecycle, &.{ "git", "log", "--graph", "--abbrev-commit", "--format=format:%h - %s", "-n", "15" });
        defer allocator.free(log);
        const status_output = try runCommandManaged(allocator, io, lifecycle, &.{ "git", "status", "--porcelain=v1", "-z" });
        defer allocator.free(status_output);
        return parse(allocator, branch, log, status_output);
    }
};

pub fn runCommandManaged(allocator: std.mem.Allocator, io: std.Io, lifecycle: ?ChildLifecycle, argv: []const []const u8) ![]u8 {
    var child = try std.process.spawn(io, .{ .argv = argv, .stdout = .pipe, .stderr = .ignore });
    errdefer if (child.id != null) child.kill(io);
    const pid: i32 = @intCast(child.id.?);
    if (lifecycle) |observer| try observer.publishFn(observer.context, pid);
    var published = lifecycle != null;
    defer if (published) if (lifecycle) |observer| observer.reapedFn(observer.context);
    const stdout_fd = child.stdout.?.handle;
    defer if (child.stdout) |stdout| {
        _ = posix.system.close(stdout.handle);
        child.stdout = null;
    };
    const old_flags = posix.system.fcntl(stdout_fd, posix.F.GETFL, @as(usize, 0));
    if (old_flags >= 0) _ = posix.system.fcntl(stdout_fd, posix.F.SETFL, @as(usize, @intCast(old_flags)) | @as(u32, @bitCast(posix.O{ .NONBLOCK = true })));
    var output = std.array_list.Managed(u8).init(allocator);
    errdefer output.deinit();
    var term_sent_at: ?i128 = null;
    var status: if (@import("builtin").link_libc) c_int else u32 = undefined;
    while (true) {
        var buffer: [4096]u8 = undefined;
        const count = posix.read(stdout_fd, &buffer) catch |err| switch (err) {
            error.WouldBlock => 0,
            else => return err,
        };
        if (count != 0) try output.appendSlice(buffer[0..count]);
        const waited = posix.system.waitpid(child.id.?, &status, posix.W.NOHANG);
        switch (posix.errno(waited)) {
            .SUCCESS => if (waited != 0) {
                // `waitpid` has already reaped this exact process. Retire the
                // PID and registry slot before any fallible output handling;
                // an allocation/read failure must never kill a reused PID.
                child.id = null;
                published = false;
                if (lifecycle) |observer| observer.reapedFn(observer.context);
                // Exit and pipe EOF are separate events; preserve bytes that
                // were buffered immediately before the child terminated.
                while (true) {
                    const trailing = posix.read(stdout_fd, &buffer) catch |err| switch (err) {
                        error.WouldBlock => 0,
                        else => return err,
                    };
                    if (trailing == 0) break;
                    try output.appendSlice(buffer[0..trailing]);
                }
                break;
            },
            .INTR => continue,
            else => return error.ChildWaitFailed,
        }
        if (lifecycle) |observer| if (observer.canceledFn(observer.context)) {
            var now: posix.timespec = undefined;
            _ = posix.system.clock_gettime(posix.CLOCK.MONOTONIC, &now);
            const now_ns = @as(i128, now.sec) * std.time.ns_per_s + now.nsec;
            if (term_sent_at == null) {
                posix.kill(child.id.?, .TERM) catch |err| if (err != error.ProcessNotFound) return err;
                term_sent_at = now_ns;
            } else if (now_ns - term_sent_at.? >= 500 * std.time.ns_per_ms) {
                posix.kill(child.id.?, .KILL) catch |err| if (err != error.ProcessNotFound) return err;
            }
        };
        std.Io.sleep(io, .fromMilliseconds(50), .awake) catch {};
    }
    while (true) {
        var buffer: [4096]u8 = undefined;
        const count = posix.read(stdout_fd, &buffer) catch |err| switch (err) {
            error.WouldBlock => break,
            else => return err,
        };
        if (count == 0) break;
        try output.appendSlice(buffer[0..count]);
    }
    const raw_status: u32 = @bitCast(status);
    if (!posix.W.IFEXITED(raw_status) or posix.W.EXITSTATUS(raw_status) != 0) return error.GitCommandFailed;
    return output.toOwnedSlice();
}

/// Compatibility seam for a one-change rollback. Production periodic refresh
/// is asynchronous as of 04C; mutation-triggered refresh remains legacy until
/// Prompt 13 migrates stage/unstage/commit.
pub const compatibility = struct {
    pub const periodic_synchronous_refresh = false;
};

test "snapshot owns all strings independently of command buffers" {
    var branch = [_]u8{ 'm', 'a', 'i', 'n', '\n' };
    var snapshot = try GitSnapshot.parse(std.testing.allocator, &branch, "abc - subject\n", "M  a.zig\n M b.zig\n?? c.zig\n");
    defer snapshot.deinit();
    @memset(&branch, 'x');
    try std.testing.expectEqualStrings("main", snapshot.branch.?);
    try std.testing.expectEqual(@as(usize, 3), snapshot.status.len);
    try std.testing.expectEqualStrings("a.zig", snapshot.status[0].path);
}

test "snapshot allocation failures clean partial ownership" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, struct {
        fn run(allocator: std.mem.Allocator) !void {
            var snapshot = try GitSnapshot.parse(allocator, "main", "one\ntwo", "M  a\n M b\n");
            defer snapshot.deinit();
        }
    }.run, .{});
}

test "porcelain z preserves special paths and rename destination" {
    var snapshot = try GitSnapshot.parse(std.testing.allocator, "main", "", "R  new name\x00old name\x00?? line\nname\x00");
    defer snapshot.deinit();
    try std.testing.expectEqual(@as(usize, 2), snapshot.status.len);
    try std.testing.expectEqualStrings("new name", snapshot.status[0].path);
    try std.testing.expectEqualStrings("line\nname", snapshot.status[1].path);
}
