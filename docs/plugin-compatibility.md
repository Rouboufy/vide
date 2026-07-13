# Plugin compatibility

Vide is a Neovim UI client, not a normal terminal session running Neovim.
Plugins execute inside Vide's isolated editor process and render through
Neovim's multigrid UI protocol. This boundary matters more than whether a
plugin is written in Lua or Vimscript.

## Plugin ownership

- Bundled plugins are declared in `src/nvim/vide_init.lua`, installed under
  Vide's data directory, and tested with the shipped configuration.
- User-installed Vide plugins are listed in
  `$XDG_DATA_HOME/vide/user_plugins.json`. Their optional configuration files
  live under `$XDG_DATA_HOME/vide/plugin_configs/`.
- System-Neovim plugins and `~/.config/nvim` are unrelated. Vide starts Neovim
  with `--clean` and `NVIM_APPNAME=vide`; it neither loads nor modifies them.

## Tested compatibility

The following bundled modules are covered by `scripts/plugin_smoke.sh`, which
loads the shipped runtime in a disposable XDG environment and verifies that
their public modules load:

| Plugin | Tested surface |
| --- | --- |
| lazy.nvim | manager and shipped plugin specification |
| alpha-nvim | dashboard module |
| telescope.nvim | picker module and Vide multigrid integration hooks |
| mason.nvim | registry UI module; package downloads are not part of this smoke test |
| blink.cmp | completion module availability |
| Harpoon | mark module |

Treesitter, LSP servers, formatters, and Mason packages also depend on external
executables and parsers. Their presence in the bundled specification is not a
claim that every language tool is installed or healthy.

Run the smoke test after bootstrapping plugins:

```bash
scripts/plugin_smoke.sh
```

## Compatibility boundary

Plugins that operate on buffers, windows, diagnostics, completion, or standard
Neovim floating windows are the best fit. Plugins must tolerate `--embed`,
`ext_multigrid`, an external status/tab UI, and Vide's IDE-mode mappings.

The following categories are unsupported unless tested and adapted:

- GUI-client-specific plugins that require Neovide, Goneovim, or another GUI
  API.
- Terminal graphics plugins that write Kitty, Sixel, or iTerm image escape
  sequences directly to Neovim's stdout. That stdout is Vide's RPC transport,
  not the user's terminal.
- Plugins that replace or bypass Neovim's UI protocol by writing directly to
  the outer terminal.
- Plugins that assume the user's normal `~/.config/nvim` runtime or mutate
  global system-Neovim plugin directories.
- Terminal-multiplexer integrations that require ownership of the outer tmux
  pane rather than operating through Neovim commands.

An unlisted plugin is unknown, not implicitly compatible. Install it inside
Vide, keep its configuration isolated, and verify startup, rendering, input,
and shutdown before adding it to the tested table.

If a broken plugin prevents startup, launch Vide once with
`VIDE_DISABLE_PLUGINS=1 vide`. This skips lazy.nvim bootstrap and all bundled
and user plugin setup while preserving plugin files, allowing settings or the
user plugin list to be repaired safely.

Open Settings > Plugins > Plugin Manager and press `s` to synchronize. If
bootstrap was interrupted or Vide started offline, the same action retries
lazy.nvim bootstrap before synchronization. Progress and failures appear as
native notices and detailed Lua errors remain available in Neovim messages and
the Vide log. User plugins can be removed from the extension shop while in a
recovery session; unrelated system-Neovim plugins are never changed.
