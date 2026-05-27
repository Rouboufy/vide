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
[![Built on](https://img.shields.io/badge/built%20on-Neovim%20%2B%20WezTerm%20%2B%20Yazi-green.svg)]()

</div>

---

## What is this?

Vide is a **complete development environment** that looks and feels like a modern IDE — and secretly runs on the fastest terminal stack available.

No compromises. Two faces.

| | VS Code / Cursor | Classic Neovim | **Vide** |
|---|---|---|---|
| Mouse support | ✅ | ❌ | ✅ |
| Beginner friendly | ✅ | ❌ | ✅ |
| GPU rendering | ❌ | ❌ | ✅ |
| Terminal-native speed | ❌ | ✅ | ✅ |
| Power user ceiling | Low | Unlimited | Unlimited |
| One-command install | ✅ | ❌ | ✅ |

---

## Two modes. One install.

### 🖥️ IDE Mode *(default)*

Looks like VS Code. Works like VS Code. *Runs on a terminal stack.*

- File tree on the left, tabs on top, error panel on bottom
- Everything is clickable with a mouse
- Zero terminal knowledge required
- Breadcrumb navigation, inline diagnostics, rich statusline

> A user coming from VS Code will feel right at home — and never have to know what a socket RPC is.

### 🧘 Zen Mode *(one keypress away)*

Pure. Fast. Distraction-free.

- Full screen, nothing but your code
- Fuzzy finder replaces the file tree
- Minimal statusline, maximum focus
- Built for SSH sessions, sysadmin work, and power users

> Press `Space m t` to toggle. Press it again to come back. Your buffers, cursor position, and file tree state are preserved.

---

## Installation

```bash
curl -fsSL https://vide.sh/install | sh
```

Or manually:

```bash
git clone https://github.com/Rouboufy/vide
cd vide
bash setup.sh
```

That's it. Open `vide` and you're in IDE mode.

> ✅ Works on macOS, Linux, Arch, Ubuntu, and WSL
> ✅ No sudo required — fully installs to `~/.local/`
> ✅ Never touches your existing Neovim or dotfile configs

---

## The Stack

Three tools. All configured in **Lua**. All best-in-class.

```
┌─────────────────────────────────────────┐
│               WEZTERM                   │
│   GPU rendering · tabs · splits · UX    │
└──────────────┬──────────────────────────┘
               │
       ┌───────┴────────┐
       ▼                ▼
┌────────────┐   ┌─────────────┐
│    YAZI    │◄──►   NEOVIM    │
│ File tree  │   │ LSP · Git   │
│ (Rust I/O) │   │ Treesitter  │
└────────────┘   └─────────────┘
```

**WezTerm** — GPU-accelerated terminal emulator. Handles the window, tabs, splits, and the no-border illusion that makes Vide feel like a native app.

**Neovim** — The editing core. LSP, Treesitter, debugging, Git — everything a modern IDE offers, running at native speed.

**Yazi** — File explorer written in Rust with async I/O. Lives in a WezTerm split pane. Never blocks Neovim, no matter how large your project.

---

## Features

### 🎨 Theme Sync
Pick a colorscheme in Neovim and WezTerm adapts automatically — tabs, borders, background, everything.

Built-in themes: **Catppuccin · TokyoNight · Gruvbox · Rose Pine · Kanagawa · Nord · Cyberdream · Nightfox · Matte Black · Aether**

Press `Space th` to open the live theme picker.

### 🔭 Fuzzy Everything
Find files, grep across your project, jump between open buffers — all from the keyboard.
`Space ff` · `Space fg` · `Ctrl+e` (Harpoon)

### 🌿 Git — First Class
Full LazyGit integration, inline diff signs, hunk staging, blame, and a custom Git log TUI — all from inside the editor.
`Space gg` · `Space gl` · `Space gd`

### 🎓 42 School Ready
- Sudo-free installation (works on 42 cluster machines)
- Automatic SSL bypass for the 42 network proxy
- Node.js auto-upgrade via `nvm` when the system version is too old
- C/C++ toolchain pre-configured out of the box

### 🛡️ Safe by Design
Vide installs into its own isolated directory (`~/.config/vide/`). Your existing Neovim setup, tmux config, and dotfiles are **never touched**.

---

## Keybindings

> All bindings use `Space` as the leader. In IDE mode, everything is also accessible via mouse.

### Navigation

| Key | Action |
|-----|--------|
| `Space m t` | Toggle IDE ↔ Zen mode |
| `Alt + h/j/k/l` | Navigate between panes |
| `Space ff` | Find files |
| `Space fg` | Live grep |
| `Ctrl + e` | Harpoon quick-jump menu |
| `Space e` | Toggle file tree |

### Git

| Key | Action |
|-----|--------|
| `Space gg` | Open LazyGit |
| `Space gl` | Git log |
| `Space gd` | Git diff |
| `Space gb` | Toggle inline blame |
| `] h` / `[ h` | Next / previous hunk |

### Editor

| Key | Action |
|-----|--------|
| `Space th` | Theme picker (live preview) |
| `Space ft` | Floating terminal |
| `Space db` | Return to dashboard |
| `Space ?` | Interactive tutorial |
| `Space hk` | Keybindings quick-reference |

---

## Update

From inside Neovim, press **`u`** on the dashboard.

Or from the terminal:

```bash
bash update.sh
```

## Uninstall

```bash
bash uninstall.sh
```

Vide will ask before removing anything. Your original dotfiles are restored from the backup created during installation.

---

## Roadmap

- [x] Neovim core config (LSP, Treesitter, Git, themes)
- [x] One-command install (macOS + Linux + 42 cluster)
- [ ] WezTerm integration (GPU rendering, no-border window)
- [ ] Yazi file tree in WezTerm split pane
- [ ] IPC bridge Yazi ↔ Neovim
- [ ] IDE / Zen mode toggle
- [ ] Theme sync Neovim ↔ WezTerm
- [ ] Interactive onboarding tutorial
- [ ] WSL full support
- [ ] SSH graceful degradation

---

## Origin

Vide started as [Nmux42](https://github.com/Rouboufy/Nmux42) — a Neovim + Tmux setup built for 42 School students. After a year of use and iteration, the question became: *what if this could be something anyone could use, without ever knowing what a terminal is?*

That question became Vide.

---

## Contributing

PRs welcome. If you're a 42 student, a Neovim enthusiast, or just someone who thinks IDEs should be faster — you're the target audience. Open an issue or submit a pull request.

---

## License

MIT — free to use, fork, and build upon.

---

<div align="center">

*Built with obsession. Runs at the speed of thought.*

</div>
