# Vide development TODO

This is the working backlog for Vide. Check an item only after its acceptance
criteria are implemented and verified. Keep completed items in the file so the
project's progress remains visible.

Priority labels:

- **P0** — reliability or data-safety work
- **P1** — important product and usability work
- **P2** — distribution, compatibility, and documentation work
- **P3** — longer-term polish

## P0 — Reliability and protocol coverage

- [x] Build a replayable Neovim UI protocol test harness.
  - Capture or construct `grid_line`, `grid_scroll`, cursor, resize, highlight,
    multigrid, popup, and floating-window event sequences.
  - Include the explicit `repeat = 0` regression that previously erased the
    first character after inserting a newline.
  - Verify exposed rows and columns after scrolling.
  - Verify grid creation, hiding, closing, destruction, and resize ordering.

- [x] Add Unicode and terminal-cell regression coverage.
  - Cover ASCII, CJK, emoji, Nerd Font symbols, combining marks, variation
    selectors, and double-width continuation cells.
  - Test clipping at widget and terminal boundaries.

- [x] Add pseudo-terminal integration tests.
  - Launch Vide with an isolated Neovim instance.
  - Cover startup, shutdown, terminal restoration, resize, typing, newline,
    paste, mouse input, and all three editing modes.
  - Verify failures do not leave the terminal in raw mode or alternate-screen
    mode.

- [x] Audit error handling and remove silent failures at subsystem boundaries.
  - Show actionable native notifications for Neovim startup, plugin bootstrap,
    settings parsing, clipboard providers, LSP setup, Git actions, and terminal
    startup.
  - Preserve detailed diagnostics in the Vide log.
  - Keep recoverable render-loop errors non-fatal.

## P1 — Editing modes and UX

- [x] Make the active mode unmistakable.
  - Display `NORMAL`, `IDE`, or `ZEN` in a consistent location.
  - Add a mouse-accessible mode switch.
  - Explain each mode briefly without requiring knowledge of Vim terminology.
  - Ensure Zen returns to the exact previous mode.

- [x] Complete IDE mode as a predictable modeless editor.
  - Support Shift+arrows, Ctrl/Cmd+arrows, Home/End, word selection, line
    selection, and mouse drag selection.
  - Support copy, cut, paste, select all, undo, redo, save, find, and replace
    using familiar shortcuts where the terminal can distinguish them.
  - Add mouse-accessible file, edit, selection, and buffer actions.
  - Prevent accidental entry into Normal or Visual mode while preserving the
    escape routes required by dialogs and plugins.
  - Test behavior on Linux, macOS, tmux, SSH, and WSL terminals.

- [x] Replace the hardcoded column-80 ruler with a user setting.
  - Remove `vim.opt.colorcolumn = "80"` as an unconditional default.
  - Default the ruler to disabled unless product testing establishes a better
    default.
  - Let users enable it and select its column from Vide's native Settings UI.
  - Consider accepting multiple comma-separated columns, matching Neovim's
    `colorcolumn` format.
  - Validate input and provide a reset/default action.
  - Apply changes immediately to existing and newly opened editor windows.
  - Keep dashboards, terminals, help, settings, and other non-file buffers free
    of the ruler.
  - Persist the setting in Vide's isolated settings file.

- [x] Build a first-run onboarding flow.
  - Let the user choose Normal or IDE mode.
  - Detect Nerd Font, true-color, clipboard, shell, and terminal capabilities.
  - Explain the essential mouse actions and six core shortcuts.
  - Offer language-server installation without making it mandatory.
  - Make onboarding dismissible and reopenable from Help.

- [x] Consolidate native UI primitives.
  - Share border, modal, button, list, scrolling, clipping, focus, and hit-test
    implementations across widgets.
  - Derive drawing and mouse geometry from the same rectangles.
  - Establish consistent keyboard focus, hover, disabled, and selected states.

- [x] Perform a complete UX and accessibility pass.
  - Verify layouts at small and very large terminal sizes.
  - Improve contrast, focus indication, empty states, loading states, and error
    states.
  - Ensure the UI remains usable without Nerd Fonts and without a mouse.
  - Add discoverable tooltips or contextual help where controls are ambiguous.

## P1 — Plugin and tooling experience

- [x] Define and document Vide's plugin compatibility boundary.
  - Distinguish bundled plugins, user-installed Vide plugins, and the user's
    unrelated system-Neovim plugins.
  - Document plugins that require ownership of the outer terminal UI.
  - Maintain a small tested compatibility list and known-incompatibility list.

- [x] Make plugin installation and recovery robust.
  - Show bootstrap and synchronization progress.
  - Support retry, offline startup, and recovery from an interrupted install.
  - Avoid blocking normal startup when optional plugins fail.
  - Provide a safe way to disable a broken user-installed plugin.

- [x] Improve LSP and language setup.
  - Detect the current project languages.
  - Offer relevant Mason packages rather than installing everything.
  - Explain missing executables and failed servers in plain language.
  - Provide a health/status view for active servers, formatters, and linters.

## P2 — Installation, updates, and releases

- [x] Replace source compilation as the default installation path with release
  binaries where practical.
  - Publish Linux x86-64 and ARM64 artifacts.
  - Publish macOS Intel and Apple Silicon artifacts.
  - Verify the Linux artifact under WSL and document any limitations.
  - Retain source builds as a developer and fallback path.

- [x] Update the existing Linux AppImage.
  - Rebuild it from the current codebase.
  - Verify startup, bundled assets, Neovim discovery, isolated XDG paths, and
    desktop integration on multiple distributions.
  - Clearly state whether Neovim is bundled or required on the host.
  - Publish checksums and version information.

- [x] Automate GitHub releases.
  - Build and test release artifacts in CI from version tags.
  - Generate the AppImage and native archives automatically.
  - Attach checksums and concise release notes.
  - Prevent publishing when tests or smoke tests fail.

- [x] Improve `setup.sh`.
  - Add `--dry-run`, `--no-plugins`, and documented noninteractive behavior.
  - Install only dependencies that are missing or too old.
  - Avoid changing system packages before confirmation.
  - Prefer release binaries and fall back to a source build explicitly.
  - Test apt, pacman, dnf, zypper, Homebrew, and WSL paths in CI where possible.

- [x] Improve update and uninstall workflows.
  - Make the installed source/version discoverable by the updater.
  - Refuse to overwrite a dirty developer checkout without explicit consent.
  - Preserve user settings during normal updates.
  - Offer separate uninstall choices for the binary, cache, plugins, settings,
    logs, and sessions.

- [x] Decide and document the supported Zig strategy.
  - Pin a known-good Zig version for reproducible builds.
  - Avoid requiring arbitrary future master snapshots.
  - Discuss a Rust or C migration only after measuring maintenance cost,
    portability, build reproducibility, binary size, and renderer performance.

## P2 — Terminal and platform compatibility

- [ ] Establish a terminal compatibility matrix.
  - Test Kitty, Alacritty, Ghostty, WezTerm, GNOME Terminal, Konsole, macOS
    Terminal, iTerm2, Windows Terminal/WSL, tmux, SSH, and the Linux console.
  - Record color, mouse, paste, modifier-key, Unicode, resize, and clipboard
    behavior.

- [x] Add capability detection and graceful fallbacks.
  - Detect true-color, mouse protocols, bracketed paste, Nerd Font preference,
    clipboard providers, and ambiguous modifier sequences.
  - Fall back to portable symbols and terminal-indexed colors when necessary.
  - Never assume a terminal can distinguish every GUI-style shortcut.

- [ ] Verify macOS and WSL end to end.
  - Test installation, updates, terminal restoration, shell startup, clipboard,
    paths, permissions, plugin installation, LSP installation, and uninstall.

## P2 — Documentation and project website

- [x] Add accurate screenshots and short recordings.
  - Capture Normal, IDE, and Zen modes.
  - Show the file explorer, terminal panel, settings, extension shop, Git panel,
    diagnostics, completion, and mouse interaction.
  - Keep captures synchronized with the current theme and UI.

- [x] Build a GitHub Pages website for Vide.
  - Create a concise landing page with the product description and three-mode
    comparison.
  - Include screenshots, a short demo, installation choices, platform support,
    key features, current limitations, and links to documentation/releases.
  - Design it responsively and keep it usable without heavy JavaScript.
  - Automate deployment from the repository.
  - Reuse project assets and avoid documenting features that are not shipped.

- [x] Expand the README and documentation.
  - Add update and uninstall instructions.
  - Add troubleshooting for PATH, Neovim versions, Zig versions, clipboard,
    fonts, plugin bootstrap, logs, tmux, SSH, macOS, and WSL.
  - Add a limitations section and link to this TODO.
  - Document where Vide stores config, data, state, cache, sessions, and logs.
  - Add contributor build/test instructions and release procedures.

- [x] Add release/version visibility.
  - Implement `vide --version` if the TUI entrypoint can support CLI flags.
  - Show the Vide version, Neovim version, and relevant paths in an About or
    diagnostics view.

## P3 — Build and codebase maintenance

- [x] Replace the generated-template `build.zig` commentary with a concise,
  project-specific build definition.

- [x] Add formatting, tests, ShellCheck, cross-compilation, and documentation
  checks to CI.

- [x] Profile startup, rendering, large files, large directories, and plugin
  initialization before making performance claims.

- [x] Document the architecture and ownership boundaries.
  - Zig frontend and native widgets
  - Neovim processes and Msgpack-RPC
  - Lua editor runtime
  - Python extension-shop helper
  - Settings, sessions, plugins, and XDG storage

## Completion rules

- A checkbox is complete only when the implementation, tests, and user-facing
  documentation are updated together.
- Platform claims require a recorded smoke test on that platform.
- Keybindings documented in the README must be verified against current code.
- Release artifacts must be reproducible from a tag and must report their
  version.
- New settings must have defaults, validation, persistence, live application,
  and reset behavior.
