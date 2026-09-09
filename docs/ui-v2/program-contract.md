# UI v2 program contract

Status: draft for architecture/RPC, UX, settings/migration, renderer/performance,
and release review. This document describes commit
`226a8420b203f9acc70c638f424f3b8543356fd7`; it does not authorize a runtime
change.

## Purpose and governing rule

UI v2 is a replacement composition shell, not a second application. There is
one Vide session and one behavioral implementation. Both shells must use the
same editor and terminal `UiState` values, the same two `RpcClient` instances,
the same settings object and persistence format, the same command identifiers
and effects, the same focus-transition semantics, and the same persisted
state. A shell may own only layout, geometry, native view composition, and
shell-private render resources.

Neovim remains authoritative for buffers, windows, cursor, editing, undo,
diagnostics, and plugins. Zig remains authoritative for shell layout, native
surface visibility, focus, overlays, drawer state, widget state, hit testing,
notifications, and rendering. The UI/RPC execution context exclusively owns
`App`, both RPC clients, both `UiState` values, the renderer, and live widget
arenas.

## Ownership and change routing

| Concern | Durable owner | v1 composition | v2 composition |
| --- | --- | --- | --- |
| Editor/terminal grids and editor truth | the existing two `UiState` values and Neovim sessions | consume | consume |
| Commands, availability, confirmation, and effects | shared controller/command/effect path introduced by Prompts 08-09 | invoke | invoke |
| Settings and persisted state | one versioned settings model (Prompt 02) | read/write through shared owner | read/write through shared owner |
| Focus and overlay transitions | one `FocusTarget` state machine (Prompt 08E) | project and render | project and render |
| Native widget behavior and data | shared slice model/controller | legacy adapter until slice migration | unavailable until slice migration, then shared |
| Geometry and hit testing | each shell's single layout result | v1 layout | v2 layout |
| Cell composition and shell styling | shell-local view code | v1 renderer consumer | v2 renderer consumer |
| RPC/process/filesystem/network execution | shared effect executor after Prompt 08C; approved legacy adapters before then | execute through shared boundary | execute through shared boundary |

A future change belongs to shared behavior if it changes a successful outcome,
confirmation policy, focus result, notification, command availability, external
effect, or persisted state. It belongs to one composition if it changes only
rectangles, responsive presentation, cell painting, or shell-local render
resources without changing those semantics.

## Shared state invariants

- A shell switch must not spawn another Neovim process, attach another UI,
  clone a grid, reload settings, repeat an effect, or reset editor state.
- Normal and IDE are editor-input policies over the same shell. Zen is a
  reversible presentation state. Use `VideNormal`, `VideIDE`, and `VideZen` in
  new policy names; Neovim Normal/Insert/Visual/Terminal remain separate modes.
- Exactly one visible, enabled, reachable target ultimately owns keyboard
  focus. Until Prompt 08E replaces the current booleans, `terminal_focus` and
  `sidebar_focus` are legacy projections, not a v2 state model.
- Painting and pointer hit testing must consume the same layout result. Every
  essential pointer outcome must have a keyboard route.
- Notices, loading, error, selected/current, focusable, and disabled-reason
  semantics are shared behavior even when rendered differently.
- Forced full redraw remains available for resize, resume, theme change, and
  terminal recovery.

## User-visible surface and action parity inventory

`Unknown` means the current code or reviewed product documents do not define a
stable contract. Prompt 01 must resolve input and focus unknowns; later slice
prompts must not silently choose them.

| Surface (source) | Supported actions/outcomes | Keyboard input | Mouse input | RPC or external effect | Focus result | Notice/persistence |
| --- | --- | --- | --- | --- | --- | --- |
| Activity bar (`activity_bar.zig`) | select/toggle Explorer, Search, Git, AI, Extensions; open Settings | `Tab`/`S-Tab` cycle while sidebar focused; `Ctrl-E` toggles sidebar; Settings via `Ctrl-S` while sidebar focused | click five activities; click Settings | Extensions may run helper search; Settings reloads files and queries RPC | activity selection sets sidebar focus; Settings opens modal-like widget | errors use global notice; active item and sidebar visibility are session-only |
| Explorer (`explorer.zig`) | navigate, select, expand/collapse, open, create file/dir, rename, delete, refresh/status, context menu, scroll | arrows/`j`/`k`, Enter/`o`, and action keys defined in widget; exact discoverable key contract is **Unknown** | row select/open/expand, wheel, right-click menu and menu actions | synchronous traversal and mutations; editor RPC status/open operations | file open returns to editor; directory/action editing retains sidebar; failure focus **Unknown** | failures become global notices; expansion/selection/scroll are session-only |
| Search (`search_panel.zig`, `list_panel.zig`) | Find Files, Live Grep, Buffers, Help Tags, Git Commits, Git Status | arrows/`j`/`k`, Enter; exact labels are visible | click row | `nvim_command` launches Telescope | command returns focus to editor | no persistence; RPC failure notice is **Unknown** |
| Git sidebar (`git_panel.zig`, `git_utils.zig`) | refresh status/branch/commits, expand groups, select/open file, stage/unstage, commit, open detailed Git view, scroll | navigation/action keys in widget; exact discoverable contract **Unknown** | group toggles, file/action rows, wheel | synchronous `git` child spawn/wait; editor open RPC | file open returns editor; mutation/commit generally retains sidebar | failures use global notice/log; state is session-only |
| AI sidebar (`ai_panel.zig`) | choose available agent, open/focus/restart AI terminal, send actions/context/diagnostics, change view, navigate | arrows/`j`/`k`, Enter/action keys; exact return route **Unknown** | click action/agent rows | startup executable probes; editor Lua notifications launch/focus AI tools | launch/focus/restart/run action returns editor/AI; context-only commands retain sidebar | availability/session selection not persisted; failures mostly delegated to Neovim notices |
| Extensions sidebar and popup (`extension_shop.zig`) | catalog/category search, navigate, details, install/remove, reload confirmation, edit config | navigation, search editing, Enter/Escape and confirmation keys in widget; exact contract **Unknown** | rows, categories, popup controls, wheel | Python helper spawn/wait; config filesystem work; network occurs in helper | popup is modal-like; edit config returns editor; close restoration **Unknown** | messages are widget-local; installed state is external plugin/config state |
| Editor viewport / Neovim grids (`UiState`, `views.zig`) | unrestricted Neovim editing and plugin UI; mouse; Telescope/floats | unhandled input forwarded as `nvim_input`; IDE action policy may intercept registered shell commands | Neovim mouse, right-click context menu, Telescope close affordance | editor RPC input/mouse/commands | editor unless an explicit shell surface takes focus | editor persistence, undo, buffers, plugins remain Neovim-owned |
| Tab strip and split chrome (`views.zig`, `events.zig`) | focus/select/close buffer or split, create buffer, open vertical/horizontal split menu | new buffer via configured `Ctrl-N`; keyboard equivalents for every split-menu action are **Unknown** | tab select/close/new; split buttons/menu; terminal split close | editor or terminal RPC calls/notifications | selected editor tab/split goes editor; terminal split stays terminal | unsaved confirmation is Neovim-owned; no shell persistence |
| Editor context menu (`editor_context_menu.zig`) | undo, redo, cut, copy, paste, select all, AI explain/fix/add context (as defined by item table) | Up/Down, Enter, Escape | right-click open; hover/select/click | Lua editor action notification | closes to editor; AI command may move to AI terminal according to action | errors use global notice; no persistence |
| IDE status menus (`events.zig`, `views.zig`) | File: new/save/close; Edit: undo/redo/cut/copy/paste/find/replace; Selection: all/line; Buffer: previous/next/close | equivalent actions exist through editor commands/current shortcuts, but menu traversal itself is **Unknown** | click menu and item | Lua editor action notification | editor | errors use global notice; no persistence |
| Status/mode/help/report chrome (`views.zig`) | inspect/change mode via Settings, open Help, open bug report, view branch/file/focus/notice | F12 opens report; configured F11 changes Zen; Help keyboard route **Unknown** | click mode, Help, Report bug | settings file/RPC refresh; Help RPC; bug-report external work | overlays take focus in legacy manner; exact restoration **Unknown** | mode is persisted through settings save paths; notices expire after five seconds |
| Unified legacy panel host (`views.zig`) | show/hide, select Terminal/Debug/Output, resize, switch bottom/right | configured `Ctrl-T`; `Alt-P`; `Alt`+arrows resize; terminal-specific focus/split keys | click tabs, drag resize | terminal RPC; Debug/Output RPC refresh | Terminal tab owns terminal focus; Debug/Output do not | size/orientation/tab are session-only |
| Integrated terminal (`terminal.zig`, terminal `UiState`) | lazy start shell, type/paste/mouse, vertical/horizontal splits, close/cycle/focus split, hide/show | `Alt-V/S/C/O/H/J/K/L`; configured toggle; remaining keys forwarded | click/focus, wheel/mouse forwarded, split-close | second RPC client and Neovim terminal session | explicit terminal/editor transitions; hide returns editor | session survives hide; no persisted layout; errors use notice |
| Debug console (`debug_console.zig`, `log_console.zig`) | refresh DAP REPL/terminal output, scroll | keyboard navigation/refresh is **Unknown** | panel tab, wheel | synchronous editor `nvim_exec_lua` call | does not take terminal focus | no persistence; empty message inline |
| Output (`output_panel.zig`, `log_console.zig`) | refresh `:messages`, scroll | keyboard navigation/refresh is **Unknown** | panel tab, wheel | synchronous editor `nvim_exec_lua` call | does not take terminal focus | no persistence; errors/empty state inline |
| Settings (`settings.zig`) | load/edit/preview/save/cancel tabs and controls, mode/theme/keybindings/fonts/editor prefs, plugin list/config, open Mason/Lazy, update Vide | internal tabs/control/dropdown/key capture navigation; Escape behavior and unsaved confirmation are incomplete/ **Unknown** | tabs, controls, dropdowns, buttons, outside close | settings filesystem I/O, RPC theme query, plugin file reads/config writes, update shell process/network | overlay-like focus; open file returns editor; close restoration **Unknown** | `settings.json` durable; preview file disposable; save/load errors surfaced by notice/log |
| Mason (`mason.zig`) | browse/search/filter packages, select/install/uninstall/update/check health | arrows/tabs/search/action keys in widget | tabs, rows, buttons, close | synchronous editor Lua RPC calls | modal-like; restoration **Unknown** | Neovim plugin state external; status inline; no shell persistence |
| Lazy (`lazy.zig`) | browse/filter/search plugins, update/sync/clean | arrows/tabs/search/action keys in widget | tabs, rows, buttons, close | synchronous call for update/clean, notification for sync, refresh RPC | modal-like; restoration **Unknown** | Neovim plugin state external; no shell persistence |
| Detailed Git (`git_detailed.zig`) | refresh history/branches, select tab/row, scroll, close | arrows/tab/Escape/action keys in widget | tabs, rows, wheel, close/outside | synchronous `git` commands | modal-like; restoration **Unknown** | session-only; errors are currently weak/ **Unknown** |
| Bug report (`bug_report.zig`) | category, summary/description entry/paste, consent, submit, success/failure, open returned URL, retry/close | F12 entry; form traversal/edit/confirm/Escape in widget | fields, category menu, consent/actions, scrolling | writes payload/status files; spawns shell/curl and waits for launcher; network submission | modal; post-close restoration **Unknown** | consent is per submission; status/error inline; diagnostics are filtered before attachment |
| Notice banner (`App.notify`, `views.zig`) | inspect transient info/warning/failure | no explicit history or focus route | none | none | never intentionally takes focus | in-memory, five-second expiry; replacement priority/history **Unknown** |
| Neovim/Telescope/plugin floating grids (`views.zig`) | native plugin interaction and close | Neovim-owned | Neovim mouse plus shell-drawn close hit target | editor RPC notification | Neovim/editor | Neovim-owned |
| Split menu (`views.zig`) | create terminal/editor split on either side | direct keyboard menu operation **Unknown** | click four choices | synchronous RPC calls | source RPC surface retains focus | no persistence |

### Widget-file coverage

Every file under `src/tui/widgets/` is accounted for above. Infrastructure
files do not create independent product behavior: `primitives.zig` owns shared
modal/button/list geometry; `list_panel.zig` implements Search's list;
`log_console.zig` implements Output and Debug; and `git_utils.zig` is the
blocking Git process helper. `output_panel.zig`, `debug_console.zig`, and
`search_panel.zig` are concrete specializations. No v2-specific copy of any of
these helpers may be created.

## Mode transition parity

| Transition | Shared outcome | RPC/external effect | Focus and state |
| --- | --- | --- | --- |
| VideNormal -> VideIDE | same shell, enable modeless editor policy, hide Neovim statusline | editor command/notification enabling IDE globals/maps | active buffer/cursor and valid focus preserved; settings mode becomes `ide` when saved |
| VideIDE -> VideNormal | same shell, remove IDE policy, show normal statusline | editor command disabling IDE globals/maps | active buffer/cursor and valid focus preserved; mode becomes `normal` |
| VideNormal or VideIDE -> VideZen | remember prior non-Zen mode; suppress activity/sidebar/tab/panel; keep mode row | embedded path changes Neovim globals/statusline; optional legacy handoff saves session, writes init, spawns/waits for native Neovim | editor state must be preserved; native surfaces hidden and cannot retain focus; exact fallback currently **Unknown** |
| VideZen -> previous mode | restore remembered VideNormal or VideIDE and shell surfaces/state | reverse editor mode command; optional handoff resumes session | buffer/cursor and applicable sidebar/drawer state preserved; restore most recent valid visible focus (legacy behavior incomplete) |
| any mode -> same mode via Settings | apply editor preferences without duplicating session/effects | settings preview/save plus editor notifications | no unrelated focus or state reset |

The optional native Zen handoff is a current compatibility path, not a UI v2
composition. Its removal/product decision belongs before UI v2 default-on.

## Effect classification policy

| Class | Definition | Allowed examples |
| --- | --- | --- |
| UI-safe | bounded in-memory state/layout/composition, nonblocking poll/read/write already ready, or queued notification with bounded transport | selection, focus transition, hit test, reducer update, damage calculation |
| bounded synchronous startup | runs before interactive input is admitted, has explicit size/time bounds, and is in the allowlist below | capability detection, creating app-data directory, extracting fixed embedded helper, spawning/attaching the two required Neovim children, setup-only RPC configuration |
| worker-only interactive | can block on RPC response, process completion, filesystem iteration/file I/O, network, or unbounded external data | all interactive `rpc.call`, Git/helper commands, Explorer scans/mutations, extension and report submission, settings/plugin scans/save/update |

The initial startup allowlist is deliberately narrow: fixed environment/path
construction; terminal/renderer/self-pipe initialization; fixed embedded
helper extraction; two Neovim spawns; widget allocation; initial settings load
(temporarily, until Prompt 02); initial Explorer/Git refresh (known debt, to be
moved); UI attach and setup-only Neovim calls at `src/main.zig:472-551`; and
opening the initial file before the event loop. Any addition requires an
architecture/RPC review and a recorded bound. Initial Explorer/Git refresh is
allowed only because input has not begun; its unbounded duration remains a
startup defect, not evidence that it is UI-safe.

## Known synchronous and external-effect audit

Line numbers refer to the audited commit and must be refreshed when the status
row returns to review.

### Direct blocking RPC calls

| Source | Direct `rpc.call` / `rpc_term.call` locations | Classification and removal owner |
| --- | --- | --- |
| `src/main.zig` | 261, 266 (reload save/session); 472, 488, 498, 503, 507, 511, 522, 540, 551 (startup); 697, 702, 739, 741 (interactive Zen); 877 (interactive paste) | startup group is bounded-startup pending Prompt 05C review; every other site is worker-ineligible RPC-context async work owned by 05C/05D |
| `src/tui/events.zig` | 142, 145, 155, 158, 165, 171, 187, 190, 210, 213, 223, 226, 236, 239 (terminal splits/focus); 475, 480, 505, 507, 517, 522 (Zen); 558, 565 (new/find); 822, 826, 831, 835 (split menu); 880 (terminal split close) | prohibited synchronous interactive RPC; Prompt 05C owns conversion |
| `src/tui/widgets/explorer.zig` | 125 (status query), 471 (editor command) | prohibited interactive RPC; Explorer slice/05C owns conversion |
| `src/tui/widgets/lazy.zig` | 84 (refresh), 433 (update), 439 (clean) | prohibited interactive RPC; Prompt 17C/05C |
| `src/tui/widgets/log_console.zig` | 36 (Debug/Output refresh) | prohibited interactive RPC; Prompt 15/05C |
| `src/tui/widgets/mason.zig` | 109, 168, 701 | prohibited interactive RPC; Prompt 17B/05C |
| `src/tui/widgets/settings.zig` | 518 (theme query) | startup use may be allowlisted; reopening Settings interactively is prohibited; Prompt 16/05C |

RPC notifications are non-waiting today but are not yet bounded by an outbound
queue. They occur at `src/main.zig:250,601,607,757,796,801,806,810,820,829,837,841,846,854`;
`src/nvim/helpers.zig:40,276`; `src/tui/events.zig:68,119,573,574,632,657,696,857,1112,1143,1236,1262,1265,1291,1298,1307`;
and `src/tui/widgets/lazy.zig:436`. Prompt 05B owns transport bounding and
Prompt 05C owns call-site classification. `App.notify` calls are in-memory
notices and are not RPC.

### Process spawn/wait and network

| Source location | Effect | Classification / owner |
| --- | --- | --- |
| `src/main.zig:228,235` | spawn the two embedded Neovim processes | bounded synchronous startup; lifecycle owner remains main/reactor |
| `src/main.zig:291-293` | optional native Zen Neovim spawn and wait | blocking interactive/session transition; compatibility owner, product decision required before v2 default |
| `src/tui/widgets/git_utils.zig:4-27` | spawn any Git command, collect output, wait | worker-only interactive; Prompt 04C/13 |
| `src/tui/widgets/extension_shop.zig:138-162,749-754` | spawn Python store helper and wait for search/install/remove | worker-only interactive; helper performs catalog/download network work; Prompt 17A |
| `src/tui/widgets/settings.zig:330-383` | write updater script, spawn background shell; later poll files | worker-only interactive; network URL is the repository setup script; Prompt 16/20 |
| `src/tui/widgets/bug_report.zig:650-729` | write request files, spawn shell/curl submission and URL launcher; launcher wait | worker-only interactive; explicit network/consent boundary; Prompt 18 |

There is no native Zig socket/HTTP client in the audited paths. Known network
work is delegated to the extension Python helper, the settings update shell
script, and bug-report `curl`. The extension helper fetches its catalog from
`https://github.com/alex-popov-tech/store.nvim.crawler/releases/latest/download/db_minified.json`
at `src/nvim/store_search.py:15`. The settings updater starts from
`https://raw.githubusercontent.com/Rouboufy/vide/main/setup.sh`; its redirect
chain and the deployment-provided bug-report endpoint remain **Unknown** and
must be inventoried by their slice owners before migration.

### Filesystem traversal and file effects reachable from native UI

| Source location | Effect | Classification / owner |
| --- | --- | --- |
| `src/main.zig:69-103` | append formatted diagnostics to `vide.log` | synchronous filesystem work reachable during interaction; Prompt 03 must instrument it and the shared effect/diagnostics design must bound or move it before UI v2 release |
| `src/main.zig:167-204,624` | create data directory, write fixed helper, delete preview | creation/extraction are bounded startup; preview deletion is interactive filesystem work to move behind settings effect |
| `src/main.zig:704-725` | write the native-Zen handoff init script | interactive filesystem compatibility effect; Prompt 05C/10 decision, removed with or before native handoff removal |
| `src/tui/events.zig:97-112,450-500` | write Zen handoff init/session paths | interactive filesystem/RPC compatibility effect; Prompt 05C/10 decision |
| `src/tui/widgets/explorer.zig:89-211` | recursive visible-tree directory opens/iteration and status rebuilding | worker-only interactive; Prompt 11B |
| `src/tui/widgets/explorer.zig:222-277` | delete file/tree, create file/dir, rename | ordered worker-only mutation; Prompt 11C |
| `src/tui/widgets/ai_panel.zig:64-109` | executable availability probes via PATH access | startup-only today; any refresh is worker-only; Prompt 18 |
| `src/tui/widgets/settings.zig:107-209` | fixed-buffer settings load and direct save | startup load temporarily allowlisted; interactive load/save worker/effect boundary; Prompt 02/16 |
| `src/tui/widgets/settings.zig:327-407` | create updater script and synchronously poll status/progress files | worker-only/polled interactive; Prompt 16/20 |
| `src/tui/widgets/settings.zig:533-672` | read plugin metadata, create config directory/file/template | worker-only interactive; Prompt 16/17 |
| `src/tui/widgets/extension_shop.zig:788-805` | create/read/write plugin config | worker-only interactive; Prompt 17A |
| `src/tui/widgets/bug_report.zig:142-177` | read `/etc/os-release` while constructing the eagerly initialized report widget | bounded synchronous startup today; move to lazy/worker-owned diagnostics collection if report initialization becomes interactive; Prompt 18 |
| `src/tui/widgets/bug_report.zig:509-768` | read/redact diagnostic files; write/delete request/status/response files | worker-only interactive and consent-sensitive; Prompt 18 |

All directory traversal found in native UI code is the Explorer iteration at
`explorer.zig:167-210`. Git subprocesses and helper scripts may traverse
internally; they are treated as worker-only external operations regardless of
their implementation.

## Compatibility adapters

Until a slice is accepted, v1 legacy widget state remains authoritative and
may use only the direct-effect paths listed above. UI v2 must not reach that
widget or effect. Prompt 08F owns narrow projection adapters; the shared
controller owns action translation; Prompt 08C owns effect execution; the
individual slice owner owns model/view projection and deletion.

An adapter must name its source surface, shared command/action mapping, state
projection, direct-effect exceptions, feature flag, and removal prompt. It may
not own settings, an RPC client, a command vocabulary, a second controller, or
editor state. It is removed when the slice's semantic, keyboard/pointer,
focus, error, persistence, lifecycle, and PTY evidence is accepted, v1 consumes
the shared behavior where required, and rollback selects composition rather
than duplicate behavior.

## Scope control

Once a surface enters migration, both implementations are frozen to parity
fixes. A bug fix affecting outcomes goes into shared behavior and both shells.
Shell-specific geometry/render bugs go only to the affected composition. New
unrelated features wait until the slice is accepted; they are never built
twice. An emergency compatibility fix must be recorded in the status row with
owner, expiry, and adapter-removal follow-up.

## Feature-flag lifecycle and recovery

No runtime flag is introduced by Prompt 00. Prompt 10 must use the approved
precedence `emergency override > explicit CLI > environment > persisted
preference > release default`, with exact names still **Unknown** pending
architecture/release approval. Proposed spellings such as `--ui=v1` and
`--ui=v2` in later prompts are not active contracts until that decision is
recorded.

Lifecycle: compile-time developer availability; explicit non-persisted launch
selection; opt-in beta backed by versioned settings; default-on with retained
v1 recovery; then v1/adapter removal only after Prompt 22's evidence gate.
Selection occurs before interactive work and changes composition only. A v2
initialization failure may fall back transactionally before user work; a
runtime failure must restore the terminal and report diagnostics, never
silently switch shells.

The emergency launch override must ignore a persisted v2 selection without
rewriting it, work without initializing v2 resources, and remain documented
and tested until v1 removal. Its exact CLI/environment spelling, collision
behavior, and post-v1 meaning are **Unknown** and owned by release plus
architecture review in Prompt 10/20A.

## Review checklist for future slices

- Identify shared outcomes, command IDs, effects, focus result, notice, and
  persistence before editing either composition.
- Declare expected and out-of-scope modules, feature flag/adapter, partial
  rollout, and disable path in `docs/ui-v2/status.md`.
- Prove keyboard reachability and pointer equivalence from one geometry result.
- Move every listed direct effect for the slice to the approved async boundary;
  do not add a new exception.
- Test cancellation, stale completion, shutdown, allocation failure, and
  partial initialization where ownership crosses a boundary.
- Preserve forced redraw and record exact verification commands/evidence.

## Prompt 00 verification record

- All 18 files under `src/tui/widgets/` are explicitly mapped above, including
  the four infrastructure/specialization helpers.
- All direct native-UI `rpc.call` sites, all discovered native process
  spawn/wait sites, all native directory traversal, and known network helper
  boundaries are listed with source locations.
- VideNormal, VideIDE, and VideZen transitions are listed explicitly.
- Ownership routing distinguishes shared behavior, v1 composition, and v2
  composition without requiring the event router.
