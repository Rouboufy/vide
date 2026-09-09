const std = @import("std");

pub const bucket_count = 128;

/// Fixed-memory, allocation-free distribution of monotonic durations in ns.
/// Buckets are powers of two.  The exact extrema are retained separately so a
/// single short stall can never be hidden by an average or bucket boundary.
pub const Histogram = struct {
    buckets: [bucket_count]u64 = [_]u64{0} ** bucket_count,
    count: u64 = 0,
    total: u128 = 0,
    min: u64 = std.math.maxInt(u64),
    max: u64 = 0,

    pub fn record(self: *Histogram, value: u64) void {
        const index: usize = if (value == 0) 0 else @min(bucket_count - 1, 64 - @clz(value));
        self.buckets[index] +|= 1;
        self.count +|= 1;
        self.total +|= value;
        self.min = @min(self.min, value);
        self.max = @max(self.max, value);
    }

    pub fn minimum(self: *const Histogram) u64 {
        return if (self.count == 0) 0 else self.min;
    }

    pub fn mean(self: *const Histogram) u64 {
        return if (self.count == 0) 0 else @intCast(self.total / self.count);
    }

    pub fn percentile(self: *const Histogram, p: u8) u64 {
        if (self.count == 0) return 0;
        if (p >= 100) return self.max;
        const rank = @max(@as(u64, 1), (@as(u128, self.count) * p + 99) / 100);
        var seen: u64 = 0;
        for (self.buckets, 0..) |n, index| {
            seen +|= n;
            if (seen >= rank) {
                if (index == 0) return 0;
                const upper = (@as(u128, 1) << @intCast(index)) - 1;
                return @intCast(@min(upper, self.max));
            }
        }
        return self.max;
    }

    pub fn p50(self: *const Histogram) u64 {
        return self.percentile(50);
    }
    pub fn p95(self: *const Histogram) u64 {
        return self.percentile(95);
    }
    pub fn p99(self: *const Histogram) u64 {
        return self.percentile(99);
    }
};

pub const Metrics = struct {
    enabled: bool = false,
    poll_wakeup: Histogram = .{},
    input_decode: Histogram = .{},
    rpc_decode: Histogram = .{},
    callback_dispatch: Histogram = .{},
    state_update: Histogram = .{},
    layout: Histogram = .{},
    composition: Histogram = .{},
    ansi_encoding: Histogram = .{},
    writer_flush: Histogram = .{},
    blocking_io_git: Histogram = .{},
    blocking_io_log: Histogram = .{},
    blocking_io_settings: Histogram = .{},
    blocking_rpc: Histogram = .{},

    emitted_bytes: u64 = 0,
    rendered_cells: u64 = 0,
    dirty_cells: u64 = 0,
    dirty_regions: u64 = 0,
    frame_count: u64 = 0,
    queue_depth: u64 = 0,
    cancelled_tasks: u64 = 0,
    stale_tasks: u64 = 0,
    coalesced_events: u64 = 0,
    editor_resize_requests: u64 = 0,
    terminal_resize_requests: u64 = 0,

    pub fn reset(self: *Metrics) void {
        const enabled = self.enabled;
        self.* = .{ .enabled = enabled };
    }

    /// Emits aggregate numbers only.  No API accepts payload text, file data,
    /// command arguments, or keystrokes, making accidental redaction leakage
    /// structurally impossible.
    pub fn exportJson(self: *const Metrics, writer: *std.Io.Writer) !void {
        try writer.writeAll("{\"durations_ns\":{");
        inline for (duration_fields, 0..) |field, i| {
            if (i != 0) try writer.writeByte(',');
            const h = &@field(self, field);
            try writer.print("\"{s}\":{{\"count\":{d},\"min\":{d},\"mean\":{d},\"max\":{d},\"p50\":{d},\"p95\":{d},\"p99\":{d}}}", .{
                field, h.count, h.minimum(), h.mean(), h.max, h.p50(), h.p95(), h.p99(),
            });
        }
        try writer.writeAll("},\"counters\":{");
        inline for (counter_fields, 0..) |field, i| {
            if (i != 0) try writer.writeByte(',');
            try writer.print("\"{s}\":{d}", .{ field, @field(self, field) });
        }
        try writer.writeAll("}}\n");
    }
};

pub const duration_fields = .{
    "poll_wakeup",     "input_decode",         "rpc_decode",    "callback_dispatch", "state_update",
    "layout",          "composition",          "ansi_encoding", "writer_flush",      "blocking_io_git",
    "blocking_io_log", "blocking_io_settings", "blocking_rpc",
};

pub const counter_fields = .{
    "emitted_bytes",            "rendered_cells",  "dirty_cells", "dirty_regions",    "frame_count",
    "queue_depth",              "cancelled_tasks", "stale_tasks", "coalesced_events", "editor_resize_requests",
    "terminal_resize_requests",
};

pub var global: Metrics = .{};

pub fn monotonicNs() u64 {
    var ts: std.posix.timespec = undefined;
    if (std.posix.system.clock_gettime(std.posix.CLOCK.MONOTONIC, &ts) != 0) return 0;
    return @as(u64, @intCast(ts.sec)) * std.time.ns_per_s + @as(u64, @intCast(ts.nsec));
}

pub const ScopedTimer = struct {
    histogram: ?*Histogram,
    started_ns: u64,

    pub inline fn start(metrics: *Metrics, histogram: *Histogram) ScopedTimer {
        if (!metrics.enabled) return .{ .histogram = null, .started_ns = 0 };
        return .{ .histogram = histogram, .started_ns = monotonicNs() };
    }

    pub inline fn stop(self: *ScopedTimer) void {
        if (self.histogram) |histogram| histogram.record(monotonicNs() -| self.started_ns);
        self.histogram = null;
    }
};

test "histogram retains exact extrema mean count and percentile ordering" {
    var h: Histogram = .{};
    for (1..101) |n| h.record(n);
    h.record(50_000_000);
    try std.testing.expectEqual(@as(u64, 101), h.count);
    try std.testing.expectEqual(@as(u64, 1), h.minimum());
    try std.testing.expectEqual(@as(u64, 50_000_000), h.max);
    try std.testing.expectEqual(@as(u64, 50_005_050 / 101), h.mean());
    try std.testing.expect(h.p50() <= h.p95());
    try std.testing.expect(h.p95() <= h.p99());
    try std.testing.expectEqual(@as(u64, 50_000_000), h.percentile(100));
}

test "empty and boundary histograms are defined" {
    var h: Histogram = .{};
    try std.testing.expectEqual(@as(u64, 0), h.minimum());
    try std.testing.expectEqual(@as(u64, 0), h.mean());
    try std.testing.expectEqual(@as(u64, 0), h.p99());
    h.record(0);
    h.record(std.math.maxInt(u64));
    try std.testing.expectEqual(@as(u64, 0), h.minimum());
    try std.testing.expectEqual(std.math.maxInt(u64), h.max);
}

test "metrics counters reset and JSON contains aggregates only" {
    var m: Metrics = .{ .enabled = true };
    inline for (counter_fields, 1..) |field, value| @field(m, field) = value;
    m.layout.record(10);
    var output = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer output.deinit();
    try m.exportJson(&output.writer);
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "\"emitted_bytes\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "\"terminal_resize_requests\":11") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "\"layout\":{\"count\":1") != null);
    m.reset();
    try std.testing.expect(m.enabled);
    inline for (counter_fields) |field| try std.testing.expectEqual(@as(u64, 0), @field(m, field));
    try std.testing.expectEqual(@as(u64, 0), m.layout.count);
}

test "disabled scoped timer has no clock or histogram effect" {
    var m: Metrics = .{};
    var timer = ScopedTimer.start(&m, &m.layout);
    timer.stop();
    try std.testing.expectEqual(@as(u64, 0), m.layout.count);
}
