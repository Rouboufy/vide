<div align="center">

```
                  ██╗   ██╗██╗██████╗ ███████╗
                  ██║   ██║██║██╔══██╗██╔════╝
                  ██║   ██║██║██║  ██║█████╗
                  ╚██╗ ██╔╝██║██║  ██║██╔══╝
                   ╚████╔╝ ██║██████╔╝███████╗
                    ╚═══╝  ╚═╝╚═════╝ ╚══════╝
```

**The IDE that hides a terminal. The terminal that wears an IDE.**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Linux-lightgrey.svg)]()
[![Built with](https://img.shields.io/badge/built%20with-Zig%20%2B%20Neovim-green.svg)]()

</div>

---

> [!WARNING]
> **macOS is not supported yet.** Vide is currently Linux-only. macOS support is under active development.

---

## What is Vide?

Vide is a terminal-native Integrated Development Environment built entirely in Zig, using Neovim as its core editing engine.

**The power of a professional IDE, the speed of a terminal, the simplicity of a single binary.**

Vide eliminates the false choice between GUI IDEs and terminal editors. You get full IDE capabilities — an integrated file explorer, an integrated terminal panel, real-time diagnostics, and a configuration interface — wrapped in a high-performance, lightweight terminal application. No bloat. No Electron. No configuration hell.

### Why Choose Vide?

- **Single Binary, Zero Installation Friction:** Ship your development environment anywhere with a binary smaller than most text editors. Works natively over SSH without X11 forwarding or remote extensions.
- **True Performance:** Zig's raw speed means Vide starts instantly, renders responsively, and handles large files effortlessly. No framework overhead, no virtual machines, no startup taxes.
- **Familiar yet Powerful:** Full Neovim compatibility means all your plugins, LSP configurations, and keybindings work out of the box. Everything from Telescope fuzzy finding to TreeSitter highlighting to your favourite plugins just works.
- **Unified Workflow:** Mouse-driven file navigation, integrated terminal, and Neovim all share the same window. No task switching, no terminal juggling. Work naturally with keyboard or mouse.
- **Complete Independence:** Vide uses its own configuration directory and never interferes with your system Neovim setup. Run both side by side.

---

## Architecture

Vide operates as a unified Terminal User Interface (TUI).

Instead of wrapping a terminal emulator or launching multiple discrete processes, Vide handles all terminal rendering directly via a highly optimized, double-buffered drawing engine written in Zig.

Neovim is launched as a hidden, headless subprocess using its native `--embed` protocol. Vide intercepts Neovim's UI commands via Msgpack-RPC and paints them onto the terminal, seamlessly integrating Neovim's power with custom native components.

This architecture ensures:
* **Zero Configuration Constraints:** Vide uses its own isolated configuration path (`~/.config/vide`) and does not interfere with your existing Neovim or shell setups.
* **Unified Interactions:** Mouse clicks and scrolls span naturally across native Zig components (like the file tree) and Neovim buffers.
* **Minimal Footprint:** A single, small binary with only one external dependency (Neovim).

---

## Core Features

### Dual Interface Modes
Vide provides two distinct layouts that can be toggled instantly without losing editor state:
* **IDE Mode:** A comprehensive layout featuring an Activity Bar, an interactive File Explorer, a Tab Bar, a Status Bar, and a resizable bottom Terminal Panel.
* **Zen Mode:** A distraction-free layout where the Neovim editor consumes the entire terminal viewport.

### Native Zig Components
The surrounding UI elements are built natively in Zig for maximum speed and memory efficiency:
* **Interactive File Explorer:** Directly queries the filesystem (`std.fs`), supporting mouse-driven navigation, directory expansion, and real-time Git/Neovim modification indicators.
* **Package Management Widgets:** Custom, full-screen TUI interfaces for both the Lazy plugin manager and the Mason package registry, featuring real-time search filtering and mouse control.
* **Configuration Menu:** A dedicated GUI-like settings panel for adjusting themes, indentation, line numbers, and keybindings on the fly.

### Uncompromised Editor Engine
Vide leverages the full capability of Neovim. Language Server Protocol (LSP), Treesitter parsing, Telescope fuzzy finding, and all standard Neovim plugins function precisely as expected.

---

## Installation

### Prerequisites

Before installing Vide, make sure you have the following:

| Dependency | Minimum Version | Notes |
| :--- | :--- | :--- |
| **Neovim** | `>= 0.10.0` | Required as the editor engine |
| **Zig** | `>= 0.16.0 (master)` | Required to build from source — installed automatically by `setup.sh` if missing |
| **git** | any | Required to clone the repository |
| **curl** | any | Required by `setup.sh` |
| **unzip** | any | Required to install the Nerd Font |
| **A Nerd Font** | — | JetBrainsMono Nerd Font installed automatically by `setup.sh` |
| **True Color terminal** | — | Any modern terminal (Alacritty, Kitty, Ghostty, etc.) |

> [!IMPORTANT]
> Vide manages its own isolated Neovim configuration under `~/.config/vide`. It will **not** modify your existing Neovim setup.

---

### Quick Install (Recommended)

Run the one-line installer. It will automatically:

1. Detect and install missing dependencies (git, curl, unzip, neovim, zig)
2. Clone the Vide repository
3. Build the binary with `zig build -Doptimize=ReleaseFast`
4. Install the binary to `~/.local/bin/vide`
5. Link the Neovim configuration to `~/.config/vide/vide-nvim`
6. Download and cache the JetBrainsMono Nerd Font
7. Bootstrap all Neovim plugins headlessly

```bash
curl -fsSL https://raw.githubusercontent.com/Rouboufy/vide/main/setup.sh | bash
```

After installation, **reopen your terminal** and run:

```bash
vide
```

> [!TIP]
> If `vide` is not found after installation, add `~/.local/bin` to your `PATH`:
> ```bash
> echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc && source ~/.bashrc
> ```

---

### Install from Latest Dev Branch

```bash
curl -fsSL https://raw.githubusercontent.com/Rouboufy/vide/dev/setup.sh | bash
```

---

### Manual Build

If you prefer to build from source yourself:

```bash
# 1. Clone the repository
git clone https://github.com/Rouboufy/vide.git
cd vide

# 2. Build the binary (requires Zig >= 0.16.0)
zig build -Doptimize=ReleaseFast

# 3. Run Vide directly
./zig-out/bin/vide

# 4. (Optional) Install the binary globally
cp ./zig-out/bin/vide ~/.local/bin/vide

# 5. (Optional) Link the configuration
ln -sfn "$(pwd)/config/vide-nvim" ~/.config/vide/vide-nvim
```

---

## Default Keybindings

### TUI Interface Controls

These keybindings are handled directly by the Vide TUI layer:

| Action | Keybinding |
| :--- | :--- |
| **Toggle Zen / IDE Mode** | `Ctrl + Z` |
| **Toggle File Explorer** | `Ctrl + E` |
| **Toggle Terminal Panel** | `Ctrl + T` |
| **Resize Panel Left** | `Alt + ←` |
| **Resize Panel Right** | `Alt + →` |
| **Resize Panel Up** | `Alt + ↑` |
| **Resize Panel Down** | `Alt + ↓` |

### Neovim / Editor Keybindings

These are configured inside Vide's embedded Neovim (`Leader = Space`):

| Action | Keybinding |
| :--- | :--- |
| **Save file** | `Ctrl + S` |
| **Force quit Vide** | `Ctrl + Q` |
| **Close current buffer** | `Ctrl + W` |
| **Open new buffer** | `Ctrl + N` |
| **Next tab** | `Ctrl + Tab` |
| **Previous tab** | `Ctrl + Shift + Tab` |
| **Undo** | `Ctrl + Z` |
| **Redo** | `Ctrl + Y` |
| **Copy to clipboard** | `Ctrl + C` |
| **Cut to clipboard** | `Ctrl + X` |
| **Paste from clipboard** | `Ctrl + V` |
| **Select all** | `Ctrl + A` |
| **Toggle File Explorer** | `Space e` |
| **Toggle IDE / Zen Mode** | `Space m t` |
| **Toggle Bottom Terminal** | `Space j` |
| **Find files (Telescope)** | `Space f f` or `Ctrl + F` |
| **Live grep (Telescope)** | `Space f g` |
| **Open recent files** | `Space f r` |
| **Show all commands** | `Space Space` |
| **Open Settings** | `Space ,` |
| **Show keybinding help** | `Space ?` |
| **Delete without yanking** | `Space d` |
| **Substitute word everywhere** | `Space s` |
| **Paste over selection** | `Space p` (Visual) |
| **Scroll half page down (centered)** | `Ctrl + D` |
| **Scroll half page up (centered)** | `Ctrl + U` |
| **Move lines down** | `J` (Visual) |
| **Move lines up** | `K` (Visual) |

> [!NOTE]
> Core TUI interface keybindings (Ctrl+E, Ctrl+T, Ctrl+Z) can be customized within the internal Settings menu (`Space ,`).

---

## Contributing

Contributions are welcome. Areas of active development include expanding the native Zig widgets, optimizing the Msgpack-RPC bridge, and broadening platform support.

## License

Vide is released under the MIT License. See `LICENSE` for details.
