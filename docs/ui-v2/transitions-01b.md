# Prompt 01B deterministic facilitator transitions

The harness renders the named before/after state at the requested dimensions.
For every transition the facilitator accepts either the bracketed pointer
control or the listed keyboard command, records the shared command ID, then
renders the next state. The focus stack is shown explicitly below.

| Sequence | From -- event / command -- to | Focus stack and restoration |
| --- | --- | --- |
| Palette | `default` -- click `[Commands]` or Ctrl-Shift-P / `palette.open` -- `command-palette` -- Close -- `default` | push Editor; Palette owns focus; pop Editor |
| T4 | `default` -- Terminal / `terminal.toggle` -- `terminal` -- click Return or Ctrl-\\ e / `terminal.return` -- `default` | push Editor; Terminal owns focus; pop Editor; terminal session retained |
| T8 | `default` -- `settings.open` -- `settings-dirty` -- Close -- `nested-confirmation` -- Cancel -- `settings-dirty` -- Discard -- `default` | Editor, Settings, Confirmation; each close pops exactly one valid owner |
| T11 | `focus-auxiliary` -- `mode.zen` -- `zen` -- Leave Zen -- `focus-auxiliary` | save Explorer/Auxiliary owner and row selection; Zen makes Editor sole owner; restore Explorer/Auxiliary with the same selection |
| T12a | `t12-parent-help` -- Open child -- `t12-dismissible-child` -- Escape -- `t12-restored-parent` | Editor, Help, Child; Escape pops Child and restores Help |
| T12b | `t12-restored-parent` -- Open blocked child -- `t12-blocked-child` -- repeated Escape -- `t12-stop` | Editor, Help, Required dialog; Escape cannot pop non-dismissible dialog and stops without leakage |
| T18 | `default` -- editor mapping -- `telescope` -- Escape/Enter -- `default` | Neovim owns picker and restoration; shell stack is unchanged |
| T19 | `default` -- split command -- `splits` -- close grid 2 -- `default` | Neovim owns grid focus; shell sees one Editor focus target |
| T20 A/B forward | `focus-editor` -- F6 -- `focus-navigation` -- F6 -- `focus-auxiliary` -- F6 -- `focus-editor` | At the 80x24 reset fixture Terminal has not started, so it is not visible and is skipped. |
| T20 A/B reverse | `focus-editor` -- Shift-F6 -- `focus-auxiliary` -- Shift-F6 -- `focus-navigation` -- Shift-F6 -- `focus-editor` | Exact reverse of the visible A/B ring; final owner Editor. |
| T20 C forward | `focus-editor` -- F6 -- `focus-auxiliary` -- F6 -- `focus-editor` | C has no navigation rail and the reset Terminal is not started, so neither is a focus stop. |
| T20 C reverse | `focus-editor` -- Shift-F6 -- `focus-auxiliary` -- Shift-F6 -- `focus-editor` | Exact reverse of the visible C ring; final owner Editor. |
| T13 | `default` -- participant discovers disabled Commit through `disabled [? why]` or a valid palette route -- `disabled-reason` -- supplied prerequisite resolves -- retry same command -- `default` | Editor remains the restoration target; refusal and prerequisite resolution lose no state; retry uses the same command ID |
| T21/22 | `focus-auxiliary` -- delete key/click / Explorer delete -- `delete-confirmation` -- Cancel -- `focus-auxiliary` | push Explorer/Auxiliary; Delete dialog owns focus; cancel restores Explorer/Auxiliary, row selection, and tree |

Failed or removed restoration targets use the accepted 01A fallback: pop to
the most recent visible, enabled, reachable target, otherwise Editor. No
transition forwards native-surface input to an editor or terminal behind it.
