test "all core modules compile and register their tests" {
    _ = @import("nvim/msgpack.zig");
    _ = @import("nvim/process.zig");
    _ = @import("nvim/rpc.zig");
    _ = @import("nvim/ui_protocol.zig");
    _ = @import("tui/layout.zig");
    _ = @import("tui/input.zig");
    _ = @import("tui/capabilities.zig");
    _ = @import("tui/theme.zig");
    _ = @import("tui/widgets/primitives.zig");
}
