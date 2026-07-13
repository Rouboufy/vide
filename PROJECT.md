# VIDE — Project specification

VIDE is a terminal-native IDE written in Zig with Neovim as its editing
engine. It is an application, not a Neovim plugin or a wrapper around the
user's Neovim configuration.

## Product goals

- Make terminal editing approachable with mouse-driven IDE controls.
- Preserve complete Neovim workflows for experienced users.
- Run without a graphical display on Linux, macOS, WSL, and over SSH.
- Keep VIDE's configuration, plugins, cache, state, undo history, and tools
  completely separate from the user's Neovim installation.
- Remain lightweight and responsive without an Electron or browser runtime.

## Editing modes

### Normal

The native VIDE interface surrounds an unrestricted Neovim editor. Users can
mix mouse interactions with Normal, Insert, Visual, and command-line modes and
their usual Vim motions.

### Zen

Neovim receives the terminal viewport except for a single bottom mode row. No
VIDE activity bar, file tree, tab strip, or terminal panel is rendered. The
mode row keeps Zen visible and mouse-switchable. VIDE's bundled plugins and
plugins installed through VIDE remain available.

### IDE

The native interface remains visible, but editable buffers behave like a
modeless text area. Typing inserts text, Escape cannot strand a beginner in
Normal mode, common desktop shortcuts work, and mouse selection is primary.
Special plugin and utility buffers retain the modes they require.

## Runtime architecture

VIDE launches two isolated `nvim --clean --embed --headless` processes:

1. The editor process owns files, LSP clients, plugins, and editing state.
2. A lightweight terminal frontend provides the integrated shell panel. It
   does not load the editor plugin stack, and the shell starts only when the
   panel is opened for the first time.

The Zig frontend communicates with both over MessagePack-RPC, consumes
Neovim's multigrid UI events, composites them with native widgets, and renders
the resulting cell grid using ANSI/VT sequences.

Every child receives `NVIM_APPNAME=vide`. With standard XDG locations this
maps to:

- `~/.config/vide`
- `~/.local/share/vide`
- `~/.local/state/vide`
- `~/.cache/vide`

The user's `~/.config/nvim` and corresponding Neovim data directories are not
loaded or modified.

## Source layout

- `src/main.zig`: process orchestration and the poll-based application loop.
- `src/nvim/`: process management, MessagePack-RPC, UI protocol, and embedded
  Lua runtime.
- `src/tui/`: terminal handling, input parsing, layout, rendering, events, and
  application state.
- `src/tui/widgets/`: native explorer, source-control, settings, package, and
  auxiliary panels.
- `setup.sh`, `update.sh`, `uninstall.sh`: user-local lifecycle scripts.

## Dependencies

At runtime VIDE requires Neovim. Git and network access are needed when
installing or updating plugins. Zig is required only when building from source.
Nerd Fonts are optional; portable text symbols are the default.

## Current engineering priorities

1. Reliable mode and buffer-state synchronization.
2. Correct rendering and input across diverse terminals and small viewports.
3. Reusable widget primitives and consistent keyboard/mouse interaction.
4. Reproducible Linux, macOS, and WSL installation and packaging.
5. Automated coverage for protocol parsing, layout, settings, and lifecycle
   behavior.
