# VIDE architecture

This document describes the current implementation. Product behavior and
platform goals are defined in `PROJECT.md`.

## Process model

`src/main.zig` initializes the real terminal, renderer, isolated environment,
and a self-pipe for resize signals. A session creates an editor Neovim process
and a lightweight terminal frontend process. Both are embedded through
stdin/stdout pipes and receive `NVIM_APPNAME=vide` plus `--clean`. The terminal
frontend loads only `terminal_init.lua`; its shell buffer is created lazily on
first panel activation.

The main loop polls terminal input, both RPC streams, and the resize pipe. It
then applies Neovim notifications to application state, calculates layout,
draws a frame, and flushes changed cells.

## Component boundaries

### Zig frontend

The Zig executable owns process lifecycle, the outer terminal, input decoding,
layout, native widgets, and final rendering. `src/main.zig` wires the
subsystems together; `src/tui/app.zig` holds runtime UI state;
`src/tui/events.zig` routes actions; and `src/tui/views.zig` performs
composition. Widgets may request editor operations through the RPC clients,
but they do not read or mutate Neovim's internal state directly.

### Neovim processes and MessagePack-RPC

`src/nvim/process.zig` is the child-process boundary. The two Neovim children
communicate only through their embedded stdin/stdout channels. The editor
process loads `vide_init.lua` and owns editing and plugin behavior. The
integrated-terminal process loads `terminal_init.lua`; it intentionally avoids
the editor plugin stack. `msgpack.zig`, `rpc.zig`, and `ui_protocol.zig` form
the protocol boundary between those children and the Zig application.

### Lua editor runtime

The Lua files under `src/nvim/` are embedded into the executable at build time.
They configure Neovim options, mappings, IDE-mode behavior, plugins, and the
dashboard. Lua may notify Zig through RPC commands, but native layout and
terminal rendering remain Zig responsibilities. User plugins execute inside
the isolated editor Neovim process, not inside the Zig frontend.

### Python extension-shop helper

`src/nvim/store_search.py` is the only Python runtime component. Zig extracts
the embedded script into the Vide data directory and invokes it as a child
process for extension search, installation, removal, and downloads. It is not
part of rendering or editor RPC. Its stdout is a data interface consumed by
the extension-shop widget; failures must be reported as extension-shop errors
rather than terminating the render loop.

## RPC and rendering

`src/nvim/msgpack.zig` encodes and decodes the MessagePack types used by
Neovim. `src/nvim/rpc.zig` implements requests, responses, and notifications.
RPC stdout remains blocking after readiness polling so a decoder always
finishes one complete frame; collection and payload sizes are bounded.

`src/nvim/ui_protocol.zig` consumes `ext_linegrid`, `ext_multigrid`, and
highlight events. `src/tui/views.zig` composites those grids with native VIDE
widgets. `src/tui/renderer.zig` stores current and previous cell buffers and
emits changed cells using VT escape sequences.

Native modal widgets derive their drawing and mouse geometry from
`src/tui/widgets/primitives.zig`. That module owns centered modal rectangles,
content and close-button hit targets, border/background/shadow rendering, and
scroll clamping. Widgets should extend these primitives instead of introducing
new independent geometry calculations.

## State ownership

Neovim is authoritative for buffers, windows, cursor position, text, undo,
diagnostics, and plugins. It sends buffer-list notifications to VIDE, which
uses them to render and interact with the native tab strip.

Zig is authoritative for interface mode, widget visibility, focus, panel
dimensions, native settings dialogs, and mouse hit testing.

Settings are persisted under VIDE's application data directory. Legacy boolean
mode fields remain readable, but `mode` (`normal`, `ide`, or `zen`) is the
canonical value.

## Storage ownership

Vide derives its directories from the XDG environment and never intentionally
uses the user's standard Neovim application name:

- Config (`$XDG_CONFIG_HOME/vide`, normally `~/.config/vide`) is reserved for
  user-facing configuration.
- Data (`$XDG_DATA_HOME/vide`, normally `~/.local/share/vide`) contains
  `settings.json`, the extracted extension helper, plugin data, session handoff
  files, and `vide.log` in the current implementation.
- State (`$XDG_STATE_HOME/vide`, normally `~/.local/state/vide`) is available
  to Neovim for state that follows its `NVIM_APPNAME=vide` paths.
- Cache (`$XDG_CACHE_HOME/vide`, normally `~/.cache/vide`) contains disposable
  Neovim and frontend caches.

The lifecycle scripts preserve all four locations during normal updates. The
uninstaller treats the binary, settings, plugins/data, logs, sessions, and
cache as separate removal choices.

## Failure boundaries

Terminal initialization and Neovim startup are session-critical failures and
must restore terminal state before returning an error. Malformed RPC payloads
must not escape their size limits. Widget refreshes, optional plugins, Git
commands, and extension-helper operations are recoverable boundaries: they
should retain diagnostics and expose an actionable UI message while allowing
the main render loop to continue.

## Mode transitions

- Normal and IDE use the same native layout.
- IDE installs modeless keymaps and an autocmd that returns editable buffers to
  Insert mode.
- Leaving IDE removes those mappings and autocmds.
- Zen assigns the renderer viewport to Neovim except for one persistent mode
  row and suppresses every other native widget.
- Leaving Zen restores the preceding Normal or IDE mode.

An optional native handoff remains available for experimentation, but embedded
Zen is the default and supported path.

## Terminal input

The terminal layer enables raw mode, alternate-screen rendering, bracketed
paste, and SGR mouse reporting. The input parser distinguishes control keys,
CSI/SS3 sequences, UTF-8 input, paste payloads, mouse actions, and resize
events. Native widgets receive events first when focused; remaining editor and
terminal events are translated to Neovim input APIs.

## Portability

Runtime code uses Zig's POSIX and `std.Io` abstractions rather than direct Linux
syscalls. Linux x86-64 and ARM64 musl builds are cross-compiled in CI. macOS
and WSL remain explicit end-to-end verification work in `TODO.md`; sharing a
POSIX implementation does not by itself establish platform support. Terminal
capabilities still vary, so Nerd Font symbols are opt-in and responsive layouts
avoid relying on a fixed viewport.
