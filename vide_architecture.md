# Vide: Deep-Dive Architecture & Internal Documentation

This document provides a rigorous, code-level explanation of how **Vide** operates. Vide is a custom Neovim frontend written in **Zig**, which constructs a VSCode-like Terminal User Interface (TUI) inside a standard terminal emulator while seamlessly proxying edits to headless Neovim instances.

---

## 1. Core Philosophy & Design

Vide is completely detached from `ncurses` or standard TUI frameworks. It manages the terminal directly via ANSI escape codes and raw `ioctl` syscalls.

To create the illusion of a split-pane IDE without interfering with the user's primary Neovim buffer list (avoiding the mess of tracking `:terminal` buffers inside the editor), Vide spawns **two distinct Neovim processes**:
1. **Editor Instance**: Handles the actual code, LSP, Telescope, and syntax highlighting.
2. **Terminal Instance**: Runs solely to provide an embedded shell (like the bottom panel in VSCode).

Vide acts as a visual multiplexer: it reads the UI grids from both Neovim instances via Msgpack-RPC, composites them with its own native Zig UI widgets (Sidebars, Tab bars), and flushes the combined frame to the screen.

---

## 2. Directory Structure & Modular Breakdown

Following the recent architectural refactoring, the codebase is cleanly separated by domain:

### `src/main.zig`
The orchestration core (now ~470 lines).
- Sets up non-blocking pipes, initializes the `App` state, spawns the Neovim child processes, and enters the `poll()` event loop.
- Delegates to the event router when terminal input arrives and to the view router when the screen needs repainting.

### `src/tui/app.zig`
The centralized global state manager.
- Contains the `App` struct which holds pointers to the `Renderer`, the `RpcClient` instances, and all instantiated widgets (`Explorer`, `SettingsWidget`, `GitPanel`, etc.).
- Maintains critical UI tracking variables such as `mode` (`.ide` vs `.zen`), `terminal_panel_height`, `file_tree_width`, and the currently active tab.
- Contains the `UiState` struct, which is the internal representation of the Neovim grid.

### `src/tui/renderer.zig`
The low-level drawing engine.
- Maintains two massive arrays of `Cell` structs: a `back_buffer` (what is currently on the physical screen) and a `front_buffer` (what we want to draw this frame).
- Exposes `drawRect`, `drawText`, and `setCell`.
- In `flush()`, it iterates over every cell. If a cell in the front buffer differs from the back buffer, it outputs the exact ANSI escape sequence to move the cursor (`\x1b[{y};{x}H`) and paint the new character and colors (`\x1b[38;2;R;G;Bm`). This double-buffering ensures zero screen tearing.

### `src/tui/events.zig`
The input router.
- `handleKey`: Checks if an open modal widget (like `SettingsWidget`) consumes the key. If not, it checks global hotkeys (like toggling Zen mode). If unhandled, it forwards the key via RPC to the focused Neovim instance.
- `handleMouse`: Maps raw `(x, y)` terminal coordinates to layout blocks. Determines if the user is dragging the sidebar border, clicking a file in the tree, closing a tab, or scrolling a terminal buffer.

### `src/tui/views.zig`
The layout compositor.
- `drawWorkspace()`: Computes the screen real estate (`Layout.compute`). It loops over the Editor grid and copies it to the top-right. It loops over the Terminal grid and copies it to the bottom panel. Finally, it overlays the native Zig widgets (Activity Bar, Status Bar) on top.

### `src/nvim/`
The Neovim abstraction layer.
- `process.zig`: Handles `std.process.Child` to spawn `vim --embed`.
- `msgpack.zig`: A custom Msgpack parser that decodes Neovim's binary RPC protocol into Zig `Value` unions.
- `rpc.zig`: The asynchronous client that reads msgpack packets, tracks request IDs, and fires the `on_notification` callback.
- `ui_protocol.zig`: The state machine that interprets Neovim's UI events (like `grid_line`, `grid_scroll`, `grid_cursor_goto`) and applies them to the local `Grid` object.
- `helpers.zig`: Utility wrappers for common RPC calls (e.g., `openFile` sends `vim.cmd('edit ...')`).

---

## 3. The Lifecycle of a Keystroke

To understand how Vide operates, consider what happens when the user presses `a` to enter Insert Mode:

1. **Input Parsing (`input.zig`)**: The host terminal receives the raw byte `0x61`. `input.zig` parses this and returns an `Event{ .key = { .raw = "a" } }`.
2. **Event Routing (`events.zig`)**: The `poll()` loop passes the event to `handleKey()`. No widget claims the key, and it's not a Vide-specific shortcut.
3. **RPC Transmission (`helpers.zig`)**: Vide constructs a Msgpack array `["nvim_input", ["a"]]` and writes it to the standard input pipe of the Editor Neovim instance.
4. **Neovim Processing**: Headless Neovim receives the input, switches to Insert Mode, and realizes the UI grid has changed.
5. **RPC Reception (`ui_protocol.zig`)**: Neovim sends a `redraw` notification over standard output. Vide's `rpc.zig` parses the msgpack and triggers `handleRedraw()`. 
6. **Grid Mutation**: Vide processes the `grid_line` events, updating the `Cell` data in its local `UiState.grid`. It also receives a `mode_info_set` event to change the cursor shape.
7. **View Render (`views.zig`)**: Because the state changed, Vide triggers `views.drawWorkspace()`, which copies the updated grid to the `Renderer` front buffer.
8. **Flush (`renderer.zig`)**: `renderer.flush()` diffs the buffers and sends the minimal ANSI string (e.g., `\x1b[10;5H\x1b[38;2;...ma`) to the host terminal to render the letter 'a' at the cursor position.

---

## 4. The Native Widget Ecosystem

Vide includes several native Zig widgets that overlay the Neovim editor.

- **Activity Bar (`activity_bar.zig`)**: The vertical icon strip on the far left. Clicking icons switches the `active_idx`, which determines which panel populates the File Tree area.
- **Explorer (`explorer.zig`)**: A recursive directory parser. It uses `std.fs.IterableDir` to build a visual tree of the current working directory. Clicking a file triggers `nvim_helpers.openFile()`.
- **Git Panel (`git_panel.zig`)**: Spawns asynchronous `git status` commands via `std.process.Child` to parse unstaged/staged files, providing a visual git diff tree.
- **Search Panel (`search_panel.zig`)**: Acts as a bridge. When invoked, it triggers Telescope inside Neovim (`__CMD__:Telescope live_grep`).
- **Settings (`settings.zig`)**: A graphical JSON editor. When the user modifies options (like `theme` or `line_numbers`) and hits `[ Save ]`, the struct is serialized to `~/.local/share/vide/settings.json`, and immediate `nvim_command` RPC calls are fired to hot-reload the settings in the running Neovim instances.

---

## 5. Theme & Color Synchronization

Vide aims to make the native Zig UI components (like the Explorer sidebar) visually blend with the Neovim colorscheme.

1. **`src/nvim/vide_init.lua`**: This script is automatically sourced into Neovim on boot. It registers an `autocmd` hooked to the `ColorScheme` event.
2. **Color Extraction**: When the user types `:colorscheme tokyonight`, the lua script extracts the active RGB hex values from core highlight groups (like `Normal`, `WinSeparator`, `StatusLine`).
3. **RPC Notification**: Lua executes `vim.rpcnotify(ui_chan, "vide_theme_changed", { bg_editor = "#1a1b26", ... })`.
4. **Theme Ingestion (`theme.zig`)**: Vide intercepts this custom notification, parses the hex codes, and injects them into the `App.active_theme` struct. The next frame drawn by `views.zig` will automatically use these new colors for all sidebars, borders, and tabs.

---

## 6. Edge Cases, Protections, and Robustness

Vide has specific logic to handle complex terminal edge-cases safely:

- **Saturating Arithmetic for Layouts**: When resizing terminal panels (`terminal_panel_height +|= 1`), Vide uses Zig's saturating addition. This prevents `u16` wrapping if a user holds down a resize shortcut.
- **Underflow Defenses**: The code explicitly checks `if (layout.panel.?.y > 0)` before evaluating `m.row == layout.panel.?.y - 1` during mouse clicks, preventing crashes on extreme terminal window sizes.
- **Bracketed Paste Throttling (`input.zig`)**: If the user pastes a massive log file into the terminal, Vide reads the `\x1b[200~` escape sequence. It enforces a strict `2 * 1024 * 1024` (2MB) memory limit on the incoming buffer string to prevent OOM panics before wrapping it in an `nvim_paste` RPC payload.
- **Background Mode Enforcement**: Some Neovim themes rely heavily on `vim.o.background` (light vs dark). Vide explicitly detects themes like `catppuccin-latte` and injects `set background=light` before applying the colorscheme to prevent inverted rendering issues.
- **Msgpack Bounds Validation**: During `grid_scroll` parsing in `ui_protocol.zig`, Vide asserts that the scrolling `top`, `bot`, `left`, and `right` parameters strictly adhere to the internal grid dimensions to prevent segfaults from corrupted RPC streams.
