//! Dormant background-task runner primitives.
//!
//! No UI, RPC, renderer, widget, or arena pointer may cross this boundary.
//! The production pool is dormant until an operation is migrated; tests and
//! workers currently share the independently-owned byte-copy adapter.
const std = @import("std");
const posix = std.posix;
const GitSnapshot = @import("git_snapshot.zig").GitSnapshot;

pub const high_capacity = 16;
pub const normal_capacity = 48;
pub const completion_capacity = high_capacity + normal_capacity;
pub const max_workers = 4;
pub const high_burst_limit = 4;

pub const OwnerId = enum(u64) { _ };
pub const Generation = enum(u64) { _ };
pub const OperationId = enum(u64) { _ };
pub const TaskId = enum(u64) { _ };

pub fn workerCount(cpu_count: ?usize) usize {
    const cpus = cpu_count orelse return 1;
    return @min(@max(cpus -| 1, 1), max_workers);
}

pub const Kind = enum { refresh_latest, read_once, interactive_read, mutation };
pub const Priority = enum { high, normal };

pub const Payload = union(Kind) {
    refresh_latest: []u8,
    read_once: []u8,
    interactive_read: []u8,
    mutation: []u8,

    pub fn init(allocator: std.mem.Allocator, op_kind: Kind, input: []const u8) !Payload {
        const owned = try allocator.dupe(u8, input);
        return switch (op_kind) {
            .refresh_latest => .{ .refresh_latest = owned },
            .read_once => .{ .read_once = owned },
            .interactive_read => .{ .interactive_read = owned },
            .mutation => .{ .mutation = owned },
        };
    }
    pub fn kind(self: Payload) Kind {
        return std.meta.activeTag(self);
    }
    pub fn bytes(self: Payload) []const u8 {
        return switch (self) {
            inline else => |value| value,
        };
    }
    pub fn deinit(self: *Payload, allocator: std.mem.Allocator) void {
        allocator.free(self.bytes());
        self.* = undefined;
    }
};

pub const Result = union(Kind) {
    refresh_latest: GitSnapshot,
    read_once: []u8,
    interactive_read: []u8,
    mutation: []u8,

    pub fn init(allocator: std.mem.Allocator, op_kind: Kind, input: []const u8) !Result {
        if (op_kind == .refresh_latest) return .{ .refresh_latest = try GitSnapshot.parse(allocator, input, "", "") };
        const owned = try allocator.dupe(u8, input);
        return fromOwned(op_kind, owned);
    }
    pub fn fromOwned(op_kind: Kind, owned_bytes: []u8) Result {
        return switch (op_kind) {
            .refresh_latest => unreachable,
            .read_once => .{ .read_once = owned_bytes },
            .interactive_read => .{ .interactive_read = owned_bytes },
            .mutation => .{ .mutation = owned_bytes },
        };
    }
    pub fn kind(self: Result) Kind {
        return std.meta.activeTag(self);
    }
    pub fn bytes(self: Result) []const u8 {
        return switch (self) {
            .refresh_latest => |value| value.branch orelse "",
            inline else => |value| value,
        };
    }
    pub fn deinit(self: *Result, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .refresh_latest => |*snapshot| snapshot.deinit(),
            inline else => |owned_bytes| allocator.free(owned_bytes),
        }
        self.* = undefined;
    }
};

pub const Command = struct {
    task_id: TaskId = @enumFromInt(0),
    owner: OwnerId,
    generation: Generation,
    operation_id: ?OperationId = null,
    payload: Payload,

    pub fn init(allocator: std.mem.Allocator, op_kind: Kind, owner: OwnerId, generation: Generation, operation_id: ?OperationId, payload: []const u8) !Command {
        if (@intFromEnum(owner) == 0 or @intFromEnum(generation) == 0) return error.InvalidIdentity;
        if ((op_kind == .mutation) != (operation_id != null)) return error.InvalidOperationId;
        if (operation_id) |id| if (@intFromEnum(id) == 0) return error.InvalidOperationId;
        return .{ .owner = owner, .generation = generation, .operation_id = operation_id, .payload = try Payload.init(allocator, op_kind, payload) };
    }

    pub fn kind(self: Command) Kind {
        return self.payload.kind();
    }

    pub fn deinit(self: *Command, allocator: std.mem.Allocator) void {
        self.payload.deinit(allocator);
        self.* = undefined;
    }
};

pub const Completion = struct {
    task_id: TaskId,
    op_kind: Kind,
    owner: OwnerId,
    generation: Generation,
    operation_id: ?OperationId,
    outcome: Outcome,

    pub fn kind(self: Completion) Kind {
        return self.op_kind;
    }

    pub fn deinit(self: *Completion, allocator: std.mem.Allocator) void {
        self.outcome.deinit(allocator);
        self.* = undefined;
    }
};

pub const Outcome = union(enum) {
    success: Result,
    failure,
    canceled_before_start,
    unknown,

    pub fn deinit(self: *Outcome, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .success => |*result| result.deinit(allocator),
            else => {},
        }
        self.* = undefined;
    }
    pub fn successBytes(self: Outcome) ?[]const u8 {
        return switch (self) {
            .success => |result| result.bytes(),
            else => null,
        };
    }
};

const CommandQueue = struct {
    items: [normal_capacity]?Command = [_]?Command{null} ** normal_capacity,
    len: usize = 0,

    fn push(self: *CommandQueue, command: Command, capacity: usize) !void {
        if (self.len == capacity) return error.RunnerBusy;
        self.items[self.len] = command;
        self.len += 1;
    }

    fn pop(self: *CommandQueue) ?Command {
        if (self.len == 0) return null;
        const value = self.items[0].?;
        std.mem.copyForwards(?Command, self.items[0 .. self.len - 1], self.items[1..self.len]);
        self.len -= 1;
        self.items[self.len] = null;
        return value;
    }

    fn removeAt(self: *CommandQueue, index: usize) Command {
        const value = self.items[index].?;
        std.mem.copyForwards(?Command, self.items[index .. self.len - 1], self.items[index + 1 .. self.len]);
        self.len -= 1;
        self.items[self.len] = null;
        return value;
    }
};

pub const FakeNotifier = struct {
    pending: bool = false,
    writes: usize = 0,

    fn notify(self: *FakeNotifier) void {
        if (!self.pending) self.writes += 1;
        self.pending = true;
    }
    pub fn drain(self: *FakeNotifier) void {
        self.pending = false;
    }
};

pub const FakeScheduler = struct {
    allocator: std.mem.Allocator,
    high: CommandQueue = .{},
    normal: CommandQueue = .{},
    completions: [completion_capacity]?Completion = [_]?Completion{null} ** completion_capacity,
    completion_len: usize = 0,
    reservations: usize = 0,
    high_streak: usize = 0,
    accepting: bool = true,
    notifier: FakeNotifier = .{},
    task_ids: TaskIdAllocator = .{},

    pub fn init(allocator: std.mem.Allocator) FakeScheduler {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *FakeScheduler) void {
        while (self.high.pop()) |command_value| {
            var command = command_value;
            command.deinit(self.allocator);
            self.reservations -= 1;
        }
        while (self.normal.pop()) |command_value| {
            var command = command_value;
            command.deinit(self.allocator);
            self.reservations -= 1;
        }
        while (self.takeCompletion()) |completion_value| {
            var completion = completion_value;
            completion.deinit(self.allocator);
        }
        std.debug.assert(self.reservations == 0);
    }

    /// Success transfers command ownership; failure leaves it with the caller.
    pub fn submit(self: *FakeScheduler, command_input: Command) !void {
        var command = command_input;
        if (!self.accepting) return error.ShuttingDown;
        const priority: Priority = switch (command.kind()) {
            .interactive_read, .mutation => .high,
            else => .normal,
        };
        const queue = if (priority == .high) &self.high else &self.normal;
        const capacity: usize = if (priority == .high) high_capacity else normal_capacity;

        if (command.kind() == .refresh_latest) {
            for (queue.items[0..queue.len], 0..) |entry, index| {
                const old = entry.?;
                if (old.kind() == command.kind() and old.owner == command.owner) {
                    command.task_id = try self.task_ids.next(command.owner);
                    var removed = queue.removeAt(index);
                    removed.deinit(self.allocator);
                    try queue.push(command, capacity);
                    return;
                }
            }
        }
        if (self.reservations == completion_capacity or queue.len == capacity) return error.RunnerBusy;
        command.task_id = try self.task_ids.next(command.owner);
        try queue.push(command, capacity);
        self.reservations += 1;
    }

    fn next(self: *FakeScheduler) ?Command {
        if (self.high.len != 0 and (self.high_streak < high_burst_limit or self.normal.len == 0)) {
            self.high_streak += 1;
            return self.high.pop();
        }
        if (self.normal.pop()) |command| {
            self.high_streak = 0;
            return command;
        }
        if (self.high.pop()) |command| {
            self.high_streak = 1;
            return command;
        }
        return null;
    }

    /// Fake operation adapter: independently owns a byte-for-byte result.
    pub fn runOne(self: *FakeScheduler) !bool {
        var command = self.next() orelse return false;
        errdefer {
            command.deinit(self.allocator);
            self.reservations -= 1;
        }
        const result = try Result.init(self.allocator, command.kind(), command.payload.bytes());
        self.completions[self.completion_len] = .{ .task_id = command.task_id, .op_kind = command.kind(), .owner = command.owner, .generation = command.generation, .operation_id = command.operation_id, .outcome = .{ .success = result } };
        self.completion_len += 1;
        command.deinit(self.allocator);
        self.notifier.notify();
        return true;
    }

    pub fn takeCompletion(self: *FakeScheduler) ?Completion {
        if (self.completion_len == 0) return null;
        const value = self.completions[0].?;
        std.mem.copyForwards(?Completion, self.completions[0 .. self.completion_len - 1], self.completions[1..self.completion_len]);
        self.completion_len -= 1;
        self.completions[self.completion_len] = null;
        self.reservations -= 1;
        return value;
    }

    pub fn cancelOwner(self: *FakeScheduler, owner: OwnerId) void {
        self.cancelIn(&self.high, owner);
        self.cancelIn(&self.normal, owner);
    }

    fn cancelIn(self: *FakeScheduler, queue: *CommandQueue, owner: OwnerId) void {
        var index: usize = 0;
        while (index < queue.len) {
            if (queue.items[index].?.owner != owner) {
                index += 1;
                continue;
            }
            var command = queue.removeAt(index);
            command.deinit(self.allocator);
            self.reservations -= 1;
        }
    }

    pub fn shutdown(self: *FakeScheduler) void {
        self.accepting = false;
        while (self.high.pop()) |value| {
            var command = value;
            command.deinit(self.allocator);
            self.reservations -= 1;
        }
        while (self.normal.pop()) |value| {
            var command = value;
            command.deinit(self.allocator);
            self.reservations -= 1;
        }
    }
};

pub const Notifier = struct {
    read_fd: posix.fd_t,
    write_fd: posix.fd_t,

    pub fn init() !Notifier {
        var fds: [2]posix.fd_t = undefined;
        if (@TypeOf(posix.system.pipe2) != void) {
            while (true) {
                const err = posix.errno(posix.system.pipe2(&fds, .{ .NONBLOCK = true, .CLOEXEC = true }));
                if (err == .SUCCESS) break;
                if (err != .INTR) return error.PipeFailed;
            }
        } else {
            while (true) {
                const err = posix.errno(posix.system.pipe(&fds));
                if (err == .SUCCESS) break;
                if (err != .INTR) return error.PipeFailed;
            }
            errdefer {
                _ = posix.system.close(fds[0]);
                _ = posix.system.close(fds[1]);
            }
            for (fds) |fd| {
                try setNonblocking(fd);
                try setCloseOnExec(fd);
            }
        }
        return .{ .read_fd = fds[0], .write_fd = fds[1] };
    }

    fn setNonblocking(fd: posix.fd_t) !void {
        var current: isize = undefined;
        while (true) {
            current = posix.system.fcntl(fd, posix.F.GETFL, @as(usize, 0));
            const err = posix.errno(current);
            if (err == .SUCCESS) break;
            if (err != .INTR) return error.PipeFailed;
        }
        const nonblocking: usize = @as(u32, @bitCast(posix.O{ .NONBLOCK = true }));
        while (true) {
            const rc = posix.system.fcntl(fd, posix.F.SETFL, @as(usize, @intCast(current)) | nonblocking);
            const err = posix.errno(rc);
            if (err == .SUCCESS) return;
            if (err != .INTR) return error.PipeFailed;
        }
    }

    fn setCloseOnExec(fd: posix.fd_t) !void {
        while (true) {
            const rc = posix.system.fcntl(fd, posix.F.SETFD, @as(usize, posix.FD_CLOEXEC));
            const err = posix.errno(rc);
            if (err == .SUCCESS) return;
            if (err != .INTR) return error.PipeFailed;
        }
    }
    pub fn deinit(self: *Notifier) void {
        _ = posix.system.close(self.read_fd);
        _ = posix.system.close(self.write_fd);
        self.* = undefined;
    }
    pub fn notify(self: *Notifier) !void {
        const byte = "x";
        while (true) {
            const err = posix.errno(posix.system.write(self.write_fd, byte.ptr, 1));
            if (err == .SUCCESS or err == .AGAIN) return;
            if (err != .INTR) return error.NotifyFailed;
        }
    }
    pub fn drain(self: *Notifier) !void {
        var bytes: [64]u8 = undefined;
        while (true) {
            const rc = posix.system.read(self.read_fd, &bytes, bytes.len);
            const err = posix.errno(rc);
            if (err == .SUCCESS and rc > 0) continue;
            if (err == .AGAIN) return;
            if (err == .INTR) continue;
            return error.NotifyFailed;
        }
    }
};

pub const max_owners = 16;

pub const TaskIdAllocator = struct {
    const Slot = struct {
        owner: OwnerId,
        next_id: u64 = 1,
        completed_watermark: u64 = 0,
        completed_ahead: u64 = 0,
    };
    slots: [max_owners]?Slot = [_]?Slot{null} ** max_owners,

    pub fn next(self: *TaskIdAllocator, owner: OwnerId) !TaskId {
        var free: ?*?Slot = null;
        for (&self.slots) |*slot| {
            if (slot.*) |*entry| {
                if (entry.owner != owner) continue;
                if (entry.next_id == 0) return error.TaskIdExhausted;
                if (entry.next_id - entry.completed_watermark > completion_capacity) return error.TaskWindowFull;
                const id: TaskId = @enumFromInt(entry.next_id);
                entry.next_id +%= 1;
                return id;
            }
            if (free == null) free = slot;
        }
        const target = free orelse return error.OwnerRegistryFull;
        target.* = .{ .owner = owner, .next_id = 2 };
        return @enumFromInt(1);
    }

    pub fn claim(self: *TaskIdAllocator, owner: OwnerId, task_id: TaskId) !void {
        const raw = @intFromEnum(task_id);
        if (raw == 0) return error.InvalidTaskId;
        var free: ?*?Slot = null;
        for (&self.slots) |*slot| {
            if (slot.*) |*entry| {
                if (entry.owner != owner) continue;
                if (raw != entry.next_id) return error.TaskIdOutOfSequence;
                if (raw - entry.completed_watermark > completion_capacity) return error.TaskWindowFull;
                entry.next_id +%= 1;
                return;
            }
            if (free == null) free = slot;
        }
        if (raw != 1) return error.TaskIdOutOfSequence;
        (free orelse return error.OwnerRegistryFull).* = .{ .owner = owner, .next_id = 2 };
    }

    pub fn complete(self: *TaskIdAllocator, owner: OwnerId, task_id: TaskId) void {
        for (&self.slots) |*slot| if (slot.*) |*entry| {
            if (entry.owner != owner) continue;
            const raw = @intFromEnum(task_id);
            if (raw <= entry.completed_watermark) return;
            const distance = raw - entry.completed_watermark;
            if (distance > 64) return;
            entry.completed_ahead |= @as(u64, 1) << @intCast(distance - 1);
            while (entry.completed_ahead & 1 != 0) {
                entry.completed_watermark += 1;
                entry.completed_ahead >>= 1;
            }
            return;
        };
    }
};

pub const OwnerRegistry = struct {
    const Entry = struct {
        id: OwnerId,
        generation: Generation,
        last_operation: u64 = 0,
        next_task: u64 = 1,
        completed_watermark: u64 = 0,
        completed_ahead: u64 = 0,
        open: bool = true,
    };
    owners: [max_owners]?Entry = [_]?Entry{null} ** max_owners,
    next_owner: u64 = 1,

    pub fn create(self: *OwnerRegistry) !OwnerId {
        if (self.next_owner == 0) return error.OwnerIdExhausted;
        for (&self.owners) |*slot| {
            if (slot.* != null and slot.*.?.open) continue;
            const id: OwnerId = @enumFromInt(self.next_owner);
            self.next_owner +%= 1;
            slot.* = .{ .id = id, .generation = @enumFromInt(1) };
            return id;
        }
        return error.OwnerRegistryFull;
    }

    fn find(self: *OwnerRegistry, id: OwnerId) ?*Entry {
        for (&self.owners) |*slot| if (slot.*) |*entry| if (entry.open and entry.id == id) return entry;
        return null;
    }

    pub fn close(self: *OwnerRegistry, id: OwnerId) bool {
        const entry = self.find(id) orelse return false;
        entry.open = false;
        return true;
    }

    pub fn generation(self: *OwnerRegistry, id: OwnerId) ?Generation {
        const entry = self.find(id) orelse return null;
        return entry.generation;
    }

    pub fn invalidate(self: *OwnerRegistry, id: OwnerId) !Generation {
        const entry = self.find(id) orelse return error.UnknownOwner;
        const current = @intFromEnum(entry.generation);
        if (current == std.math.maxInt(u64)) return error.GenerationExhausted;
        entry.generation = @enumFromInt(current + 1);
        // All tasks allocated in the previous generation are now terminally
        // stale. Retire them so they cannot leave a permanent hole in the
        // bounded out-of-order completion window.
        entry.completed_watermark = entry.next_task - 1;
        entry.completed_ahead = 0;
        return entry.generation;
    }

    pub fn nextOperation(self: *OwnerRegistry, id: OwnerId) !OperationId {
        const entry = self.find(id) orelse return error.UnknownOwner;
        if (entry.last_operation == std.math.maxInt(u64)) return error.OperationIdExhausted;
        entry.last_operation += 1;
        return @enumFromInt(entry.last_operation);
    }

    pub fn nextTask(self: *OwnerRegistry, id: OwnerId) !TaskId {
        const entry = self.find(id) orelse return error.UnknownOwner;
        if (entry.next_task == 0) return error.TaskIdExhausted;
        if (entry.next_task - entry.completed_watermark > completion_capacity) return error.TaskWindowFull;
        const result: TaskId = @enumFromInt(entry.next_task);
        entry.next_task +%= 1;
        return result;
    }

    pub fn rollbackTask(self: *OwnerRegistry, id: OwnerId, task_id: TaskId) bool {
        const entry = self.find(id) orelse return false;
        const raw = @intFromEnum(task_id);
        if (entry.next_task != raw + 1 or raw <= entry.completed_watermark) return false;
        entry.next_task = raw;
        return true;
    }

    fn recordCompleted(entry: *Entry, task_id: TaskId) bool {
        const raw = @intFromEnum(task_id);
        if (raw == 0 or raw <= entry.completed_watermark) return false;
        const distance = raw - entry.completed_watermark;
        if (distance > 64) return false;
        const mask = @as(u64, 1) << @intCast(distance - 1);
        if (entry.completed_ahead & mask != 0) return false;
        entry.completed_ahead |= mask;
        while (entry.completed_ahead & 1 != 0) {
            entry.completed_watermark += 1;
            entry.completed_ahead >>= 1;
        }
        return true;
    }

    /// Returns ownership only for a live, current, first-seen completion.
    /// Every rejected completion is destroyed in this call.
    pub fn validate(self: *OwnerRegistry, allocator: std.mem.Allocator, completion_ptr: *Completion) ?Completion {
        const entry = self.find(completion_ptr.owner) orelse {
            completion_ptr.deinit(allocator);
            return null;
        };
        if (entry.generation != completion_ptr.generation) {
            completion_ptr.deinit(allocator);
            return null;
        }
        if (@intFromEnum(completion_ptr.task_id) >= entry.next_task) {
            completion_ptr.deinit(allocator);
            return null;
        }
        if (completion_ptr.kind() == .mutation) {
            const operation = completion_ptr.operation_id orelse {
                completion_ptr.deinit(allocator);
                return null;
            };
            if (@intFromEnum(operation) > entry.last_operation) {
                completion_ptr.deinit(allocator);
                return null;
            }
        } else if (completion_ptr.operation_id != null) {
            completion_ptr.deinit(allocator);
            return null;
        }
        if (!recordCompleted(entry, completion_ptr.task_id)) {
            completion_ptr.deinit(allocator);
            return null;
        }
        const result = completion_ptr.*;
        completion_ptr.* = undefined;
        return result;
    }
};

pub const ChildToken = struct { worker: usize, slot_generation: u64, pid: i32, operation_id: OperationId };

pub const FakeChildController = struct {
    const Slot = struct {
        generation: u64 = 0,
        pid: i32 = 0,
        operation_id: OperationId = @enumFromInt(1),
        published: bool = false,
        cancel_requested: bool = false,
        graceful_sent: bool = false,
        force_sent: bool = false,
        elapsed_ms: u64 = 0,
    };
    slots: [max_workers]Slot = [_]Slot{.{}} ** max_workers,
    shutdown_cancel: [max_workers]bool = [_]bool{false} ** max_workers,
    graceful_count: usize = 0,
    force_count: usize = 0,
    reap_count: usize = 0,

    pub fn requestShutdown(self: *FakeChildController) void {
        for (&self.shutdown_cancel, &self.slots) |*persistent, *slot| {
            persistent.* = true;
            if (slot.published) slot.cancel_requested = true;
        }
    }

    pub fn publish(self: *FakeChildController, worker: usize, pid: i32, operation_id: OperationId) !ChildToken {
        const slot = &self.slots[worker];
        if (slot.published) return error.ChildSlotBusy;
        if (slot.generation == std.math.maxInt(u64)) return error.ChildGenerationExhausted;
        slot.generation += 1;
        slot.pid = pid;
        slot.operation_id = operation_id;
        slot.published = true;
        slot.cancel_requested = self.shutdown_cancel[worker];
        slot.graceful_sent = false;
        slot.force_sent = false;
        slot.elapsed_ms = 0;
        return .{ .worker = worker, .slot_generation = slot.generation, .pid = pid, .operation_id = operation_id };
    }

    pub fn advance(self: *FakeChildController, token: ChildToken, elapsed_ms: u64) bool {
        const slot = &self.slots[token.worker];
        if (!matches(slot, token) or !slot.cancel_requested) return false;
        if (!slot.graceful_sent) {
            slot.graceful_sent = true;
            self.graceful_count += 1;
        }
        slot.elapsed_ms += elapsed_ms;
        if (slot.elapsed_ms >= 500 and !slot.force_sent) {
            slot.force_sent = true;
            self.force_count += 1;
        }
        return true;
    }

    pub fn reap(self: *FakeChildController, token: ChildToken) bool {
        const slot = &self.slots[token.worker];
        if (!matches(slot, token)) return false;
        slot.published = false;
        self.reap_count += 1;
        return true;
    }

    /// Deterministic 04B child adapter used by the owning worker on exit. A
    /// real adapter replaces the elapsed-time step with <=50 ms wait polls.
    pub fn cancelAndReap(self: *FakeChildController, worker: usize) void {
        const slot = &self.slots[worker];
        if (!slot.published) return;
        const token: ChildToken = .{ .worker = worker, .slot_generation = slot.generation, .pid = slot.pid, .operation_id = slot.operation_id };
        slot.cancel_requested = true;
        _ = self.advance(token, 500);
        _ = self.reap(token);
    }

    fn matches(slot: *const Slot, token: ChildToken) bool {
        return slot.published and slot.generation == token.slot_generation and slot.pid == token.pid and slot.operation_id == token.operation_id;
    }
};

pub const NotifierRaceModel = struct {
    queued: usize = 0,
    byte_pending: bool = false,
    writes: usize = 0,

    pub fn publish(self: *NotifierRaceModel) void {
        self.queued += 1;
        if (self.queued == 1 and !self.byte_pending) {
            self.byte_pending = true;
            self.writes += 1;
        }
    }
    pub fn consumeAll(self: *NotifierRaceModel) void {
        self.queued = 0;
    }
    /// Models draining the pipe under the queue lock and the mandatory recheck.
    pub fn drainRecheck(self: *NotifierRaceModel, publish_at_boundary: bool) void {
        self.byte_pending = false;
        if (publish_at_boundary) self.publish();
        if (self.queued != 0 and !self.byte_pending) {
            self.byte_pending = true;
            self.writes += 1;
        }
    }
};

pub const InitStages = struct {
    mutex: bool = false,
    notifier: bool = false,
    storage: bool = false,
    workers: usize = 0,
    cleanup_count: usize = 0,

    pub fn simulate(self: *InitStages, worker_count: usize, fail_at: usize) !void {
        var stage: usize = 0;
        errdefer self.unwind();
        stage += 1;
        if (stage == fail_at) return error.InjectedFailure;
        self.mutex = true;
        stage += 1;
        if (stage == fail_at) return error.InjectedFailure;
        self.notifier = true;
        stage += 1;
        if (stage == fail_at) return error.InjectedFailure;
        self.storage = true;
        for (0..worker_count) |_| {
            stage += 1;
            if (stage == fail_at) return error.InjectedFailure;
            self.workers += 1;
        }
    }

    pub fn unwind(self: *InitStages) void {
        while (self.workers != 0) {
            self.workers -= 1;
            self.cleanup_count += 1;
        }
        if (self.storage) {
            self.storage = false;
            self.cleanup_count += 1;
        }
        if (self.notifier) {
            self.notifier = false;
            self.cleanup_count += 1;
        }
        if (self.mutex) {
            self.mutex = false;
            self.cleanup_count += 1;
        }
    }
};

/// Dormant production host. The allocator passed to `init` must be thread-safe.
/// Workers currently execute only the owned byte-copy adapter.
pub const Runner = struct {
    allocator: std.mem.Allocator,
    sync_backend: std.Io.Threaded,
    mutex: std.Io.Mutex = .init,
    condition: std.Io.Condition = .init,
    notifier: Notifier,
    high: CommandQueue = .{},
    normal: CommandQueue = .{},
    completions: [completion_capacity]?Completion = [_]?Completion{null} ** completion_capacity,
    completion_len: usize = 0,
    reservations: usize = 0,
    high_streak: usize = 0,
    accepting: bool = true,
    completion_admission: bool = true,
    stopping: bool = false,
    workers_paused: bool = false,
    pause_after_dequeue: bool = false,
    worker_dequeued: bool = false,
    cancel: [max_workers]bool = [_]bool{false} ** max_workers,
    active_owner: [max_workers]?OwnerId = [_]?OwnerId{null} ** max_workers,
    threads: [max_workers]?std.Thread = [_]?std.Thread{null} ** max_workers,
    thread_count: usize = 0,
    task_ids: TaskIdAllocator = .{},
    children: FakeChildController = .{},

    pub const InitOptions = struct {
        worker_count: ?usize = null,
        /// Test seam: fail before spawning the worker at this zero-based index.
        fail_spawn_at: ?usize = null,
        /// Deterministic test seam; shutdown always releases paused workers.
        pause_workers: bool = false,
        pause_after_dequeue: bool = false,
    };

    pub fn init(allocator: std.mem.Allocator, options: InitOptions) !*Runner {
        const self = try allocator.create(Runner);
        errdefer allocator.destroy(self);
        var notifier = try Notifier.init();
        errdefer notifier.deinit();
        self.* = .{ .allocator = allocator, .sync_backend = std.Io.Threaded.init(allocator, .{}), .notifier = notifier, .workers_paused = options.pause_workers, .pause_after_dequeue = options.pause_after_dequeue };
        errdefer self.sync_backend.deinit();
        const discovered = std.Thread.getCpuCount() catch null;
        const count = options.worker_count orelse workerCount(discovered);
        if (count == 0 or count > max_workers) return error.InvalidWorkerCount;
        errdefer self.stopAndJoinSpawned();
        for (0..count) |index| {
            if (options.fail_spawn_at == index) return error.InjectedSpawnFailure;
            self.threads[index] = try std.Thread.spawn(.{}, workerMain, .{ self, index });
            self.thread_count += 1;
        }
        return self;
    }

    pub fn notifierFd(self: *const Runner) posix.fd_t {
        return self.notifier.read_fd;
    }

    fn lock(self: *Runner) void {
        self.mutex.lockUncancelable(self.sync_backend.io());
    }
    fn unlock(self: *Runner) void {
        self.mutex.unlock(self.sync_backend.io());
    }

    /// Success transfers ownership. Rejection leaves ownership with caller.
    pub fn submit(self: *Runner, value_input: Command) !void {
        var value = value_input;
        self.lock();
        defer self.unlock();
        if (!self.accepting) return error.ShuttingDown;
        const high_priority = value.kind() == .interactive_read or value.kind() == .mutation;
        const queue = if (high_priority) &self.high else &self.normal;
        const capacity: usize = if (high_priority) high_capacity else normal_capacity;
        if (value.kind() == .refresh_latest) {
            for (queue.items[0..queue.len], 0..) |entry, index| {
                const old = entry.?;
                if (old.kind() == value.kind() and old.owner == value.owner) {
                    if (self.reservations == completion_capacity) return error.RunnerBusy;
                    if (@intFromEnum(value.task_id) == 0) {
                        value.task_id = try self.task_ids.next(value.owner);
                    } else try self.task_ids.claim(value.owner, value.task_id);
                    var removed = queue.removeAt(index);
                    self.publishTerminalLocked(removed, .canceled_before_start);
                    removed.deinit(self.allocator);
                    try queue.push(value, capacity);
                    self.reservations += 1;
                    self.condition.signal(self.sync_backend.io());
                    return;
                }
            }
        }
        if (queue.len == capacity or self.reservations == completion_capacity) return error.RunnerBusy;
        if (@intFromEnum(value.task_id) == 0) {
            value.task_id = try self.task_ids.next(value.owner);
        } else try self.task_ids.claim(value.owner, value.task_id);
        try queue.push(value, capacity);
        self.reservations += 1;
        self.condition.signal(self.sync_backend.io());
    }

    fn nextLocked(self: *Runner) ?Command {
        if (self.high.len != 0 and (self.high_streak < high_burst_limit or self.normal.len == 0)) {
            self.high_streak += 1;
            return self.high.pop();
        }
        if (self.normal.pop()) |value| {
            self.high_streak = 0;
            return value;
        }
        if (self.high.pop()) |value| {
            self.high_streak = 1;
            return value;
        }
        return null;
    }

    fn workerMain(self: *Runner, worker_index: usize) void {
        var threaded = std.Io.Threaded.init(self.allocator, .{});
        defer threaded.deinit();
        while (true) {
            self.lock();
            while (!self.stopping and (self.workers_paused or (self.high.len == 0 and self.normal.len == 0)))
                self.condition.waitUncancelable(self.sync_backend.io(), &self.mutex);
            if (self.stopping and self.high.len == 0 and self.normal.len == 0) {
                self.children.cancelAndReap(worker_index);
                self.condition.broadcast(self.sync_backend.io());
                self.unlock();
                return;
            }
            var value = self.nextLocked().?;
            self.active_owner[worker_index] = value.owner;
            self.worker_dequeued = true;
            self.condition.broadcast(self.sync_backend.io());
            while (self.pause_after_dequeue and !self.stopping)
                self.condition.waitUncancelable(self.sync_backend.io(), &self.mutex);
            // Persistent cancellation must be observed after every blocking
            // point and immediately before the adapter starts. Mutations are
            // never reported canceled after admission; they run to a terminal
            // success/failure outcome.
            const canceled = self.cancel[worker_index] and value.kind() != .mutation;
            self.unlock();

            if (canceled) {
                self.lock();
                self.publishTerminalLocked(value, .canceled_before_start);
                self.finishActiveLocked(worker_index);
                self.unlock();
                value.deinit(self.allocator);
                continue;
            }
            var child_context = GitChildContext{ .runner = self, .worker = worker_index, .operation_id = @enumFromInt(@intFromEnum(value.task_id)) };
            const lifecycle: @import("git_snapshot.zig").ChildLifecycle = .{ .context = &child_context, .publishFn = GitChildContext.publish, .canceledFn = GitChildContext.canceled, .reapedFn = GitChildContext.reaped };
            const result: Result = if (value.kind() == .refresh_latest)
                .{ .refresh_latest = blk: {
                    if (std.mem.eql(u8, value.payload.bytes(), "__test_slow_child__")) {
                        const ignored = @import("git_snapshot.zig").runCommandManaged(self.allocator, threaded.io(), lifecycle, &.{ "sh", "-c", "trap '' TERM; exec sleep 30" }) catch break :blk GitSnapshot.parse(self.allocator, "", "", "") catch unreachable;
                        self.allocator.free(ignored);
                        break :blk GitSnapshot.parse(self.allocator, "", "", "") catch unreachable;
                    }
                    break :blk GitSnapshot.captureManaged(self.allocator, threaded.io(), lifecycle) catch {
                        self.lock();
                        self.publishTerminalLocked(value, .failure);
                        self.finishActiveLocked(worker_index);
                        self.unlock();
                        value.deinit(self.allocator);
                        continue;
                    };
                } }
            else
                Result.init(self.allocator, value.kind(), value.payload.bytes()) catch {
                    self.lock();
                    self.publishTerminalLocked(value, if (value.kind() == .mutation) .unknown else .failure);
                    self.finishActiveLocked(worker_index);
                    self.unlock();
                    value.deinit(self.allocator);
                    continue;
                };
            const completion: Completion = .{ .task_id = value.task_id, .op_kind = value.kind(), .owner = value.owner, .generation = value.generation, .operation_id = value.operation_id, .outcome = .{ .success = result } };
            value.deinit(self.allocator);

            self.lock();
            if (!self.completion_admission) {
                self.reservations -= 1;
                self.unlock();
                var rejected = completion;
                rejected.deinit(self.allocator);
                continue;
            }
            const was_empty = self.completion_len == 0;
            self.completions[self.completion_len] = completion;
            self.completion_len += 1;
            self.finishActiveLocked(worker_index);
            if (was_empty) self.notifier.notify() catch {};
            self.condition.broadcast(self.sync_backend.io());
            self.unlock();
        }
    }

    const GitChildContext = struct {
        runner: *Runner,
        worker: usize,
        operation_id: OperationId,
        token: ?ChildToken = null,

        fn publish(raw: *anyopaque, pid: i32) !void {
            const self: *GitChildContext = @ptrCast(@alignCast(raw));
            self.token = try self.runner.publishChild(self.worker, pid, self.operation_id);
        }
        fn canceled(raw: *anyopaque) bool {
            const self: *GitChildContext = @ptrCast(@alignCast(raw));
            self.runner.lock();
            defer self.runner.unlock();
            return self.runner.cancel[self.worker] or self.runner.stopping;
        }
        fn reaped(raw: *anyopaque) void {
            const self: *GitChildContext = @ptrCast(@alignCast(raw));
            if (self.token) |token| _ = self.runner.reapChild(token);
            self.token = null;
        }
    };

    /// Transfers one completion. Draining the last item consumes the wake byte
    /// under the same mutex used by publishers, closing the drain/rearm race.
    pub fn takeCompletion(self: *Runner) ?Completion {
        self.lock();
        defer self.unlock();
        if (self.completion_len == 0) return null;
        const value = self.completions[0].?;
        std.mem.copyForwards(?Completion, self.completions[0 .. self.completion_len - 1], self.completions[1..self.completion_len]);
        self.completion_len -= 1;
        self.completions[self.completion_len] = null;
        self.reservations -= 1;
        self.task_ids.complete(value.owner, value.task_id);
        if (self.completion_len == 0) self.notifier.drain() catch {};
        return value;
    }

    pub fn deinit(self: *Runner) void {
        const allocator = self.allocator;
        self.shutdown();
        self.lock();
        self.completion_admission = false;
        while (self.completion_len != 0) {
            var value = self.completions[self.completion_len - 1].?;
            self.completion_len -= 1;
            self.reservations -= 1;
            value.deinit(allocator);
        }
        self.unlock();
        self.notifier.drain() catch {};
        self.notifier.deinit();
        self.sync_backend.deinit();
        std.debug.assert(self.reservations == 0);
        allocator.destroy(self);
    }

    /// Stops admission, turns every queued accepted command into a terminal
    /// outcome, and joins workers. Completion admission intentionally remains
    /// open until after the join so the reactor can drain outcomes before
    /// calling `deinit`.
    pub fn shutdown(self: *Runner) void {
        if (self.thread_count == 0 and self.stopping) return;
        self.stopAndJoinSpawned();
    }

    pub fn waitUntilWorkerDequeues(self: *Runner) void {
        self.lock();
        defer self.unlock();
        while (!self.worker_dequeued) self.condition.waitUncancelable(self.sync_backend.io(), &self.mutex);
    }

    pub fn waitUntilChildPublished(self: *Runner, worker: usize) void {
        self.lock();
        defer self.unlock();
        while (!self.children.slots[worker].published) self.condition.waitUncancelable(self.sync_backend.io(), &self.mutex);
    }

    pub fn waitUntilCompletionCount(self: *Runner, count: usize) void {
        self.lock();
        defer self.unlock();
        while (self.completion_len < count) self.condition.waitUncancelable(self.sync_backend.io(), &self.mutex);
    }

    /// Cancels queued work for a closed owner and marks a running read stale.
    /// Mutations already running are deliberately allowed to reach a terminal
    /// outcome and are never reported as canceled.
    pub fn cancelOwner(self: *Runner, owner: OwnerId) void {
        self.lock();
        defer self.unlock();
        self.cancelOwnerInLocked(&self.high, owner);
        self.cancelOwnerInLocked(&self.normal, owner);
        for (self.active_owner[0..self.thread_count], 0..) |active, index| {
            if (active != null and active.? == owner) {
                self.cancel[index] = true;
                self.pause_after_dequeue = false;
            }
        }
        self.condition.broadcast(self.sync_backend.io());
    }

    fn cancelOwnerInLocked(self: *Runner, queue: *CommandQueue, owner: OwnerId) void {
        var index: usize = 0;
        while (index < queue.len) {
            if (queue.items[index].?.owner != owner) {
                index += 1;
                continue;
            }
            var value = queue.removeAt(index);
            self.publishTerminalLocked(value, .canceled_before_start);
            value.deinit(self.allocator);
        }
    }

    fn finishActiveLocked(self: *Runner, worker_index: usize) void {
        self.active_owner[worker_index] = null;
        if (!self.stopping) self.cancel[worker_index] = false;
    }

    /// Worker-owned child adapters publish and update slots only through these
    /// mutex-protected methods. The fake-clock controller is the 04B adapter;
    /// later operation modules supply the actual signal/wait/reap calls.
    pub fn publishChild(self: *Runner, worker: usize, pid: i32, operation_id: OperationId) !ChildToken {
        self.lock();
        defer self.unlock();
        if (worker >= self.thread_count) return error.InvalidWorker;
        const token = try self.children.publish(worker, pid, operation_id);
        self.condition.broadcast(self.sync_backend.io());
        return token;
    }

    pub fn advanceChild(self: *Runner, token: ChildToken, elapsed_ms: u64) bool {
        self.lock();
        defer self.unlock();
        return self.children.advance(token, elapsed_ms);
    }

    pub fn reapChild(self: *Runner, token: ChildToken) bool {
        self.lock();
        defer self.unlock();
        const reaped = self.children.reap(token);
        if (reaped) self.condition.broadcast(self.sync_backend.io());
        return reaped;
    }

    fn stopAndJoinSpawned(self: *Runner) void {
        self.lock();
        self.accepting = false;
        self.stopping = true;
        self.workers_paused = false;
        self.pause_after_dequeue = false;
        for (self.cancel[0..self.thread_count]) |*flag| flag.* = true;
        self.children.requestShutdown();
        while (self.high.pop()) |item| {
            var value = item;
            self.publishTerminalLocked(value, if (value.kind() == .mutation) .unknown else .canceled_before_start);
            value.deinit(self.allocator);
        }
        while (self.normal.pop()) |item| {
            var value = item;
            self.publishTerminalLocked(value, .canceled_before_start);
            value.deinit(self.allocator);
        }
        self.condition.broadcast(self.sync_backend.io());
        self.unlock();
        for (self.threads[0..self.thread_count]) |thread_opt| if (thread_opt) |thread| thread.join();
        self.thread_count = 0;
    }

    fn publishTerminalLocked(self: *Runner, value: Command, outcome: Outcome) void {
        std.debug.assert(self.completion_admission);
        std.debug.assert(self.completion_len < completion_capacity);
        const was_empty = self.completion_len == 0;
        self.completions[self.completion_len] = .{
            .task_id = value.task_id,
            .op_kind = value.kind(),
            .owner = value.owner,
            .generation = value.generation,
            .operation_id = value.operation_id,
            .outcome = outcome,
        };
        self.completion_len += 1;
        if (was_empty) self.notifier.notify() catch {};
        self.condition.broadcast(self.sync_backend.io());
    }
};

fn makeCommand(allocator: std.mem.Allocator, kind: Kind, owner: u64, generation: u64, operation_id: ?u64, payload: []const u8) !Command {
    return Command.init(allocator, kind, @enumFromInt(owner), @enumFromInt(generation), if (operation_id) |id| @enumFromInt(id) else null, payload);
}

test "worker count is clamped and failure falls back" {
    try std.testing.expectEqual(@as(usize, 1), workerCount(null));
    try std.testing.expectEqual(@as(usize, 1), workerCount(0));
    try std.testing.expectEqual(@as(usize, 1), workerCount(1));
    try std.testing.expectEqual(@as(usize, 1), workerCount(2));
    try std.testing.expectEqual(@as(usize, 4), workerCount(99));
}

test "queue bounds rejection retains caller ownership" {
    var scheduler = FakeScheduler.init(std.testing.allocator);
    defer scheduler.deinit();
    for (0..high_capacity) |i| try scheduler.submit(try makeCommand(std.testing.allocator, .mutation, 1, 1, i + 1, "h"));
    var rejected_high = try makeCommand(std.testing.allocator, .mutation, 1, 1, 100, "reject");
    defer rejected_high.deinit(std.testing.allocator);
    try std.testing.expectError(error.RunnerBusy, scheduler.submit(rejected_high));
    for (0..normal_capacity) |_| try scheduler.submit(try makeCommand(std.testing.allocator, .read_once, 2, 1, null, "n"));
    var rejected_normal = try makeCommand(std.testing.allocator, .read_once, 2, 1, null, "reject");
    defer rejected_normal.deinit(std.testing.allocator);
    try std.testing.expectError(error.RunnerBusy, scheduler.submit(rejected_normal));
}

test "priority fairness and FIFO are deterministic" {
    var scheduler = FakeScheduler.init(std.testing.allocator);
    defer scheduler.deinit();
    try scheduler.submit(try makeCommand(std.testing.allocator, .read_once, 2, 1, null, "normal"));
    for (0..5) |i| try scheduler.submit(try makeCommand(std.testing.allocator, .mutation, 1, 1, i + 1, &.{@intCast('0' + i)}));
    for (0..5) |_| _ = try scheduler.runOne();
    const expected = [_][]const u8{ "0", "1", "2", "3", "normal" };
    for (expected) |text| {
        var done = scheduler.takeCompletion().?;
        defer done.deinit(std.testing.allocator);
        try std.testing.expectEqualStrings(text, done.outcome.successBytes().?);
    }
}

test "latest refresh replaces queued predecessor without consuming reservation" {
    var scheduler = FakeScheduler.init(std.testing.allocator);
    defer scheduler.deinit();
    try scheduler.submit(try makeCommand(std.testing.allocator, .refresh_latest, 7, 1, null, "old"));
    try scheduler.submit(try makeCommand(std.testing.allocator, .refresh_latest, 7, 2, null, "new"));
    try std.testing.expectEqual(@as(usize, 1), scheduler.reservations);
    _ = try scheduler.runOne();
    var done = scheduler.takeCompletion().?;
    defer done.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("new", done.outcome.successBytes().?);
}

test "owner cancellation and shutdown deinitialize queued payloads" {
    var scheduler = FakeScheduler.init(std.testing.allocator);
    defer scheduler.deinit();
    try scheduler.submit(try makeCommand(std.testing.allocator, .read_once, 1, 1, null, "a"));
    try scheduler.submit(try makeCommand(std.testing.allocator, .read_once, 2, 1, null, "b"));
    scheduler.cancelOwner(@enumFromInt(1));
    try std.testing.expectEqual(@as(usize, 1), scheduler.reservations);
    scheduler.shutdown();
    try std.testing.expectEqual(@as(usize, 0), scheduler.reservations);
    var rejected = try makeCommand(std.testing.allocator, .read_once, 2, 1, null, "c");
    defer rejected.deinit(std.testing.allocator);
    try std.testing.expectError(error.ShuttingDown, scheduler.submit(rejected));
}

test "notifier coalesces and can be drained and rearmed" {
    var notifier = try Notifier.init();
    defer notifier.deinit();
    try notifier.notify();
    try notifier.notify();
    try notifier.drain();
    try notifier.notify();
    try notifier.drain();
}

test "allocation failures preserve ownership paths" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, struct {
        fn run(allocator: std.mem.Allocator) !void {
            var scheduler = FakeScheduler.init(allocator);
            defer scheduler.deinit();
            try scheduler.submit(try makeCommand(allocator, .read_once, 1, 1, null, "owned bytes"));
            _ = try scheduler.runOne();
            var done = scheduler.takeCompletion().?;
            defer done.deinit(allocator);
        }
    }.run, .{});
}

test "owner identity generation operation exhaustion and close fail closed" {
    var registry = OwnerRegistry{};
    const owner = try registry.create();
    try std.testing.expectEqual(@as(u64, 1), @intFromEnum(owner));
    try std.testing.expectEqual(@as(u64, 2), @intFromEnum(try registry.invalidate(owner)));
    try std.testing.expectEqual(@as(u64, 1), @intFromEnum(try registry.nextOperation(owner)));
    registry.find(owner).?.generation = @enumFromInt(std.math.maxInt(u64));
    try std.testing.expectError(error.GenerationExhausted, registry.invalidate(owner));
    registry.find(owner).?.last_operation = std.math.maxInt(u64);
    try std.testing.expectError(error.OperationIdExhausted, registry.nextOperation(owner));
    try std.testing.expect(registry.close(owner));
    try std.testing.expect(registry.generation(owner) == null);
    registry.next_owner = std.math.maxInt(u64);
    _ = try registry.create();
    try std.testing.expectError(error.OwnerIdExhausted, registry.create());
}

test "task reservation rollback and assigned IDs share one sequence" {
    var registry = OwnerRegistry{};
    const owner = try registry.create();
    const reserved = try registry.nextTask(owner);
    try std.testing.expect(registry.rollbackTask(owner, reserved));
    try std.testing.expectEqual(reserved, try registry.nextTask(owner));

    var ids = TaskIdAllocator{};
    try ids.claim(owner, @enumFromInt(1));
    try std.testing.expectEqual(@as(u64, 2), @intFromEnum(try ids.next(owner)));
    try std.testing.expectError(error.TaskIdOutOfSequence, ids.claim(owner, @enumFromInt(2)));
}

fn makeCompletion(allocator: std.mem.Allocator, task_id: TaskId, kind: Kind, owner: OwnerId, generation: Generation, operation_id: ?OperationId, text: []const u8) !Completion {
    return .{ .task_id = task_id, .op_kind = kind, .owner = owner, .generation = generation, .operation_id = operation_id, .outcome = .{ .success = try Result.init(allocator, kind, text) } };
}

test "completion validation disposes stale duplicate and unknown owner exactly once" {
    var registry = OwnerRegistry{};
    const owner = try registry.create();
    const generation = registry.generation(owner).?;
    const task_one = try registry.nextTask(owner);
    var accepted_input = try makeCompletion(std.testing.allocator, task_one, .read_once, owner, generation, null, "accepted");
    var accepted = registry.validate(std.testing.allocator, &accepted_input).?;
    defer accepted.deinit(std.testing.allocator);

    var duplicate = try makeCompletion(std.testing.allocator, task_one, .read_once, owner, generation, null, "duplicate");
    try std.testing.expect(registry.validate(std.testing.allocator, &duplicate) == null);
    _ = try registry.invalidate(owner);
    var stale = try makeCompletion(std.testing.allocator, try registry.nextTask(owner), .interactive_read, owner, generation, null, "stale");
    try std.testing.expect(registry.validate(std.testing.allocator, &stale) == null);
    var unknown = try makeCompletion(std.testing.allocator, @enumFromInt(1), .read_once, @enumFromInt(999), @enumFromInt(1), null, "unknown");
    try std.testing.expect(registry.validate(std.testing.allocator, &unknown) == null);

    const operation = try registry.nextOperation(owner);
    const mutation_task = try registry.nextTask(owner);
    var mutation = try makeCompletion(std.testing.allocator, mutation_task, .mutation, owner, registry.generation(owner).?, operation, "mutation");
    var accepted_mutation = registry.validate(std.testing.allocator, &mutation).?;
    accepted_mutation.deinit(std.testing.allocator);
    var mutation_duplicate = try makeCompletion(std.testing.allocator, mutation_task, .mutation, owner, registry.generation(owner).?, operation, "duplicate");
    try std.testing.expect(registry.validate(std.testing.allocator, &mutation_duplicate) == null);
}

test "Git snapshot completions are rejected after generation change and owner close" {
    var registry = OwnerRegistry{};
    const owner = try registry.create();
    const first_generation = registry.generation(owner).?;
    const stale_id = try registry.nextTask(owner);
    _ = try registry.invalidate(owner);
    var stale = try makeCompletion(std.testing.allocator, stale_id, .refresh_latest, owner, first_generation, null, "stale-branch");
    try std.testing.expect(registry.validate(std.testing.allocator, &stale) == null);

    const current_generation = registry.generation(owner).?;
    const closed_id = try registry.nextTask(owner);
    try std.testing.expect(registry.close(owner));
    var closed = try makeCompletion(std.testing.allocator, closed_id, .refresh_latest, owner, current_generation, null, "closed-branch");
    try std.testing.expect(registry.validate(std.testing.allocator, &closed) == null);
}

test "task completion watermark reclaims sequential history beyond capacity" {
    var registry = OwnerRegistry{};
    const owner = try registry.create();
    const generation = registry.generation(owner).?;
    for (0..completion_capacity + 20) |_| {
        const task_id = try registry.nextTask(owner);
        var input = try makeCompletion(std.testing.allocator, task_id, .read_once, owner, generation, null, "read");
        var accepted = registry.validate(std.testing.allocator, &input).?;
        accepted.deinit(std.testing.allocator);
    }
    try std.testing.expectEqual(@as(u64, completion_capacity + 20), registry.find(owner).?.completed_watermark);
    try std.testing.expectEqual(@as(u64, 0), registry.find(owner).?.completed_ahead);
}

test "reordered repeated reads are accepted and exact task duplicate is rejected" {
    var registry = OwnerRegistry{};
    const owner = try registry.create();
    const generation = registry.generation(owner).?;
    const first = try registry.nextTask(owner);
    const second = try registry.nextTask(owner);
    var later = try makeCompletion(std.testing.allocator, second, .read_once, owner, generation, null, "second");
    var accepted_later = registry.validate(std.testing.allocator, &later).?;
    accepted_later.deinit(std.testing.allocator);
    var earlier = try makeCompletion(std.testing.allocator, first, .read_once, owner, generation, null, "first");
    var accepted_earlier = registry.validate(std.testing.allocator, &earlier).?;
    accepted_earlier.deinit(std.testing.allocator);
    var duplicate = try makeCompletion(std.testing.allocator, second, .read_once, owner, generation, null, "duplicate");
    try std.testing.expect(registry.validate(std.testing.allocator, &duplicate) == null);
    try std.testing.expectEqual(@as(u64, 2), registry.find(owner).?.completed_watermark);
}

test "task admission backpressures a completion gap wider than capacity" {
    var ids = TaskIdAllocator{};
    const owner: OwnerId = @enumFromInt(1);
    var allocated: [completion_capacity]TaskId = undefined;
    for (&allocated) |*id| id.* = try ids.next(owner);
    try std.testing.expectError(error.TaskWindowFull, ids.next(owner));
    // Completing later work does not hide the slow first task.
    for (allocated[1..]) |id| ids.complete(owner, id);
    try std.testing.expectError(error.TaskWindowFull, ids.next(owner));
    ids.complete(owner, allocated[0]);
    _ = try ids.next(owner);
}

test "completion validator rejects a forged unadmitted task id" {
    var registry = OwnerRegistry{};
    const owner = try registry.create();
    var forged = try makeCompletion(std.testing.allocator, @enumFromInt(1), .read_once, owner, registry.generation(owner).?, null, "forged");
    try std.testing.expect(registry.validate(std.testing.allocator, &forged) == null);
}

test "child cancellation escalates at 500ms and stale tokens cannot signal reused pid" {
    var children = FakeChildController{};
    const first = try children.publish(0, 42, @enumFromInt(1));
    children.requestShutdown();
    try std.testing.expect(children.advance(first, 499));
    try std.testing.expect(children.slots[0].graceful_sent);
    try std.testing.expect(!children.slots[0].force_sent);
    try std.testing.expect(children.advance(first, 1));
    try std.testing.expect(children.slots[0].force_sent);
    try std.testing.expect(children.reap(first));
    const reused = try children.publish(0, 42, @enumFromInt(2));
    try std.testing.expect(!children.advance(first, 500));
    try std.testing.expect(children.advance(reused, 500));
}

test "shutdown before child publication is copied into the slot" {
    var children = FakeChildController{};
    children.requestShutdown();
    const token = try children.publish(2, 77, @enumFromInt(9));
    try std.testing.expect(children.slots[2].cancel_requested);
    try std.testing.expect(children.advance(token, 500));
    try std.testing.expect(children.slots[2].force_sent);
}

test "notifier drain boundary publication is never lost" {
    var model = NotifierRaceModel{};
    model.publish();
    try std.testing.expectEqual(@as(usize, 1), model.writes);
    model.consumeAll();
    model.drainRecheck(true);
    try std.testing.expect(model.byte_pending);
    try std.testing.expectEqual(@as(usize, 1), model.queued);
    try std.testing.expectEqual(@as(usize, 2), model.writes);
    model.drainRecheck(false);
    try std.testing.expect(model.byte_pending);
}

test "every partial initialization stage unwinds only initialized resources" {
    const worker_count = max_workers;
    const total_stages = 3 + worker_count;
    for (1..total_stages + 1) |fail_at| {
        var stages = InitStages{};
        try std.testing.expectError(error.InjectedFailure, stages.simulate(worker_count, fail_at));
        try std.testing.expect(!stages.mutex and !stages.notifier and !stages.storage);
        try std.testing.expectEqual(@as(usize, 0), stages.workers);
        try std.testing.expectEqual(fail_at - 1, stages.cleanup_count);
    }
    var successful = InitStages{};
    try successful.simulate(worker_count, total_stages + 1);
    successful.unwind();
    try std.testing.expectEqual(total_stages, successful.cleanup_count);
}

test "production runner idle has no notifier wakeup" {
    var runner = try Runner.init(std.testing.allocator, .{ .worker_count = 1 });
    defer runner.deinit();
    var fds = [_]posix.pollfd{.{ .fd = runner.notifierFd(), .events = posix.POLL.IN, .revents = 0 }};
    try std.testing.expectEqual(@as(usize, 0), try posix.poll(&fds, 0));
}

fn waitRunnerCompletion(runner: *Runner) !Completion {
    var fds = [_]posix.pollfd{.{ .fd = runner.notifierFd(), .events = posix.POLL.IN, .revents = 0 }};
    if (try posix.poll(&fds, 2000) == 0) return error.CompletionTimeout;
    return runner.takeCompletion() orelse error.MissingCompletion;
}

test "production worker owns and publishes an independent result" {
    var runner = try Runner.init(std.testing.allocator, .{ .worker_count = 1 });
    defer runner.deinit();
    try runner.submit(try makeCommand(std.testing.allocator, .read_once, 1, 1, null, "thread result"));
    var done = try waitRunnerCompletion(runner);
    defer done.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("thread result", done.outcome.successBytes().?);
    var fds = [_]posix.pollfd{.{ .fd = runner.notifierFd(), .events = posix.POLL.IN, .revents = 0 }};
    try std.testing.expectEqual(@as(usize, 0), try posix.poll(&fds, 0));
}

test "production notifier writes one byte for a nonempty completion batch" {
    var runner = try Runner.init(std.testing.allocator, .{ .worker_count = 1 });
    defer runner.deinit();
    try runner.submit(try makeCommand(std.testing.allocator, .read_once, 1, 1, null, "one"));
    try runner.submit(try makeCommand(std.testing.allocator, .interactive_read, 1, 2, null, "two"));
    runner.waitUntilCompletionCount(2);

    var byte: [1]u8 = undefined;
    const first = posix.system.read(runner.notifierFd(), &byte, 1);
    try std.testing.expectEqual(posix.E.SUCCESS, posix.errno(first));
    try std.testing.expectEqual(@as(usize, 1), first);
    const second = posix.system.read(runner.notifierFd(), &byte, 1);
    try std.testing.expectEqual(posix.E.AGAIN, posix.errno(second));

    var one = runner.takeCompletion().?;
    one.deinit(std.testing.allocator);
    var two = runner.takeCompletion().?;
    two.deinit(std.testing.allocator);
}

test "production shutdown owns queued and concurrently published work" {
    var runner = try Runner.init(std.testing.allocator, .{ .worker_count = 1, .pause_workers = true });
    for (0..high_capacity) |index|
        try runner.submit(try makeCommand(std.testing.allocator, .mutation, 1, 1, index + 1, "high"));
    for (0..normal_capacity) |_| try runner.submit(try makeCommand(std.testing.allocator, .read_once, 2, 1, null, "normal"));
    var rejected = try makeCommand(std.testing.allocator, .mutation, 1, 1, 100, "full");
    defer rejected.deinit(std.testing.allocator);
    try std.testing.expectError(error.RunnerBusy, runner.submit(rejected));
    runner.deinit();
}

test "production shutdown exposes terminal outcomes before destroy" {
    var runner = try Runner.init(std.testing.allocator, .{ .worker_count = 1, .pause_workers = true });
    try runner.submit(try makeCommand(std.testing.allocator, .mutation, 1, 1, 1, "mutation"));
    try runner.submit(try makeCommand(std.testing.allocator, .read_once, 2, 1, null, "read"));
    runner.shutdown();

    var first = runner.takeCompletion().?;
    defer first.deinit(std.testing.allocator);
    var second = runner.takeCompletion().?;
    defer second.deinit(std.testing.allocator);
    if (first.kind() == .mutation) {
        try std.testing.expect(first.outcome == .unknown);
        try std.testing.expect(second.outcome == .canceled_before_start);
    } else {
        try std.testing.expect(second.outcome == .unknown);
        try std.testing.expect(first.outcome == .canceled_before_start);
    }
    runner.deinit();
}

test "shutdown rechecks cancellation after dequeue while mutation reports outcome" {
    {
        var runner = try Runner.init(std.testing.allocator, .{ .worker_count = 1, .pause_after_dequeue = true });
        try runner.submit(try makeCommand(std.testing.allocator, .read_once, 1, 1, null, "read"));
        runner.waitUntilWorkerDequeues();
        runner.shutdown();
        var done = runner.takeCompletion().?;
        defer done.deinit(std.testing.allocator);
        try std.testing.expect(done.outcome == .canceled_before_start);
        runner.deinit();
    }
    {
        var runner = try Runner.init(std.testing.allocator, .{ .worker_count = 1, .pause_after_dequeue = true });
        try runner.submit(try makeCommand(std.testing.allocator, .mutation, 1, 1, 1, "mutation"));
        runner.waitUntilWorkerDequeues();
        runner.shutdown();
        var done = runner.takeCompletion().?;
        defer done.deinit(std.testing.allocator);
        try std.testing.expect(done.outcome == .success);
        runner.deinit();
    }
}

test "owner close cancellation reaches queued and running reads" {
    var runner = try Runner.init(std.testing.allocator, .{ .worker_count = 1, .pause_after_dequeue = true });
    try runner.submit(try makeCommand(std.testing.allocator, .read_once, 7, 1, null, "running"));
    runner.waitUntilWorkerDequeues();
    try runner.submit(try makeCommand(std.testing.allocator, .refresh_latest, 7, 1, null, "queued"));
    runner.cancelOwner(@enumFromInt(7));
    runner.waitUntilCompletionCount(2);
    var one = runner.takeCompletion().?;
    defer one.deinit(std.testing.allocator);
    var two = runner.takeCompletion().?;
    defer two.deinit(std.testing.allocator);
    try std.testing.expect(one.outcome == .canceled_before_start);
    try std.testing.expect(two.outcome == .canceled_before_start);
    runner.deinit();
}

test "git refresh admission keeps reference input-path latency bounded" {
    var runner = try Runner.init(std.testing.allocator, .{ .worker_count = 1, .pause_workers = true });
    defer runner.deinit();
    var before: posix.timespec = undefined;
    var after: posix.timespec = undefined;
    _ = posix.system.clock_gettime(posix.CLOCK.MONOTONIC, &before);
    try runner.submit(try makeCommand(std.testing.allocator, .refresh_latest, 44, 1, null, "."));
    _ = posix.system.clock_gettime(posix.CLOCK.MONOTONIC, &after);
    const elapsed_ns = (@as(i128, after.sec) - before.sec) * std.time.ns_per_s + (@as(i128, after.nsec) - before.nsec);
    // This measures the reactor-side reference operation, not Git execution:
    // admission must remain far below the former multi-hundred-ms stall.
    try std.testing.expect(elapsed_ns >= 0 and elapsed_ns < 100 * std.time.ns_per_ms);
}

test "production slow Git child shutdown escalates and exactly reaps" {
    var runner = try Runner.init(std.testing.allocator, .{ .worker_count = 1 });
    defer runner.deinit();
    try runner.submit(try makeCommand(std.testing.allocator, .refresh_latest, 55, 1, null, "__test_slow_child__"));
    runner.waitUntilChildPublished(0);
    var sleeper = std.Io.Threaded.init(std.testing.allocator, .{});
    defer sleeper.deinit();
    try std.Io.sleep(sleeper.io(), .fromMilliseconds(100), .awake);
    var admission_before: posix.timespec = undefined;
    var admission_after: posix.timespec = undefined;
    _ = posix.system.clock_gettime(posix.CLOCK.MONOTONIC, &admission_before);
    try runner.submit(try makeCommand(std.testing.allocator, .interactive_read, 56, 1, null, "input-path"));
    _ = posix.system.clock_gettime(posix.CLOCK.MONOTONIC, &admission_after);
    const admission_ns = (@as(i128, admission_after.sec) - admission_before.sec) * std.time.ns_per_s + (@as(i128, admission_after.nsec) - admission_before.nsec);
    try std.testing.expect(admission_ns >= 0 and admission_ns < 100 * std.time.ns_per_ms);
    var before: posix.timespec = undefined;
    var after: posix.timespec = undefined;
    _ = posix.system.clock_gettime(posix.CLOCK.MONOTONIC, &before);
    runner.cancelOwner(@enumFromInt(55));
    runner.shutdown();
    _ = posix.system.clock_gettime(posix.CLOCK.MONOTONIC, &after);
    const elapsed_ns = (@as(i128, after.sec) - before.sec) * std.time.ns_per_s + (@as(i128, after.nsec) - before.nsec);
    try std.testing.expect(elapsed_ns >= 500 * std.time.ns_per_ms);
    try std.testing.expect(elapsed_ns < 1500 * std.time.ns_per_ms);
    try std.testing.expectEqual(@as(usize, 1), runner.children.reap_count);
    var completion = runner.takeCompletion().?;
    defer completion.deinit(std.testing.allocator);
}

test "production child slot inherits shutdown and guards reuse" {
    var runner = try Runner.init(std.testing.allocator, .{ .worker_count = 1 });
    const old = try runner.publishChild(0, 42, @enumFromInt(1));
    runner.shutdown();
    try std.testing.expect(!runner.advanceChild(old, 500));
    try std.testing.expectEqual(@as(usize, 1), runner.children.graceful_count);
    try std.testing.expectEqual(@as(usize, 1), runner.children.force_count);
    try std.testing.expectEqual(@as(usize, 1), runner.children.reap_count);
    runner.deinit();
}

test "production partial spawn injection joins already spawned workers" {
    try std.testing.expectError(error.InjectedSpawnFailure, Runner.init(std.testing.allocator, .{ .worker_count = max_workers, .fail_spawn_at = 2 }));
}

test "production completion publication remains admitted until shutdown join" {
    var runner = try Runner.init(std.testing.allocator, .{ .worker_count = 1, .pause_after_dequeue = true });
    try runner.submit(try makeCommand(std.testing.allocator, .mutation, 1, 1, 1, "in flight"));
    runner.waitUntilWorkerDequeues();
    // deinit releases the worker, permits its already accepted publication,
    // joins it, and only then closes and drains completion admission.
    runner.deinit();
}
