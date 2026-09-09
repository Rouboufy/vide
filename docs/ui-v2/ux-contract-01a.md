# UI v2 workflow and input contract (Prompt 01A)

Status: proposed for UX approval. This document fixes the evaluation contract
for Prompt 01B; it does not select a shell or change runtime behavior.

## Scope and ownership

This contract refines `program-contract.md`. Neovim remains authoritative for
editor and terminal contents, modes, cursor, buffers, diagnostics, plugins,
and undo. Zig owns the single shell focus owner, surface visibility, overlays,
drawers, layout, hit testing, and rendering. VideNormal and VideIDE are input
policy presets over one shell. VideZen is a reversible presentation state.

01A produces workflow, input, focus, responsive, accessibility, and evaluation
semantics. Cell prototypes, visual styling, implementation, participant
results, and a winning design are out of scope. Prompt 01B must produce every
alternative and viewport combination without changing this script. Prompt 01C
evaluates them and owns the product choice.

## Command and discoverability contract

Every action below has one stable shared command ID. Labels and shortcuts are
metadata, not command identity. Commands expose role, current shortcut,
availability, disabled reason, confirmation policy, effect, and resulting
focus to menus, contextual hints, Help, and the searchable registry.

The discoverability ladder is, in order: persistent region labels or mnemonic
text when space permits; a contextual hint on entering a specialized focus;
visible close/return instructions for overlays and terminal focus; searchable
commands and current shortcuts in Help/palette; and onboarding only for a
concept that cannot be learned safely in context. An icon-only control always
has a text alternative in Help/palette and an accessible label available
without hover. The registry supplements, and never replaces, persistent and
contextual discovery.

Core IDs used by the workflows are `file.open`, `file.save`, `file.close`,
`explorer.focus`, `search.files`, `search.text`, `problem.next`,
`problem.open`, `terminal.toggle`, `terminal.focus`, `terminal.return`,
`git.focus`, `git.stage`, `git.commit`, `settings.open`, `help.open`,
`palette.open`, `focus.editor`, `focus.next_region`, `focus.previous_region`,
`mode.normal`, `mode.ide`, `mode.zen`, and `app.quit`. Slice owners may add
IDs, but may not rename these outcomes per shell.

### Fixed shell input vocabulary

The shell reserves `F1` for `help.open`, `F6`/`Shift-F6` for
`focus.next_region`/`focus.previous_region`, and `Ctrl-Shift-P` for
`palette.open`. These sequences are recognized in every focus target and are
listed in Help and contextual hints. A top modal shadows their normal
execution: `F1` shows that modal's contextual Help inline without moving
focus; `F6`, `Shift-F6`, and `Ctrl-Shift-P` are consumed with the visible
reason `Resolve or cancel this dialog first`. They never escape a focus trap
or reach a surface behind it. Without a modal, they execute normally. No other
unprefixed key is globally consumed while an editor or terminal owns focus.

The terminal escape prefix is `Ctrl-\`. It has no timeout: the prefix indicator
remains visible until exactly one subsequent decoded key arrives. `e` invokes
`terminal.return`, `t` invokes `terminal.toggle`, `?` opens the terminal-focus
Help topic, and a second `Ctrl-\` sends one literal `Ctrl-\` to Neovim. Any
other suffix cancels prefix state and forwards the original `Ctrl-\` bytes and
suffix bytes, in order and unchanged, to the focused terminal in one input
operation. Resize/resume does not cancel an active prefix; terminal destruction
does. Mouse and paste never count as the suffix and pass through normally.
Plain Escape is always terminal input.

## Audience workflows

`E` marks an essential workflow. Every E workflow must be keyboard-completable.
“State kept” includes buffer contents, undo, cursor, selections, native-surface
selection/scroll, terminal session, and pending non-destructive form input
unless the workflow explicitly changes it.

### IDE-oriented beginners

| ID | Value path and successful outcome | Visible/searchable entry | Final focus / state |
| --- | --- | --- | --- |
| B1 E | Open Explorer, choose a folder/file, edit, save | Explorer label; Open File; Save | editor / state kept |
| B2 E | Search files, open a result, edit, return to prior file | Search label; `search.files`; tabs | editor / both buffers kept |
| B3 E | Search project text, open result, inspect context, return | Search label; `search.text`; Back/previous buffer | editor / query and results kept |
| B4 E | See a diagnostic, open its details, jump to problem, fix it | Problems indicator; `problem.open`/`problem.next` | editor at repaired location |
| B5 E | Open terminal, run a command, return to editor, reopen terminal | Terminal label and visible return hint | editor / live terminal retained |
| B6 | Create, rename, then delete a file with confirmation | Explorer context actions; registry | explorer after mutation / expanded tree kept |
| B7 | Inspect changed files, stage one, commit with message | Source Control label; registry | Git surface / editor and selection kept |
| B8 | Change a preference, preview, save; cancel a later change | Settings label; `settings.open` | prior valid target / saved value only |
| B9 E | Enter Zen while editing, keep working, leave Zen | visible mode control; registry | prior valid target, normally editor / shell state restored |
| B10 E | Get lost, open Help/palette, identify current focus and return | persistent Help; `help.open`; `palette.open` | invoking target / query may be retained |

### Experienced Neovim users

| ID | Value path and successful outcome | Visible/searchable entry | Final focus / state |
| --- | --- | --- | --- |
| N1 E | Open a file and use Neovim Normal/Insert/Visual/command-line input unchanged | editor; `file.open` | editor / Neovim state authoritative |
| N2 E | Use Telescope/plugin floating UI, cancel or accept, continue editing | Neovim command/plugin mapping | editor / plugin outcome kept |
| N3 E | Split editor windows, move among them, close one | Neovim commands plus registered split commands | selected editor grid |
| N4 E | Open terminal, enter a terminal application, use Escape freely, invoke prefix, return | Terminal label; visible prefix/return hint | editor / terminal job retained |
| N5 | Browse Git status, open a changed file, stage it, return | Git label; registry | editor after open, Git after stage |
| N6 | Switch VideNormal to VideIDE and back without changing buffer/mode history unexpectedly | mode control; registry | same valid target / buffer, cursor, undo kept |
| N7 E | Enter/leave VideZen with editor grids, floats, and cursor preserved | mode control; registry | most recent valid target |
| N8 | Open Output/Debug, inspect and scroll, return to exact editor window | panel label; registry | invoking editor grid / panel scroll kept |
| N9 | Trigger an editor-owned unsaved-buffer close and answer its confirmation | tab close; `file.close` | Neovim-selected target / buffer follows answer |
| N10 E | Resize through every tier while editing and recover without lost keys or focus | terminal resize; Help remains reachable | nearest valid target / all hidden state kept |

### SSH and keyboard-only users

| ID | Value path and successful outcome | Visible/searchable entry | Final focus / state |
| --- | --- | --- | --- |
| S1 E | Launch, identify initial focus, open file, edit, save without mouse | initial focus marker; Help/palette | editor |
| S2 E | Traverse editor, Explorer, Git, and panel in documented order and reverse it | focus hints; next/previous-region commands | chosen region / selections kept |
| S3 E | Open terminal, run a command, use literal Escape, return with terminal prefix | terminal hint; `terminal.return` | editor / terminal retained |
| S4 E | Open/close a modal and a nested confirmation without focus leakage | visible dialog controls/hints | invoking valid target |
| S5 | Search files and project text; correct query errors; open result | Search label; palette | editor / query history retained per slice policy |
| S6 | Operate Explorer create/rename/delete and cancel destructive confirmation | Explorer hints; registry | explorer / no mutation on cancel |
| S7 | Stage and commit; recover from a failed Git effect | Git hints; retry command | Git / typed commit message retained on failure |
| S8 E | Work at 60x20 then 40x12; use Help and quit; regain surfaces after resize | recovery text; Help and quit shortcuts | editor or restored prior valid target |
| S9 | Toggle VideNormal, VideIDE, and VideZen solely through commands | palette/Help and current shortcuts | same/restored target / editor state kept |
| S10 E | Open a disabled command, read why, resolve prerequisite, retry | palette disabled reason | command-defined target / no state loss on refusal |

## Single focus-owner model

At every settled state, exactly one `FocusTarget` owns keyboard input. The
model is a tagged identity, never independent booleans:

- `editor(grid_id)` and `terminal(session_id, grid_id)`;
- `native(surface_id, control_id?)` for activity/navigation, Explorer,
  Search, Git, AI, Extensions, tabs, panels, Settings, Help, and other widgets;
- `overlay(overlay_id, control_id?)` for a dialog, menu, palette, context menu,
  or confirmation.

A target is valid only if enabled, visible, and reachable in the active layout.
Hidden surfaces may retain models and receive output, but cannot own keyboard
focus. Initial focus is the active editor grid. A click focuses the valid
target under the shared paint/hit-test layout; a click outside a modal is
handled by that modal's policy and never changes focus behind it.

The valid focus graph is generated from the current layout: modal parent to
its enabled controls and child modal; otherwise editor, visible primary
navigation, visible auxiliary, and visible drawer/panel form the region ring.
`focus.next_region` and `focus.previous_region` traverse that ring; Tab within
a native form traverses enabled controls. Editor and terminal Tab input is
passed through unless an explicit, displayed terminal prefix is active.
Direct commands may enter a region. Every native region exposes
`focus.editor`; terminal exposes `terminal.return` through its documented
prefix. Plain Escape is not the sole exit from any native region.

### Concrete surface and overlay policy

| FocusTarget/surface | Kind | Entry and explicit handling | Escape / outside click | Successful close or activation focus |
| --- | --- | --- | --- | --- |
| Activity/navigation | native region | F6 ring, mnemonic, click; arrows and activation | no action / click focuses valid hit target | activated sidebar, or editor for editor action |
| Explorer | native region | command, navigation activation/context commands | cancels inline rename/menu only / click valid hit target | opened file → editor; otherwise Explorer |
| Search | native region | command, query/list navigation | clears active query edit, then no action / valid hit target | result → editor |
| Git sidebar | native region | command, navigation and Git commands | cancels commit edit if clean; dirty edit opens confirmation / valid hit target | opened file → editor; otherwise Git |
| AI sidebar | native region | command, navigation/activation | cancels local menu only / valid hit target | command-defined AI terminal or editor |
| Extensions sidebar | native region | command, navigation/search | cancels search edit or closes child popup / valid hit target | sidebar unless edit-config returns editor |
| Editor tab/split chrome | native controls around editor | click or registered command | no action / clicked valid grid/control | selected editor/terminal grid |
| Drawer host (Terminal/Debug/Output) | native region | command, tab navigation, resize commands | no action / valid hit target | selected drawer target |
| Integrated terminal | terminal grid | command/click, prefix table; all else Neovim-owned | always forwarded / terminal mouse or chrome hit | terminal until prefix-return/chrome command |
| Debug and Output | native region | F6 ring, scroll/refresh, return command | no action / valid hit target | same surface or editor by explicit return |
| Settings | dismissible modal with dirty guard | focus-trapped form, save/cancel | clean closes; dirty opens confirmation / clean outside asks to close, dirty opens confirmation | recorded invoker or fallback |
| Help | dismissible non-modal overlay | navigation/search/close; background stays enabled but does not receive keys | closes / outside closes | recorded invoker or fallback |
| Command palette | dismissible modal | focus-trapped search/results | closes / outside closes | command result target or invoker |
| Context and split menus | dismissible modal menu | arrows, activation, close | closes one menu / outside closes one menu | recorded invoker or command result |
| Extension popup | dismissible modal; dirty guard where editing | focus-trapped controls and confirmations | safe close; dirty opens confirmation / same | Extensions or command result |
| Mason and Lazy | dismissible modal | focus-trapped tabs/search/actions | closes if no operation requires resolution / outside follows same rule | recorded invoker or fallback |
| Detailed Git | dismissible modal | focus-trapped tabs/list/actions | closes / outside closes | recorded invoker or fallback |
| Bug report | dismissible modal with dirty/submitting guard | focus-trapped form/consent/submit | clean closes; dirty confirms; submitting is non-dismissible / same | recorded invoker or fallback |
| Unsaved/destructive/reload confirmation | nested modal | explicit labeled confirm/cancel only | cancel when safe; mandatory resolution consumes Escape with `Action required` / outside never dismisses | parent control or command-defined target |
| Notice banner | non-modal, never focus owner | Help/notification history exposes message | not applicable | unchanged |
| Neovim/plugin/Telescope floats | editor-owned | all keyboard/mouse input passed to Neovim except fixed global keys | forwarded to Neovim / Neovim mouse | editor grid selected by Neovim |

Activity-side Help and Settings entry controls are included in their target
surface. A future slice adding a focusable surface must add a row before UX
approval; category-only routing is insufficient.

### Restoration and fallback

Opening an overlay pushes the current valid owner and overlay identity onto a
bounded restoration stack. Closing the top overlay restores its recorded
owner if valid, otherwise the newest valid visible owner in focus history,
otherwise the active editor grid. Closing a parent closes descendants first.
Duplicate close/repeated Escape at the settled base state is idempotent.

When resize, mode change, async completion, disablement, or destruction makes
the owner invalid, focus moves immediately by the same fallback rule. Entering
VideZen records the prior owner then focuses the active editor grid; leaving
restores it if valid. Resume validates the owner and layout, then applies the
same rule. Re-entering a live terminal requires `terminal.focus` or a click; it
never regains focus merely because output arrives. A failed effect keeps focus
at the initiating target unless that target disappeared, preserves editable
input, and exposes an actionable error.

## Ordered input-resolution contract

For each decoded input event, exactly the first matching stage handles it:

1. Terminal recovery/resume and session-critical signals are handled by the
   shell and cause focus validation plus a forced full redraw.
2. The top explicit modal handles only its declared editing, navigation,
   confirmation, dismissal, outside-click, and shadowed-global rules. `F1`
   shows inline contextual Help; region traversal and palette globals show the
   unavailable reason defined above. A non-dismissible modal rejects dismissal
   visibly; input never reaches anything behind it.
3. If the focused terminal has an active escape prefix, its next key is
   interpreted by the fixed shell input vocabulary above. Unknown suffixes
   cancel the prefix and send the prefix bytes plus suffix bytes to the
   terminal unchanged in one input operation; they never invoke a hidden target.
4. The focused target handles only commands explicitly assigned below.
5. Unhandled editor input is forwarded unchanged to the focused editor
   Neovim; unhandled terminal input is forwarded unchanged to the focused
   terminal Neovim. Unhandled native-surface input is ignored with an optional
   visible hint or terminal bell and is never forwarded.
6. If a target became invalid during dispatch, restoration/fallback runs
   before the next event.

| Focus target | Explicit shell handling | Escape | Unhandled input |
| --- | --- | --- | --- |
| Editor/Neovim grid | global commands only when their exact sequence is reserved and displayed; mouse chrome hits from shared layout | always passes to Neovim unless an explicit shell modal is above it | unchanged to editor Neovim |
| Terminal grid | `Ctrl-\` prefix table; chrome mouse; paste policy | literal Escape passes to terminal; `Ctrl-\`, then `e` invokes `terminal.return` | unchanged to terminal Neovim |
| Native navigation/list/tree | arrows, PageUp/Down, Home/End, activation, selection, context command, next/previous region, `focus.editor`, Help | concrete surface table governs; otherwise no action, never the sole return route | consume/ignore locally; optional visible hint |
| Native editable form | text editing, field traversal, activation, cancel/confirm, Help, explicit return where safe | concrete surface table governs; dirty state uses confirmation | consume/ignore locally |
| Non-modal overlay | concrete surface navigation/edit/activate/close; background is not disabled | concrete surface table governs and restores focus | consume/ignore locally |
| Dismissible modal | enabled controls, focus trap, confirm/cancel, declared outside click | dismisses only when safe; unsaved/destructive state opens confirmation | consume/ignore locally |
| Non-dismissible modal | enabled controls and required resolution only; focus trap | consumed with visible “action required” reason | consume/ignore locally |
| Nested confirmation | confirmation choices only; child owns focus before parent | cancel if allowed, restoring parent control; repeated Escape cannot cross two levels in one event | consume/ignore locally |

Shell-reserved global commands must use sequences that cannot be prefixes of
ordinary editor or terminal input, or must require the terminal escape prefix.
Their routing tests cover every focus target. Mouse-owning terminal programs
are the sole task-equivalence exception: their internal mouse outcome need not
have a Vide keyboard equivalent, but focusing/leaving the terminal does.

## Keyboard and pointer task equivalence

| Outcome class | Keyboard path | Pointer path | Required equivalence |
| --- | --- | --- | --- |
| Open/activate | region traversal, mnemonic, shortcut, or registry | labeled control, row, or tab | same command ID, successful effect, final focus, state |
| Context action | focused row plus context key/registry | right-click menu | same availability, menu commands, result |
| Destructive action | action then explicit confirm/cancel controls | action then identical confirm/cancel dialog | same warning, default, confirmation policy, mutation, focus |
| Close/cancel | visible shortcut/control; Escape only where authorized | visible close/cancel or allowed outside click | same preserved/discarded state and restoration target |
| Resize/reorder | registered commands where offered | drag handle | same bounds and retained content; nonessential free-form sizing may be pointer-enhanced |
| Disabled/error recovery | focus command, read reason, retry/cancel | click command, read reason, retry/cancel | same reason, retained input, retry effect and final focus |

No context-menu or clickable command may omit a keyboard or registry route.
Tests assert command ID rather than merely similar labels.

### Per-workflow equivalence record

`K` names the keyboard route; `P` names the pointer route. In every row,
cancel leaves the pre-command model unchanged and restores the initiating valid
target; an effect error retains editable input/selection, shows an actionable
retry/cancel message, and keeps the initiator unless it vanished. “Standard”
means those cancellation and error semantics; deviations are explicit.

| Workflow | K / P route | Completion and final focus | Cancel/error and preserved state |
| --- | --- | --- | --- |
| B1 | F6 Explorer or `file.open` / Explorer row | saved editor, editor focus | standard; buffers/tree retained |
| B2 | `search.files` / Search label+row | result editor | standard; query/results retained |
| B3 | `search.text` / Search label+row | result editor | standard; query/results retained |
| B4 | `problem.open` / problem indicator | diagnostic editor | standard; diagnostic list retained |
| B5 | `terminal.toggle`, prefix+e / Terminal label/return control | editor, live terminal | standard; session/output retained |
| B6 | Explorer context key / right-click | Explorer after confirmed mutation | identical confirmation; tree retained on cancel/error |
| B7 | Git commands / Git controls | Git | failed commit retains message and stage state |
| B8 | Settings command/form keys / Settings controls | invoker after save/cancel | dirty confirmation identical; unsaved edit retained on failed save |
| B9 | `mode.zen` / mode control | restored prior valid target | failed transition retains mode, focus, editor state |
| B10 | F1/palette / Help/palette controls | invoking target | query retained until explicit close; standard |
| N1 | Neovim/file commands / editor/file controls | editor | Neovim owns cancel/error and editor state |
| N2 | Neovim mapping documented in Help / plugin UI | Neovim-selected editor | Neovim owns cancel/error/state; shell does not intercept |
| N3 | Neovim split commands/registry / split controls | selected editor grid | Neovim confirmation/state; standard shell effect error |
| N4 | terminal command and prefix / Terminal controls | editor, live terminal | literal Escape passes through; session retained |
| N5 | Git commands / Git controls | editor on open, Git on stage | standard; Git selection retained |
| N6 | mode commands / mode controls | same valid target | failed switch keeps prior policy and editor state |
| N7 | `mode.zen` / mode control | restored valid target | as B9 |
| N8 | drawer commands / panel controls | exact invoking editor grid | panel scroll/output retained on close/error |
| N9 | `file.close` / tab close | Neovim-selected editor | identical Neovim-owned unsaved confirmation |
| N10 | terminal resize plus F1 / terminal resize plus controls | nearest valid target | all hidden surface/editor/terminal state retained |
| S1 | palette/file/save commands / same controls if available | editor | standard; buffers retained |
| S2 | F6/Shift-F6 / labeled region click | chosen region | no destructive cancel; selections retained |
| S3 | terminal command, literal Escape, prefix+e / terminal controls | editor | session/output retained |
| S4 | modal control traversal / modal controls | invoking target | one-level cancellation; parent form retained |
| S5 | search commands / Search controls | editor result | invalid query is editable; results/query retained |
| S6 | Explorer context key / right-click | Explorer | identical destructive confirmation; tree retained |
| S7 | Git commands / Git controls | Git | failed commit retains message/stage state for retry |
| S8 | F1 and quit command / visible controls when present | editor/restored target | resize never cancels data or commands |
| S9 | mode commands / mode controls | same/restored target | failed switch preserves prior mode and editor state |
| S10 | palette navigation/retry / disabled control/retry | command-defined target | refusal preserves state and exposes same reason |

## Semantic indicators independent of color

| State | Required non-color signal |
| --- | --- |
| Keyboard focus | border/leading marker plus region name; focused control has brackets or underline glyph treatment |
| Selection/current | selection marker and `selected`/`current` semantic state; current and selected use distinct markers if both exist |
| Error | `Error:` text or `!` plus readable message and recovery action |
| Unread count | textual integer beside region label; `99+` cap must retain exact accessible value |
| Loading | `Loading…` text or spinner plus label; control exposes busy state |
| Disabled | visibly unavailable control plus a reachable textual reason in focus, Help, or palette |

## Responsive invariants and boundaries

Width and height are evaluated independently from the minimum cells required
by visible regions. Base minima are: editor content 40 columns by 10 rows;
compact navigation 3 columns; labeled navigation 18 columns; usable auxiliary
19 columns by 8 rows; comfortable auxiliary 28 columns; one-cell separators;
three rows for top/bottom chrome; and two rows for emergency guidance. A slice
must declare a larger minimum when its content requires it; layout recomputes
from that value instead of clipping.

| Axis tier | Below boundary | At boundary | Above boundary |
| --- | --- | --- | --- |
| Width comfortable, 112 | compact presentation; `64 editor + 28 auxiliary + 18 labels + 2 separators` does not fit | all three fit exactly | distribute surplus to editor first, then auxiliary |
| Width compact, 79 | constrained presentation; `50 editor + 24 auxiliary + 3 rail + 2 separators` does not fit | all three fit exactly | retain compact until comfortable boundary |
| Width constrained, 60 | emergency; `40 editor + 19 auxiliary + 1 separator` does not fit | editor and one auxiliary fit exactly | give surplus to editor until compact boundary |
| Width emergency, 40 | resize guidance may replace editor because readable editor minimum does not fit | editor-only plus recovery guidance fits | editor remains primary; suspended state retained |
| Height comfortable, 27 | compact height; `24 content + 3 chrome` does not fit | fits exactly | surplus to editor |
| Height compact, 20 | constrained height; `17 content + 3 chrome` does not fit | fits exactly | retain until comfortable boundary |
| Height constrained, 15 | emergency; `12 active content + 3 chrome` does not fit | fits exactly | retain until compact boundary |
| Height emergency, 12 | resize guidance replaces normal composition because `10 editor + 2 guidance` does not fit | editor-only/recovery fits | retain until constrained boundary |

The effective named tier is the more restrictive axis result, but layout uses
both axis results (for example, wide/short may retain labels while stacking or
suspending a drawer). Comfortable shows full labels and simultaneous regions.
Compact may abbreviate chrome but retains text alternatives. Constrained keeps
the editor and one active auxiliary simultaneously when their declared minima
fit; otherwise it presents the auxiliary as a full-content swap with a visible
editor-return command, preserving both states. Emergency deterministically
shows the editor when at least 40x12, or non-overlapping resize guidance below
that. Help and quit remain keyboard-accessible in emergency.

Transitions occur only on a resize/layout transaction and are computed from
integer minima, so there is no hysteresis feedback or oscillation. A tier may
change geometry or presentation, never commands, focus semantics, or stored
state. Hidden/suspended targets become invalid and follow focus fallback.
Tests cover one column/row below, at, and above every listed or slice-declared
boundary, repeated alternating resize, active modal/terminal/auxiliary cases,
clipped guidance, state preservation, hit-test equality, and forced redraw.

## State across modes and resize

Resize preserves editor and terminal sessions/grids, buffer/cursor/undo,
active tabs, native selections and scroll, expanded trees, panel sizes within
new bounds, overlay form input, restoration history, and active commands.
Mode transitions preserve the same state. VideZen hides native regions, keeps
their state, focuses editor, and restores the newest valid target on exit.
Only an explicit command may discard user input or destroy a surface.

## Acceptance traceability

- All essential workflows have visible and searchable commands and a keyboard
  path; pointer paths invoke the same command IDs.
- Neovim and terminal Escape pass through unless the top modal explicitly
  owns dismissal; every consumed Escape is a table entry and requires a test.
- Native input never leaks to a hidden editor or terminal.
- Focus entry, traversal, restoration, invalidation, resume, terminal
  re-entry, failed effects, nested overlays, and repeated Escape are defined.
- Breakpoint and equivalence assertions are specified independently of color,
  glyph choice, and prototype layout.
