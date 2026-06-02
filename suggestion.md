# Vide Code Simplification & Maintainability Suggestions

After copying and analyzing the `vide` directory and studying the codebase (particularly `src/main.zig`), it is clear that the application has a very solid and performant foundation. However, as the project grows, the monolithic nature of `main.zig` (which currently exceeds 1,300 lines) will make it increasingly difficult to maintain and more prone to errors. 

To make the codebase easier to maintain, less error-prone, and more welcoming to new contributors, I suggest breaking down `main.zig` into smaller, focused modules. Below is a comprehensive plan on how to simplify the code structurally.

## 1. Extract Application State into an `App` Struct
**Current Issue:**
State variables like `mode`, `activity_bar`, `last_click_x`, `tabs`, and layout metrics are defined as local variables inside `innerMain` and then passed down. This results in function signatures that are far too large, such as `runNvimSession` which currently takes **14 arguments**.

**Suggestion:**
Create an `App` (or `Editor`) context struct to encapsulate the global/session state. 

```zig
// In src/app.zig or at the top of main.zig
pub const App = struct {
    allocator: std.mem.Allocator,
    term: *Terminal,
    renderer: *Renderer,
    rpc: *RpcClient,
    rpc_term: *RpcClient,
    ui_state: *UiState,
    ui_term: *UiState,
    mode: Mode,
    activity_bar: ActivityBar,
    tabs: std.array_list.Managed(TabInfo),
    active_tab: usize,
    terminal_focus: bool,
    // ... other state fields

    pub fn init(...) !App { ... }
    pub fn deinit(...) void { ... }
};
```
**Benefit:** You can then pass a single `*App` pointer to functions, significantly reducing boilerplate and the risk of passing the wrong argument.

## 2. Separate Event Handling Logic
**Current Issue:**
The event loop in `main.zig` contains massive `switch` statements to handle keyboard inputs (`.key`) and mouse inputs (`.mouse`). This mixes input routing logic tightly with application business logic.

**Suggestion:**
Extract this logic into dedicated event handler functions.

```zig
// In src/events.zig or a dedicated section
pub fn handleKey(app: *App, key: []const u8) !void {
    // Process keyboard shortcuts, settings toggle, new file, etc.
}

pub fn handleMouse(app: *App, m: MouseEvent) !void {
    // Process mouse clicks, scrolling, sidebar resizing, etc.
}
```
**Benefit:** This will cut hundreds of lines out of the main event loop, making it much easier to read the high-level application flow.

## 3. Extract UI Rendering Routines
**Current Issue:**
In the main `while(true)` loop, there is a large block of code dedicated to drawing the editor grid, activity bar, tabs, status bar, and terminal panels. 

**Suggestion:**
Move the UI drawing logic into a separate `view` or `ui` module.

```zig
// In src/tui/views.zig
pub fn drawWorkspace(app: *App, layout: Layout, theme: *const Theme) void {
    drawEditorView(app, layout.editor, theme);
    drawSidebar(app, layout.file_tree, theme);
    drawStatusBar(app, layout.status_bar, theme);
    drawTerminalPanel(app, layout.panel, theme);
}
```
**Benefit:** UI code is purely functional based on the state. Separating it makes it easier to test layouts, fix rendering bugs, and add new components without cluttering the main loop.

## 4. Encapsulate Theme and Colors
**Current Issue:**
Theme colors are currently defined as file-level global variables in `main.zig`:
```zig
var bg_editor = Color{ .rgb = .{ .r = 30, .g = 30, .b = 30 } };
var bg_sidebar = Color{ .rgb = .{ .r = 37, .g = 37, .b = 38 } };
// ...
```
**Suggestion:**
Create a `Theme` struct (e.g., in `src/theme.zig`) that holds all colors, along with utility functions like `parseHexColor`.

```zig
pub const Theme = struct {
    bg_editor: Color,
    bg_sidebar: Color,
    // ...

    pub fn default() Theme { ... }
    pub fn updateFromConfig(self: *Theme, map: msgpack.Value.Map) void { ... }
};
```
**Benefit:** Removes global state, prevents accidental modification, and cleanly centralizes the theming logic. The `App` struct can simply hold the active `Theme`.

## 5. Move Neovim RPC Helpers
**Current Issue:**
Helper functions like `openFile`, `sendMouseEvent`, and `handleNotification` are located in `main.zig`.
**Suggestion:**
These functions strictly deal with Neovim's msgpack RPC protocol and should be moved to `src/nvim/rpc.zig` (or a new `src/nvim/helpers.zig`). 

```zig
// In src/nvim/helpers.zig
pub fn sendMouseEvent(rpc: *RpcClient, alloc: std.mem.Allocator, m: input.MouseEvent, col: u16, row: u16) void { ... }
pub fn openFile(rpc: *RpcClient, alloc: std.mem.Allocator, path: []const u8) !void { ... }
```
**Benefit:** Keeps `main.zig` oblivious to the low-level string commands and msgpack formatting required by Neovim.

---

## 6. Refactoring TUI Widgets into a UI Toolkit
**Current Issue:**
Looking at files like `src/tui/widgets/settings.zig` (~32KB), `git_panel.zig` (~19KB), and `mason.zig` (~21KB), a major reason for their large size is the manual drawing of every UI primitive. Every single widget manually draws drop shadows, window borders (using `╭`, `─`, `╮`, `│`, etc.), button brackets, and background rectangles using explicit loops over `x` and `y` coordinates. Mouse clicks are also manually tracked via raw hardcoded coordinate bounds checking.

**Suggestion:**
Build a tiny, reusable **UI Toolkit** (or "Canvas" helpers) for common primitives.
```zig
// In src/tui/ui_toolkit.zig
pub fn drawWindow(ren: *Renderer, rect: Rect, title: []const u8, theme: *const Theme) void {
    drawDropShadow(ren, rect, theme);
    drawBackground(ren, rect, theme);
    drawBorders(ren, rect, theme);
    // Draw title and close buttons automatically
}

pub fn drawButton(ren: *Renderer, x: u16, y: u16, text: []const u8, is_active: bool, theme: *const Theme) void {
    // Standardized bracketed buttons: "[ Save ]"
}
```
**Benefit:**
By using `ui_toolkit.drawWindow(ren, rect, "Settings", theme)`, you can eliminate hundreds of lines of explicit loop drawing code in every widget. This will shrink files like `settings.zig` by more than half, drastically reducing coordinate math errors and making it much easier to globally update the UI's look and feel.

---

### Conclusion
By implementing these structural simplifications, `main.zig` will be reduced from a 1,300+ line monolith to a clean, readable coordinator file (around 200-300 lines) that simply initializes the application context, runs the event loop, and delegates to specialized modules. Furthermore, creating a shared UI Toolkit will shrink the massive widget files and make the entire TUI significantly more maintainable. This will dramatically lower the barrier for future feature additions and debugging.
