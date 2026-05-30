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
[![Version](https://img.shields.io/badge/version-0.1.0--alpha-orange.svg)]()
[![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux%20%7C%20WSL-lightgrey.svg)]()
[![Built with](https://img.shields.io/badge/built%20with-Zig%20%2B%20Neovim-green.svg)]()

</div>

---

## What is Vide?

Vide is a **single-binary TUI IDE** built in Zig that embeds Neovim as its editing engine.

It looks like VS Code. It runs like a terminal app. It works over SSH.

No Electron. No WezTerm. No Yazi. No QuickShell.
**One binary. One dependency: Neovim.**

---

## Two modes. One install.

### 🖥️ IDE Mode *(default)*

```
┌────┬──────────────┬───────────────────────────────┐
│    │  EXPLORER    │                               │
│ A  │              │         NEOVIM                │
│ C  │  ∨ src       │                               │
│ T  │    main.zig  │   your code here              │
│ B  │    build.zig │                               │
│ A  │  > tests/    │                               │
│ R  │              ├───────────────────────────────┤
│    │              │  ⊗ 0  ⚠ 2  diagnostics        │
├────┴──────────────┴───────────────────────────────┤
│  main  src/main.zig    Ln 42    Zig    UTF-8       │
└───────────────────────────────────────────────────┘
```

Everything is mouse-clickable. File tree on the left. Tabs on top.
Zero terminal knowledge required.

### 🧘 Zen Mode *(one keypress away)*

```
┌───────────────────────────────────────────────────┐
│                                                   │
│                    NEOVIM                         │
│               (full screen)                       │
│                                                   │
└───────────────────────────────────────────────────┘
```

Press `Space m t` to toggle. Everything else disappears.
Your buffers, cursor, and file tree state are preserved.

---

## Installation

```bash
curl -fsSL https://vide.sh/install | sh
```

Or build from source:

```bash
git clone https://github.com/Rouboufy/vide
cd vide
zig build -Doptimize=ReleaseFast
./zig-out/bin/vide
```

> ✅ macOS · Linux · WSL
> ✅ No sudo required
> ✅ Works natively over SSH
> ✅ Never touches your existing Neovim config

---

## How it works

Vide is built in **Zig** and embeds Neovim via its native `--embed` protocol.

```
┌─────────────────────────────────────────┐
│             VIDE  (Zig binary)           │
│                                         │
│  Activity Bar  │  File Tree  │  Editor  │
│  (Zig widget)  │ (std.fs)    │ (Neovim  │
│                │             │ viewport)│
│                                         │
│         msgpack-rpc layer               │
└──────────────────────┬──────────────────┘
                       │
                  nvim --embed
              (LSP · Treesitter · Plugins)
```

Vide handles **all rendering** — every pixel of the UI is drawn by Vide using raw VT/ANSI sequences. Neovim runs headless in the background and only handles text editing logic.

This means:
- The activity bar, file tree, tab bar, and status bar are all native Zig widgets
- Full mouse support everywhere, including the file tree
- SSH works out of the box — it's a pure TUI
- One process to debug, one log to read, one binary to ship

---

## Features

### 🎨 VS Code Visual Parity
Vide's IDE mode is designed to match VS Code exactly:
- Interactive settings popup (click the ⚙️ in the sidebar)
- True Modeless IDE Experience: Automatically locks into a VSCode-like mode without escaping to Normal mode.
- `#007ACC` status bar and active tab border
- Nerd Font icons throughout
- Breadcrumb navigation (barbecue-style)

### 💾 Persistent Settings
Vide saves your state instantly to a lightweight `settings.json` file. Your IDE Mode, Zen Mode, Theme, and System Clipboard preferences are perfectly preserved across restarts.

### 🌿 Full Neovim Power
Vide uses Neovim as its editor engine — not a reimplementation, not a stripped version.
LSP, Treesitter, Telescope, LazyGit, every plugin you already use works.

### 🌳 Native File Tree & Terminal Panel
- Built directly on `std.fs`. No external process required.
- Full mouse click and scroll support everywhere, including the file tree and popup menus.
- Integrated Resizable Terminal Panel (Alt+Up / Alt+Down)
- Integrated File Tree Resize (Alt+Left / Alt+Right)

### ⚡ Performance
- Double-buffer renderer — only modified cells are redrawn
- Single binary, ~2-5 MB
- Starts in under 100ms

### 🌐 SSH Native
Pure TUI means Vide works over SSH without any setup.
Zen mode is especially powerful in remote sessions.

---

## Keybindings

> All bindings use `Space` as the leader.

| Key | Action |
|-----|--------|
| `Click ⚙️`  | Open Interactive Settings Menu |
| `Ctrl + K`  | Toggle IDE ↔ Zen mode |
| `Ctrl + E`  | Toggle File Explorer |
| `Ctrl + T`  | Toggle Terminal Panel |
| `Ctrl + N`  | New file |
| `Alt+Arrows`| Resize panels |
| `Space f f` | Find files |
| `Space f g` | Live grep |
| `Space g g` | LazyGit |

---

## Building from source

**Requirements:**
- Zig 0.14+
- Neovim 0.10+

```bash
# Debug build
zig build

# Release build
zig build -Doptimize=ReleaseFast

# Run directly
zig build run
```

---

## Roadmap

- [x] Phase 1 — TUI renderer (raw mode, double buffer, input)
- [x] Phase 2 — Neovim RPC (msgpack, `nvim --embed`, UI protocol)
- [x] Phase 3 — Widgets (activity bar, file tree, tab bar, status bar, terminal)
- [x] Phase 4 — Integration (mouse support, settings persistence, toggle mode, resize)
- [ ] Phase 5 — Distribution (install script, macOS + Linux + WSL)

---

## Origin

Vide started as [Nmux42](https://github.com/Rouboufy/Nmux42) — a Neovim + Tmux distribution built for 42 School students.

After a year of iteration, the question became: *what if the whole thing was one application, with full control over every pixel, working everywhere including SSH, with no external dependencies?*

That question became Vide.

---

## Contributing

PRs welcome. If you know Zig, Neovim, or just care about developer tools — open an issue or submit a pull request.

---

## License

MIT

---

<div align="center">

*Built with obsession. Runs at the speed of thought.*

</div>
