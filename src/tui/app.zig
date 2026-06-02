const std = @import("std");
const nvim = @import("../nvim/msgpack.zig");
const ui = @import("../nvim/ui_protocol.zig");
const renderer = @import("renderer.zig");
const input = @import("input.zig");
const rpc_client = @import("../nvim/rpc.zig");
const theme = @import("theme.zig");
const settings = @import("widgets/settings.zig");
const Layout = @import("layout.zig").Layout;
const ActivityBar = @import("widgets/activity_bar.zig").ActivityBar;
const Terminal = @import("terminal.zig").Terminal;
const Explorer = @import("widgets/explorer.zig").Explorer;
const GitPanel = @import("widgets/git_panel.zig").GitPanel;
const SearchPanel = @import("widgets/search_panel.zig").SearchPanel;
const OutputPanel = @import("widgets/output_panel.zig").OutputPanel;
const DebugConsole = @import("widgets/debug_console.zig").DebugConsole;
const MasonWidget = @import("widgets/mason.zig").MasonWidget;
const LazyWidget = @import("widgets/lazy.zig").LazyWidget;
const GitDetailedWidget = @import("widgets/git_detailed.zig").GitDetailedWidget;

pub const Mode = enum { ide, zen };

pub const TabInfo = struct {
    name: []const u8,
    path: ?[]const u8,
};

pub const RpcContext = struct {
    app: *App,
    ui_state: *ui.UiState,
};

pub const App = struct {
    allocator: std.mem.Allocator,
    term: *Terminal,
    ren: *renderer.Renderer,
    rpc: *rpc_client.RpcClient,
    rpc_term: *rpc_client.RpcClient,
    
    ui_state: *ui.UiState,
    ui_term: *ui.UiState,
    
    active_theme: theme.Theme,
    mode: Mode,
    
    tabs: std.array_list.Managed(TabInfo),
    active_tab: usize,
    
    terminal_focus: bool,
    show_file_tree: bool,
    show_terminal_panel: bool,
    
    needs_resize: bool,
    terminal_panel_height: u16,
    active_terminal_panel_idx: u8, // 0=Terminal, 1=Debug, 2=Output

    settings_widget: *settings.SettingsWidget,
    explorer: *Explorer,
    git_panel: *GitPanel,
    search_panel: *SearchPanel,
    output_panel: *OutputPanel,
    debug_console: *DebugConsole,
    mason_widget: *MasonWidget,
    lazy_widget: *LazyWidget,
    git_detailed_widget: *GitDetailedWidget,
    activity_bar: ActivityBar,

    // Mouse tracking state
    is_resizing_sidebar: bool = false,
    is_resizing_panel: bool = false,
    last_click_x: u16 = 0,
    last_click_y: u16 = 0,
    file_tree_width: u16 = 30,
    was_settings_open: bool = false,
    last_explorer_refresh: i64 = 0,

    pub fn init(allocator: std.mem.Allocator, term: *Terminal, ren: *renderer.Renderer, rpc: *rpc_client.RpcClient, rpc_term: *rpc_client.RpcClient, ui_state: *ui.UiState, ui_term: *ui.UiState) App {
        return App{
            .allocator = allocator,
            .term = term,
            .ren = ren,
            .rpc = rpc,
            .rpc_term = rpc_term,
            .ui_state = ui_state,
            .ui_term = ui_term,
            .active_theme = theme.Theme{},
            .mode = .ide,
            .tabs = std.array_list.Managed(TabInfo).init(allocator),
            .active_tab = 0,
            .terminal_focus = false,
            .show_file_tree = true,
            .show_terminal_panel = false,
            .needs_resize = true,
            .terminal_panel_height = 8,
            .active_terminal_panel_idx = 0,
            .settings_widget = undefined,
            .explorer = undefined,
            .git_panel = undefined,
            .search_panel = undefined,
            .output_panel = undefined,
            .debug_console = undefined,
            .mason_widget = undefined,
            .lazy_widget = undefined,
            .git_detailed_widget = undefined,
            .activity_bar = ActivityBar{ .active_idx = 0 },
        };
    }
};
