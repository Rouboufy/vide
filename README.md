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
[![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux%20%7C%20WSL-lightgrey.svg)]()
[![Built with](https://img.shields.io/badge/built%20with-Zig%20%2B%20Neovim-green.svg)]()

</div>

---

## What is Vide?

Vide is a terminal-native Integrated Development Environment built entirely in Zig, using Neovim as its core editing engine.

**The power of a professional IDE, the speed of a terminal, the simplicity of a single binary.**

Vide eliminates the false choice between GUI IDEs and terminal editors. You get full IDE capabilities—integrated file explorer, integrated terminal panel, real-time diagnostics, and a configuration interface—wrapped in a high-performance, lightweight terminal application. No bloat. No Electron. No configuration hell.

### Why Choose Vide?

- **Single Binary, Zero Installation Friction:** Ship your development environment anywhere with a binary smaller than most text editors. Works natively over SSH without X11 forwarding or remote extensions.
- **True Performance:** Zig's raw speed means Vide starts instantly, renders responsively, and handles large files effortlessly. No framework overhead, no virtual machines, no startup taxes.
- **Familiar yet Powerful:** Full Neovim compatibility means all your plugins, LSP configurations, and keybindings work out of the box. Everything from Telescope fuzzy finding to TreeSitter highlighting to your favorite plugins just works.
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
* **Configuration Menu:** A dedicated GUI-like settings panel for adjusting themes, indentations, line numbers, and keybindings on the fly.

### Uncompromised Editor Engine
Vide leverages the full capability of Neovim. Language Server Protocol (LSP), Treesitter parsing, Telescope fuzzy finding, and all standard Neovim plugins function precisely as expected.

---

## Installation

### Prerequisites
* Neovim >= 0.10.0
* A terminal emulator with True Color support
* A Nerd Font (e.g., JetBrainsMono) for proper icon rendering

### Automated Installation (Linux & macOS)
```bash
curl -fsSL https://raw.githubusercontent.com/Rouboufy/vide/main/setup.sh | bash
```

### Manual Build
Ensure Zig (version 0.14.0 or newer) is installed.
```bash
git clone https://github.com/Rouboufy/vide
cd vide
zig build -Doptimize=ReleaseFast
./zig-out/bin/vide
```

---

## Default Keybindings

| Action | Keybinding |
| :--- | :--- |
| **Toggle Zen Mode** | `Ctrl + K` |
| **Toggle File Explorer** | `Ctrl + E` |
| **Toggle Terminal Panel** | `Ctrl + T` |
| **Create New File** | `Ctrl + N` |
| **Find Files (Telescope)** | `Space f f` |
| **Live Grep (Telescope)** | `Space f g` |
| **Resize Panels** | `Alt + Arrow Keys` |

*Note: Core interface toggles can be customized within the internal Settings menu.*

---

## Contributing

Contributions are welcome. Areas of active development include expanding the native Zig widgets, optimizing the Msgpack-RPC bridge, and broadening platform distribution channels.

## License

Vide is released under the MIT License. See `LICENSE` for details.
