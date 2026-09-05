# Workspace sidebar selection

The user selected design 1, Workspace sidebar, on 2026-09-05. This is the
product direction for Normal and Zen; it does not constitute completion of
the earlier participant study in 01C.

Normal replaces the icon activity rail and horizontal buffer tabs with one
24-column sidebar (clamped to preserve at least 24 editor columns). Open files
and eight tools share one scrollable list. Tools reuse the existing explorer,
Git, AI, and extension views; their header returns to the workspace list.
Below 40 columns the sidebar yields its space to the editor. The IDE mode
keeps the existing shell.

The editor header shows the current file and the command-menu binding. The
footer uses the editor background and shows Neovim's editing mode, the focused
region, and the configured Zen binding. Unsaved buffers have an asterisk in
the open-files list. Existing theme colors remain authoritative.

The searchable native command menu works without plugins and uses the same
actions as mouse selection. It accepts batched terminal text and pasted
queries. Enter runs the selected command, arrows move selection, and Escape
closes it. File search falls back to Neovim's filename-completing input when
Telescope is unavailable. Close buffer uses the existing unsaved-file-aware
Neovim helper. Switch buffers opens a native searchable list with names, paths,
buffer numbers, and current/modified indicators. It uses the same live buffer
list as the sidebar and supports keyboard selection, mouse selection, scrolling,
and compact/Zen layouts without plugins. Escape returns to the command menu.

F2 or the command's shortcut column records a shortcut directly in the menu.
Assignments save atomically and apply immediately; Escape cancels and duplicate
bindings are rejected across core and additional commands. Save failures leave
the previous binding in effect. The Command menu entry exposes its own binding.
New command bindings are unset by default, and core presets preserve them.

F6 traverses visible regions, with Shift+F6 reversing the order. Zen clears
hidden sidebar/terminal focus, retains their state, and restores focus on exit.
Opening a native sidebar tool or terminal from Zen returns to the prior shell.
Native Neovim handoff remains an optional, separate behavior.

Core settings now include save, commands, and next-region bindings. Keyboard
recording, duplicate rejection, reset, and Save & Close are available without
the mouse. Explicit Vim-safe and familiar presets replace only the core
binding fields. Loading existing settings does not replace customized values.
New installations use Ctrl+P for file search; existing Ctrl+F overrides remain
until the user changes or resets them. Shift+F6 remains a fixed reverse-focus
alias, and Neovim mappings remain in its own configuration.

Verification: `zig build test --summary all`, `zig build`,
`python3 tests/pty_integration.py`, and `python3 tests/workspace_ui.py`.
The workspace test runs an isolated tmux socket and XDG directories and checks
the terminal cell grid, file saving, command filtering, keyboard-only shortcut
recording/persistence and preset application, Zen focus restoration, terminal
session survival, and narrow-to-wide resize. Optional `--capture <directory>`
saves Normal, Zen, and command-menu cell captures.

`python3 tests/commands_ui.py` covers shortcut assignment/replacement, conflicts,
cancel, clicking the shortcut column, Ctrl/Alt/function keys, restart persistence,
buffer switching and closing, unsaved-change cancellation, and Zen/compact
buffer lists. Optional `--capture <directory>` saves text and ANSI captures.

## Picker refinement

Telescope now owns its thin rounded borders in Normal, IDE, and Zen; Vide no
longer paints a second frame, shadow, or red close box over those windows.
The prompt is above ascending results, titles identify the operation, and
paths show filenames first. A side preview appears when the editor grid has
at least 110 columns; Alt+P toggles it. Width/height are bounded by the editor
grid and capped at 140 columns / 26 rows. Highlights follow the active
Neovim theme, including subsequent ColorScheme changes.

Files, project search, open/recent buffers, in-file search, help, commands,
and diagnostics share the configuration. Telescope's normal selection and
split mappings remain available: Ctrl+N/P moves, Enter opens, Ctrl+X/V opens
in a horizontal/vertical split, Ctrl+T opens a tab, and Tab marks a result.
Escape closes in one press. Vide's workspace shortcuts yield while a picker
is open, except the configured command-menu and Zen shortcuts, which close
the picker before changing context. The footer offers mouse Open, Mark,
Preview, and Close targets where space permits. Mouse input inside the
editor goes directly to Neovim, not to workspace context menus underneath.

`python3 tests/pickers_ui.py` uses locally installed Telescope/plenary sources
with an isolated tmux socket and XDG directories, without downloading or
changing user plugins. Pass `--plugin-root <directory>` for another install.
It covers search, selection, preview keyboard/mouse controls, opening files,
wide/compact/tiny layouts, Escape, and Normal/Zen transitions. Optional
`--capture <directory>` saves both text and ANSI-color terminal captures.

The sidebar now separates OPEN FILES, PROJECT actions, and TOOLS with bold,
muted headings, horizontal rules, and blank rows between sections. Choices
are indented beneath their headings, with trailing arrows on tool actions.
The current file has a persistent left rail and a subtle bold highlight;
keyboard focus uses an accent background and a leading arrow independently.
Rendering and mouse targets share the same row mapping, and the workspace
integration test covers non-action section rows and scrolling in short windows.
Alternative project-tree/minimal layouts remain proposals.
