const std = @import("std");
const posix = std.posix;

/// The reactor is deliberately single-threaded. It owns poll registrations;
/// the caller retains the resources named by their file descriptors and must
/// remove a registration before closing/replacing that resource.
pub const Source = enum {
    terminal_input,
    resize_signal,
    nvim_editor_read,
    nvim_editor_write,
    nvim_terminal_read,
    nvim_terminal_write,
    task_completion,
};

pub const Interest = packed struct {
    read: bool = false,
    write: bool = false,
};

pub const Token = struct {
    slot: u8,
    generation: u64,
};

pub const Ready = struct {
    token: Token,
    source: Source,
    readable: bool,
    writable: bool,
    hung_up: bool,
    failed: bool,
};

pub const Phase = enum(u8) {
    readiness_collection,
    transport_progress,
    normalized_event_dispatch,
    state_update,
    composition,
    flush,
    shutdown,
};

pub const PhaseTracker = struct {
    next: Phase = .readiness_collection,

    pub fn enter(self: *PhaseTracker, phase: Phase) !void {
        if (phase == .shutdown) {
            if (self.next == .shutdown) return error.InvalidReactorPhase;
            self.next = .shutdown;
            return;
        }
        if (phase != self.next) return error.InvalidReactorPhase;
        self.next = switch (phase) {
            .readiness_collection => .transport_progress,
            .transport_progress => .normalized_event_dispatch,
            .normalized_event_dispatch => .state_update,
            .state_update => .composition,
            .composition => .flush,
            .flush => .readiness_collection,
            .shutdown => unreachable,
        };
    }
};

pub const max_sources = 16;

const Slot = struct {
    fd: posix.fd_t = -1,
    source: Source = .terminal_input,
    interest: Interest = .{},
    generation: u64 = 0,
    active: bool = false,
};

pub const ReadySet = struct {
    items: [max_sources]Ready = undefined,
    len: usize = 0,

    pub fn slice(self: *const ReadySet) []const Ready {
        return self.items[0..self.len];
    }

    pub fn find(self: *const ReadySet, source: Source) ?Ready {
        for (self.slice()) |item| if (item.source == source) return item;
        return null;
    }

    /// Dispatches a stable readiness snapshot in registration order. The
    /// callback runs on the reactor thread and must not retain `ready`.
    pub fn dispatch(self: *const ReadySet, context: anytype, comptime handler: anytype) !void {
        for (self.slice()) |ready| try handler(context, ready);
    }
};

pub const Reactor = struct {
    slots: [max_sources]Slot = [_]Slot{.{}} ** max_sources,
    registration_order: [max_sources]u8 = undefined,
    registration_count: usize = 0,

    pub fn add(self: *Reactor, fd: posix.fd_t, source: Source, interest: Interest) !Token {
        if (!interest.read and !interest.write) return error.EmptyInterest;
        for (&self.slots) |*slot| {
            if (slot.active and slot.source == source) return error.DuplicateSource;
        }
        var found_free = false;
        for (&self.slots, 0..) |*slot, index| {
            if (slot.active) continue;
            found_free = true;
            if (slot.generation == std.math.maxInt(u64)) continue;
            slot.generation += 1;
            slot.fd = fd;
            slot.source = source;
            slot.interest = interest;
            slot.active = true;
            self.registration_order[self.registration_count] = @intCast(index);
            self.registration_count += 1;
            return .{ .slot = @intCast(index), .generation = slot.generation };
        }
        if (found_free) return error.GenerationExhausted;
        return error.ReactorFull;
    }

    pub fn remove(self: *Reactor, token: Token) bool {
        const slot = self.validSlot(token) orelse return false;
        slot.active = false;
        slot.fd = -1;
        slot.interest = .{};
        for (self.registration_order[0..self.registration_count], 0..) |slot_index, order_index| {
            if (slot_index != token.slot) continue;
            std.mem.copyForwards(
                u8,
                self.registration_order[order_index .. self.registration_count - 1],
                self.registration_order[order_index + 1 .. self.registration_count],
            );
            self.registration_count -= 1;
            break;
        }
        return true;
    }

    pub fn update(self: *Reactor, token: Token, interest: Interest) !void {
        if (!interest.read and !interest.write) return error.EmptyInterest;
        const slot = self.validSlot(token) orelse return error.StaleToken;
        slot.interest = interest;
    }

    pub fn collect(self: *const Reactor, timeout_ms: i32) !ReadySet {
        var pollfds: [max_sources]posix.pollfd = undefined;
        var slot_indices: [max_sources]u8 = undefined;
        var count: usize = 0;
        for (self.registration_order[0..self.registration_count]) |slot_index| {
            const slot = &self.slots[slot_index];
            var events_mask: i16 = 0;
            if (slot.interest.read) events_mask |= posix.POLL.IN;
            if (slot.interest.write) events_mask |= posix.POLL.OUT;
            pollfds[count] = .{ .fd = slot.fd, .events = events_mask, .revents = 0 };
            slot_indices[count] = slot_index;
            count += 1;
        }

        _ = try posix.poll(pollfds[0..count], timeout_ms);
        var result = ReadySet{};
        for (pollfds[0..count], slot_indices[0..count]) |pollfd, slot_index| {
            if (pollfd.revents == 0) continue;
            const slot = &self.slots[slot_index];
            result.items[result.len] = .{
                .token = .{ .slot = slot_index, .generation = slot.generation },
                .source = slot.source,
                .readable = (pollfd.revents & posix.POLL.IN) != 0,
                .writable = (pollfd.revents & posix.POLL.OUT) != 0,
                .hung_up = (pollfd.revents & posix.POLL.HUP) != 0,
                .failed = (pollfd.revents & (posix.POLL.ERR | posix.POLL.NVAL)) != 0,
            };
            result.len += 1;
        }
        return result;
    }

    fn validSlot(self: *Reactor, token: Token) ?*Slot {
        if (token.slot >= max_sources) return null;
        const slot = &self.slots[token.slot];
        if (!slot.active or slot.generation != token.generation) return null;
        return slot;
    }
};

test "phase order is deterministic" {
    var phases = PhaseTracker{};
    inline for (.{
        Phase.readiness_collection,
        Phase.transport_progress,
        Phase.normalized_event_dispatch,
        Phase.state_update,
        Phase.composition,
        Phase.flush,
    }) |phase| try phases.enter(phase);
    try std.testing.expectEqual(Phase.readiness_collection, phases.next);
    try std.testing.expectError(error.InvalidReactorPhase, phases.enter(.composition));
    try phases.enter(.shutdown);
    try std.testing.expectError(error.InvalidReactorPhase, phases.enter(.shutdown));
}

test "shutdown is a validated terminal transition from every runtime phase" {
    inline for (std.enums.values(Phase)) |stop_before| {
        if (stop_before == .shutdown) continue;
        var phases = PhaseTracker{};
        inline for (std.enums.values(Phase)) |phase| {
            if (phase == stop_before) break;
            try phases.enter(phase);
        }
        try phases.enter(.shutdown);
        try std.testing.expectError(error.InvalidReactorPhase, phases.enter(.readiness_collection));
    }
}

test "removed tokens cannot affect an OS-reused descriptor" {
    var original_pipe: [2]posix.fd_t = undefined;
    try std.testing.expectEqual(posix.E.SUCCESS, posix.errno(posix.system.pipe(&original_pipe)));
    const reused_fd = original_pipe[0];
    var reactor = Reactor{};
    const old = try reactor.add(reused_fd, .terminal_input, .{ .read = true });
    try std.testing.expect(reactor.remove(old));
    _ = posix.system.close(original_pipe[0]);
    _ = posix.system.close(original_pipe[1]);

    var replacement_pipe: [2]posix.fd_t = undefined;
    try std.testing.expectEqual(posix.E.SUCCESS, posix.errno(posix.system.pipe(&replacement_pipe)));
    defer _ = posix.system.close(replacement_pipe[0]);
    defer _ = posix.system.close(replacement_pipe[1]);
    try std.testing.expectEqual(reused_fd, replacement_pipe[0]);

    const replacement = try reactor.add(replacement_pipe[0], .task_completion, .{ .read = true });
    try std.testing.expectEqual(old.slot, replacement.slot);
    try std.testing.expect(old.generation != replacement.generation);
    try std.testing.expect(!reactor.remove(old));
    try std.testing.expectError(error.StaleToken, reactor.update(old, .{ .write = true }));
    try reactor.update(replacement, .{ .read = true, .write = true });
}

test "poll interests can be added and removed" {
    var pipe: [2]posix.fd_t = undefined;
    const rc = posix.system.pipe(&pipe);
    try std.testing.expectEqual(posix.E.SUCCESS, posix.errno(rc));
    defer _ = posix.system.close(pipe[0]);
    defer _ = posix.system.close(pipe[1]);
    var reactor = Reactor{};
    const token = try reactor.add(pipe[0], .task_completion, .{ .read = true });
    const byte = "x";
    try std.testing.expectEqual(@as(usize, 1), posix.system.write(pipe[1], byte.ptr, byte.len));
    const ready = try reactor.collect(0);
    const completion = ready.find(.task_completion) orelse return error.MissingReadiness;
    try std.testing.expect(completion.readable);
    try std.testing.expect(reactor.remove(token));
    try std.testing.expectEqual(@as(usize, 0), (try reactor.collect(0)).len);
}

test "read and future write interests share the same poll seam" {
    var pipe: [2]posix.fd_t = undefined;
    const rc = posix.system.pipe(&pipe);
    try std.testing.expectEqual(posix.E.SUCCESS, posix.errno(rc));
    defer _ = posix.system.close(pipe[0]);
    defer _ = posix.system.close(pipe[1]);

    var reactor = Reactor{};
    _ = try reactor.add(pipe[0], .nvim_editor_read, .{ .read = true });
    _ = try reactor.add(pipe[1], .nvim_editor_write, .{ .write = true });
    try std.testing.expectError(error.DuplicateSource, reactor.add(pipe[0], .nvim_editor_read, .{ .read = true }));
    const ready = try reactor.collect(0);
    const writable = ready.find(.nvim_editor_write) orelse return error.MissingReadiness;
    try std.testing.expect(writable.writable);
}

test "readiness dispatch preserves deterministic registration order" {
    const Context = struct {
        sources: [2]Source = undefined,
        len: usize = 0,

        fn accept(self: *@This(), ready: Ready) !void {
            self.sources[self.len] = ready.source;
            self.len += 1;
        }
    };

    var first_pipe: [2]posix.fd_t = undefined;
    var second_pipe: [2]posix.fd_t = undefined;
    try std.testing.expectEqual(posix.E.SUCCESS, posix.errno(posix.system.pipe(&first_pipe)));
    defer _ = posix.system.close(first_pipe[0]);
    defer _ = posix.system.close(first_pipe[1]);
    try std.testing.expectEqual(posix.E.SUCCESS, posix.errno(posix.system.pipe(&second_pipe)));
    defer _ = posix.system.close(second_pipe[0]);
    defer _ = posix.system.close(second_pipe[1]);

    var reactor = Reactor{};
    _ = try reactor.add(first_pipe[1], .nvim_editor_write, .{ .write = true });
    _ = try reactor.add(second_pipe[1], .nvim_terminal_write, .{ .write = true });
    const ready = try reactor.collect(0);
    var context = Context{};
    try ready.dispatch(&context, Context.accept);
    try std.testing.expectEqual(@as(usize, 2), context.len);
    try std.testing.expectEqual(Source.nvim_editor_write, context.sources[0]);
    try std.testing.expectEqual(Source.nvim_terminal_write, context.sources[1]);
}

test "readiness dispatch preserves registration chronology after slot reuse" {
    var pipes: [3][2]posix.fd_t = undefined;
    for (&pipes) |*pipe| {
        try std.testing.expectEqual(posix.E.SUCCESS, posix.errno(posix.system.pipe(pipe)));
    }
    defer for (pipes) |pipe| {
        _ = posix.system.close(pipe[0]);
        _ = posix.system.close(pipe[1]);
    };

    var reactor = Reactor{};
    const removed = try reactor.add(pipes[0][1], .nvim_editor_write, .{ .write = true });
    _ = try reactor.add(pipes[1][1], .nvim_terminal_write, .{ .write = true });
    try std.testing.expect(reactor.remove(removed));
    const replacement = try reactor.add(pipes[2][1], .task_completion, .{ .write = true });
    try std.testing.expectEqual(removed.slot, replacement.slot);

    const ready = try reactor.collect(0);
    try std.testing.expectEqual(@as(usize, 2), ready.len);
    try std.testing.expectEqual(Source.nvim_terminal_write, ready.items[0].source);
    try std.testing.expectEqual(Source.task_completion, ready.items[1].source);
}

test "generation exhaustion fails closed" {
    var reactor = Reactor{};
    reactor.slots[0].generation = std.math.maxInt(u64);
    const usable = try reactor.add(42, .task_completion, .{ .read = true });
    try std.testing.expectEqual(@as(u8, 1), usable.slot);
    try std.testing.expect(reactor.remove(usable));
    for (&reactor.slots) |*slot| slot.generation = std.math.maxInt(u64);
    try std.testing.expectError(error.GenerationExhausted, reactor.add(42, .task_completion, .{ .read = true }));
}
