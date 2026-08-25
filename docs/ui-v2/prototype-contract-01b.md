# UI v2 low-fidelity shell alternatives (Prompt 01B)

Status: proposed for UX review. These are non-interactive cell-level shells,
not runtime UI changes. They deliberately do not select or rank an alternative.
Prompt 01C must evaluate all three with the fixed 01A script.

## Assets and reading rules

The checked-in files under `prototypes-01b/` are exact ASCII cell grids. Every
line occupies exactly the filename's column count and every file has exactly
the filename's row count. ASCII keeps one code point equal to one terminal
cell and avoids font-dependent glyph widths. Brackets indicate focusable
controls, `>` selection, `[FOCUS: name]` keyboard focus, `! Error:` error,
an integer unread count, `Loading...` busy state, and `disabled [? why]` a
disabled action with a discoverable reason. Color is never required.

The grids show a representative editor + Explorer fixture. They are shell
frames, not twelve independent product states: scripted interactions replace
the auxiliary content in the same allocated rectangle or open the overlays
defined below. Hidden surfaces retain their model state.

`prototypes-01b/states/` is the deterministic facilitator deck. Render any
state at any requested size with, for example,
`python3 docs/ui-v2/prototype_harness_01b.py a-labeled problems 80 24`.
The facilitator changes state only when the participant activates a bracketed
pointer control or its documented keyboard/registry equivalent. The output is
always exactly the requested rows and columns. `prototypes-01b/boundaries/`
contains checked-in below/at/above evidence for every accepted width and
height boundary and every alternative.
`transitions-01b.md` fixes event, command, focus-stack, next-state, and
restoration sequences for palette use, terminal, Settings, Zen, T12, editor
owned Telescope/splits, T20 traversal, and deletion.

## Alternative A: labeled collapsible navigation

At 120x40, an 18-cell persistent column spells out primary region names. At
80x24 it collapses to the same three-cell mnemonic rail used at compact width;
the focused mnemonic's full name appears in the adjacent surface heading and
Help. At 60x20 the rail yields to the active auxiliary, leaving editor + one
auxiliary. At 40x12 all navigation is suspended behind Help/palette so the
editor and recovery guidance remain readable.

## Alternative B: mnemonic text rail

A three-cell rail (`E`, `S`, `!`, `G`, `T`, `C`, `?`) persists at comfortable
and compact sizes. Every mnemonic has a full-text target in Help/palette and
the active surface supplies its full heading, so it is not icon-only. The rail
is suspended at constrained and emergency sizes under the same state-retention
rules as A.

## Alternative C: command-first, no permanent rail

No navigation rail consumes editor width. A persistent text command affordance
in the header exposes clickable `[Commands]`, `Ctrl-Shift-P Commands`, and
`F1 Help`; the active
auxiliary has a labeled heading. Pointer users open regions from the command
menu or labeled controls. Constrained and emergency behavior matches the
shared contract. The command registry is prominent here but Help and
contextual surface controls remain separate discoverability routes.

## Shared interaction storyboard

All three shells dispatch the same command IDs and produce the same final
focus, preserved state, cancellation, confirmation, and error behavior. A
prototype facilitator changes only the visible shell state described here;
the deterministic fixture and task wording remain those in
`evaluation-script-01a.md`.

| Script tasks | Prototype transition and visible route |
| --- | --- |
| T1, T2 | Explorer/Open or palette `file.open`; editor edit; `file.save`; tab/previous-buffer return. Pointer Save is visible in the editor action menu. |
| T3 | `!1 Problems` or `problem.open` replaces auxiliary with diagnostic list/details; activating the row focuses its editor location. |
| T4, T5 | Terminal label/control or `terminal.toggle` opens the retained lower/auxiliary surface. It displays `Escape -> terminal; Ctrl-\\ e -> editor`; return control dispatches `terminal.return`. |
| T6, T7 | Source Control or `git.focus` shows fixture file, Stage, commit field and Cancel. Cancel retains the staged state defined by 01A and returns via `focus.editor`. |
| T8, T15 | `settings.open` opens a modal. Dirty close opens nested Save/Discard/Cancel confirmation; Cancel preserves the edit, Discard restores the invoker. |
| T9 | Emergency shell keeps editor, unclipped resize guidance, `help.open`, `palette.open`, and searchable `app.quit`; closing Help restores editor. |
| T10 | Resizing suspends or restores regions without discarding Explorer selection or terminal session; invalid hidden focus falls back to editor. |
| T11 | `mode.zen` hides shell surfaces, retains selection, and focuses editor; leaving Zen restores Explorer focus and selection. |
| T12 | Help is non-modal. Supplied nested confirmation is modal; each authorized Escape dismisses one level. A non-dismissible state says `Choose an action`; input never leaks behind it. |
| T13 | Disabled commit exposes `Missing author identity` through `? why`; resolving fixture identity enables and retries the same command ID. |
| T14 | Every grid exposes focus, selection, error, unread, loading, and disabled states through the textual markers defined above. Emergency legitimately suspends auxiliary states; Help names retained hidden states. |
| T16 | Search/File or palette `search.files` opens fixed results; result activation opens `events.zig`; tab return restores editor. |
| T17 | Search/Text or palette `search.text` opens fixed `FocusTarget` results; query/results remain after opening and return. |
| T18 | Supplied editor-owned Telescope overlay receives movement and Escape unchanged; shell does not consume them and Neovim restores editor focus. |
| T19 | Palette registered split actions dispatch Neovim split commands; Neovim owns grids and selected editor focus. |
| T20 | `focus.next_region`/reverse traverse editor, visible navigation (if present), active auxiliary, and terminal in that order, skipping hidden/disabled targets. |
| T21, T22 | Explorer Actions/context menu requests deletion; identical modal warning and safe Cancel default are used for keyboard and pointer routes; cancel restores Explorer. |

The deck state names are `default`, `action-menu`, `problems`, `terminal`,
`git`, `settings-dirty`, `nested-confirmation`, `help`, `command-palette`, `zen`,
`disabled-reason`, `file-search`, `text-search`, `telescope`, `splits`, and
`delete-confirmation`. Bracketed controls are pointer hit targets and keyboard
focus stops. Enter/click activates the same command; Tab/Shift-Tab moves within
an overlay; F6/Shift-F6 traverses regions outside modals. `action-menu`
supplies the explicit pointer Save and split actions for all alternatives.
The facilitator records the command ID from the 01A mapping before switching
to the named next state, making the keyboard and pointer paths reproducible.
The traversal states make every applicable forward and reverse T20 stop
independently renderable. At the 80x24 reset fixture A/B generate Editor,
Navigation, and Auxiliary; C generates Editor and Auxiliary because it has no
rail. None generates Terminal because the reset terminal session is not
started. The five `t12-*` states separately render the parent Help,
dismissible child, restored parent, non-dismissible child, and repeated-Escape
stop condition. Zen, Telescope, and splits use dedicated full-editor layouts;
they are not auxiliary-panel substitutions.

## Overlay shells and focus rules

Modal frame: title contains `[DIALOG]`, body contains the question/error, the
focused control is bracketed, and the footer names allowed close/cancel keys.
Nested overlays remain inside the parent frame. Non-dismissible modals replace
close text with `Choose an action`; clicks outside do nothing. Non-modal Help,
palette, Problems details, search results, terminal, Git, and Explorer show
`Return to <invoker>` and restore that target if still valid. If invalid, they
restore the most recent visible target, then editor.

At 120x40/80x24/60x20, auxiliary surfaces reuse the right-hand rectangle so
controls never overlap editor cells. At 40x12, modal content replaces the
editor rectangle rather than floating over clipped recovery text. The active
modal receives input first; otherwise terminal prefix, focused target, and
shell routing follow 01A exactly.

## Responsive derivation

The primary assets exercise the accepted minima rather than introducing alternative
breakpoints: 120x40 is comfortable (>=112x27), 80x24 compact (>=79x20),
60x20 constrained by width, and 40x12 emergency. Width and height are resolved
independently, with the effective tier being the more restrictive axis. The
The boundary deck covers 39/40/41, 59/60/61, 78/79/80, and 111/112/113
columns at 27 rows, plus 11/12/13, 14/15/16, 19/20/21, and 26/27/28 rows at
120 columns. It proves deterministic tier selection and exact geometry. The
ten-crossing focus/state/redraw exercise remains Prompt 01C evaluator work;
01B does not claim participant validation.

All alternatives intentionally converge in emergency presentation after the
identity header. At that tier the accepted contract prioritizes the same
editor, recovery/resize guidance, semantic-state Help, and quit access over
each alternative's navigation treatment. The verifier checks this convergence
at representative width- and height-caused emergency sizes; retained state
and command semantics remain identical rather than being discarded.

The alternatives also converge on the constrained editor + one-auxiliary body
because the accepted 40-column editor and 19-column auxiliary minima leave no
room for either navigation treatment at 60 columns. Alternative C retains its
explicit `[Commands]` pointer control in the header; A and B retain their
navigation identity in Help/palette and restore it unchanged above the tier.

No state is persisted by these prototypes. Remove this document, generator,
verifier, and `prototypes-01b/` to roll back 01B without affecting runtime or
accepted 01A evidence.
