# Vide UI v2 implementation playbook

## Purpose

This playbook converts the UI v2 roadmap into a sequence of implementation
prompts. Each prompt is intended to be handed to a coding agent or engineer as
one bounded assignment. The prompts deliberately separate discovery, design,
infrastructure, migration, and release work so that UI v2 remains an
incremental replacement of Vide's native shell rather than a second
application.

UI v2 keeps the existing Zig executable, embedded Neovim processes,
MessagePack-RPC protocol, editor state, and isolated runtime. It changes the
frontend scheduling, state boundaries, layout, interaction model, native
widgets, and visual system.

## Rules that apply to every prompt

Include these rules whenever a prompt is executed:

1. Read `PROJECT.md`, `vide_architecture.md`, `docs/performance.md`, and the
   files named in the prompt before changing code.
2. Inspect the worktree first. Preserve unrelated user changes and do not
   perform destructive Git operations.
3. Treat Neovim as authoritative for buffers, windows, cursor, editing,
   diagnostics, plugins, and undo. Treat Zig as authoritative for shell
   layout, focus, overlays, drawers, native widgets, and rendering.
4. Do not create a second controller, settings model, command vocabulary, or
   editor state for UI v2. UI v1 and v2 may temporarily have different
   composition/layout shells, but must share behavior and effects.
5. Do not add synchronous process waits, filesystem traversal, network work,
   or blocking RPC calls to an interactive path.
6. Only the UI/RPC execution context may access either `RpcClient`, `App`, the
   renderer, or live widget arenas. Worker tasks return independently owned
   results through bounded queues.
7. Make ownership and cleanup explicit. Stale completions, cancellation,
   shutdown, allocation failure, and partial initialization must be tested.
8. Painting geometry and mouse hit-testing must derive from the same layout
   result. Essential tasks must be keyboard-accessible.
   Task equivalence means equivalent successful outcomes, confirmation policy,
   focus result, and preserved state; it does not require identical keyboard
   and pointer interaction sequences. No action may be pointer-only.
9. Preserve a forced full-redraw path for resize, resume, theme changes, and
   terminal recovery.
10. Add or update tests in the same change. Run focused tests first, then the
    broadest relevant repository suite.
11. Measure before claiming a performance improvement. Record the build mode,
    terminal dimensions, environment, and comparison baseline.
12. If a prerequisite or acceptance gate is not satisfied, stop and report the
    blocker instead of weakening the gate or expanding scope.
13. Test semantics before styling. Assert roles, labels, command IDs,
    focusability, navigation order, selected/current state, disabled reasons,
    and loading/error state independently of terminal colors and glyphs.
14. Use unambiguous names such as `VideNormal`, `VideIDE`, and `VideZen` for
    Vide policies. Refer separately to Neovim Normal, Insert, Visual, and
    Terminal modes.

## Program execution record and approval

Create and maintain `docs/ui-v2/status.md` when implementation begins. It must
contain one row per prompt or lettered sub-prompt with:

- status and named approval role;
- prerequisite commit IDs;
- implementation commit or pull request;
- test, benchmark, design, and validation evidence paths;
- decision date, approved exceptions, and expiry/follow-up issue;
- persisted-state impact and rollback/disable instructions.

“Accepted” means the change is integrated into the designated UI v2
integration branch, all required evidence is recorded, and the relevant owner
has approved it. Approval roles are architecture/RPC, UX, settings/migration,
renderer/performance, and release. A prerequisite change that invalidates
evidence returns affected dependent prompts to review.

Each runtime prompt must record expected modules, out-of-scope modules, its
feature flag or compatibility seam, partial-rollout policy, and how to disable
the path without reverting unrelated later work.

## Dependency and workstream map

```text
00 Program contract
├── 01A UX contract → 01B prototypes → 01C product decision
├── 02 Settings durability
└── 03 Observability → 03B reactor seam
                     ├── 04A task design → 04B runner → 04C Git refresh
                     └── 05A RPC framing → 05B async transport → 05C call sites

05A → 05B → 05C → 05D
04B + 05B + 03 → 06 invalidation
06 → 07A ANSI encoder → 07B retained composition → 07C optional optimization
01C + 04B + 05D + 06 + 07B → 08A–08F shared model → 09A–09C
02 + 09 → 10 editor-only v2 shell
10 → sidebar, drawer, and overlay vertical-slice workstreams
all slices → 19 visual system → 20A–20E beta → 21 default → 22 removal
```

Lettered sub-prompts are separate assignments with separate status rows,
reviews, rollback boundaries, and evidence. Do not hand an entire multi-part
prompt to one implementation agent.

## Repository verification catalog

Every status row must list exact commands. Select the applicable commands from
this catalog and add focused tests for the touched module:

- `zig build test` for the Zig unit suite;
- `python3 tests/pty_integration.py` for interactive PTY behavior;
- `python3 tests/performance_profile.py` to validate a performance record;
- `python3 scripts/profile_vide.py` for controlled profiling;
- `tests/terminal_compat.sh` for supported terminal transports;
- the relevant scripts under `tests/` for IDE mode, onboarding, launcher,
  packaging, and AppImage behavior.

Prompt 03 must add a documented test-resource policy: PR, nightly, soak, and
release time budgets; deterministic seeds and fixture sizes; retry rules;
quarantine owner and expiry; required runner characteristics; and permitted
skip conditions. Missing required hardware blocks release promotion, not the
individual code change, and must never be reported as a fabricated pass.

## Delivery format for every implementation assignment

The implementer should finish each prompt with:

- a concise outcome summary;
- files changed and important design decisions;
- tests and measurements run, including failures;
- acceptance criteria satisfied or still open;
- ownership, compatibility, or follow-up risks;
- confirmation that no unrelated changes were overwritten.

Do not begin the next prompt merely because code compiles. Its entry gate must
also be satisfied.

---

## Prompt 00 — Establish the UI v2 program contract

**Entry gate:** None.

**Objective:** Create the durable specification that prevents UI v1 and UI v2
from becoming separate applications.

**Implementation prompt:**

> Prepare the UI v2 program contract without changing runtime behavior. Audit
> `PROJECT.md`, `vide_architecture.md`, `src/main.zig`, `src/tui/app.zig`,
> `src/tui/events.zig`, `src/tui/views.zig`, and all native widget entry
> points. Add a version-controlled UI v2 specification under `docs/` that:
>
> - defines what remains shared between shells: editor `UiState`, both RPC
>   clients, settings, commands, effects, focus semantics, and persisted state;
> - inventories every user-visible surface and every action it supports;
> - records each action's keyboard input, mouse input, RPC or external effect,
>   focus result, notification behavior, and persistence behavior;
> - classifies each existing operation as UI-safe, bounded synchronous startup
>   work, or worker-only interactive work;
> - defines compatibility-adapter ownership and explicit removal criteria;
> - defines scope control: a migrating slice receives fixes but no unrelated
>   feature expansion in both implementations;
> - defines the UI v2 feature-flag lifecycle and emergency launch override;
> - lists all currently known synchronous effects and blocking RPC calls with
>   source locations.
>
> Use tables where they make parity and ownership auditable. Mark unknowns
> explicitly rather than guessing. Do not implement the new architecture in
> this assignment.

**Required verification:**

- Every widget under `src/tui/widgets/` appears in the surface inventory.
- Every direct `rpc.call`, process spawn/wait, directory traversal, and network
  helper reachable from native UI code appears in the effect audit.
- Normal, IDE, and Zen transitions appear in the parity inventory.
- A reviewer can determine whether a future change belongs to shared behavior,
  UI v1 composition, or UI v2 composition.

**Exit gate:** The contract and parity inventory are complete enough to review
future slices without reading the entire event router.

---

## Prompt 01 — Define and validate the UX contract

**Entry gate:** Prompt 00 is accepted.

**Objective:** Decide interaction semantics before choosing the final shell
layout.

**Mandatory execution split:**

- **01A — Workflow and input contract:** produce the audience workflows,
  focus/input rules, responsive invariants, and evaluation script.
- **01B — Prototypes:** produce all shell/viewport combinations using 01A's
  fixed script; do not choose a winner.
- **01C — Validation and product decision:** run the evaluation, record
  evidence/confidence, and approve a design. This is owned by the product/UX
  decision-maker. If the participant minimum is unavailable, the result may be
  marked provisional for engineering exploration but cannot satisfy the
  default-on release gate.

**Implementation prompt:**

> Produce the UI v2 UX contract and low-fidelity terminal prototypes. Do not
> commit to an icon-only navigation rail. Identify the ten highest-value user
> workflows for each of these audiences: IDE-oriented beginners, experienced
> Neovim users, and SSH/keyboard-only users. Workflows should include the full
> path across regions, such as opening a file, editing it, inspecting a
> problem, opening a terminal, and returning to the editor.
>
> Specify:
>
> - a single focus-owner model and valid focus graph;
> - focus entry, traversal, restoration, and failure fallback;
> - modal versus non-modal overlays;
> - exact Escape/pass-through behavior for editor modes, embedded terminals,
>   sidebars, drawers, dialogs, and nested overlays;
> - mode invariants: Normal and IDE are editor-input policy presets over one
>   shell; Zen is a reversible presentation state;
> - what state survives resize and mode transitions;
> - task-equivalence rules for keyboard and pointer input;
> - non-color indicators for focus, selection, errors, unread counts, loading,
>   and disabled controls;
> - a searchable command registry as a discoverability layer, without making
>   it the only discoverability mechanism.
>
> Define an ordered input-resolution contract for every `FocusTarget`, not only
> an Escape table. The top explicit modal receives input first according to its
> dismissal, confirmation, and editing rules. An active terminal escape prefix
> receives its documented next key. Otherwise the focused target handles only
> commands explicitly defined for it, including navigation, activation, and
> focus return. Input unhandled by focused Neovim or terminal surfaces passes
> through unchanged; define unhandled input for native surfaces explicitly and
> never forward it to a hidden editor or terminal. Do not rely on plain Escape as the sole way to
> leave a sidebar or drawer. If a native surface consumes it, the assignment
> must be explicit, consistent, visible, and proven unable to intercept editor
> or terminal input. Cover non-dismissible modals, unsaved changes, nested
> overlays, repeated Escape, and invalid restoration targets.
>
> A valid keyboard focus owner must be enabled, currently visible, and reachable
> in the active layout. Hidden terminals or auxiliary surfaces may retain
> sessions and receive output but cannot retain keyboard focus. Define fallback
> to the most recent valid visible target or deterministically to the editor
> when the former owner is hidden, destroyed, disabled, removed by an
> async completion, or excluded by a responsive-tier change. Also define
> initial focus, resume, terminal re-entry, clicks outside modals, and failed
> effects.
>
> Define task equivalence per workflow: completion, cancellation, error
> recovery, final focus, and preserved state for keyboard and pointer paths.
> Essential workflows must be keyboard-completable. Every context-menu or
> clickable command must also be reachable by keyboard or command registry.
> Record justified exceptions such as mouse-owning terminal applications.
>
> Define a discoverability ladder: persistent labels or mnemonic text for
> primary regions where space permits; contextual hints on entering specialized
> focus; visible close/return instructions for overlays and terminal focus;
> searchable commands and current shortcuts in Help/palette; and onboarding
> only for concepts that cannot be learned safely in context. Icon-only
> affordances require a text alternative available without hover.
>
> Create three cell-level shell alternatives: labeled collapsible navigation,
> mnemonic text rail, and command-first/no-permanent-rail. Show each at
> `120x40`, `80x24`, `60x20`, and `40x12`. Define named responsive tiers:
> comfortable, compact, constrained, and emergency. Width and height must be
> treated independently. In constrained mode, preserve the editor and one
> auxiliary surface; in emergency mode, provide deterministic editor-only or
> resize guidance without overlapping or unreachable controls.
> Derive transitions from the minimum usable dimensions of the editor and
> active auxiliary surface rather than width alone or arbitrary global
> constants. Specify behavior below, at, and above every boundary and prevent
> oscillation. A tier may change presentation but cannot change command
> semantics or discard hidden state. Emergency mode may suspend auxiliaries,
> but retains editor access, visible recovery/resize guidance, and keyboard
> access to Help and quit.
>
> Evaluate every alternative with the same scripted workflows, initial state,
> viewport, and participant information. Record completion, unrecoverable
> errors, wrong-region focus events, requests for help, discoverability
> failures, and qualitative feedback; do not rank designs by speed alone.
> Prefer lightweight workflow sessions with at
> least two IDE-oriented users, two Neovim-oriented users, and one SSH-focused
> user. If external sessions are unavailable, document an internal dogfood
> protocol. Internal dogfood may find defects and provisional preferences but
> is not user validation. Record familiarity, terminal, input method, viewport,
> decision owner, and confidence. The minimum decision gate is: no essential
> workflow is unreachable, no participant is trapped without visible recovery,
> focus and editor-return are identifiable, and there is no material
> discoverability regression for beginner or keyboard-only workflows.

**Required verification:**

- Essential workflows are traceable to visible or searchable commands.
- No input intended for focused Neovim or terminal surfaces is consumed by the
  shell. Every shell-consumed Escape is authorized by the approved routing
  table, visibly discoverable where needed, and covered by a routing test.
- Every shell alternative is evaluated using the same tasks and viewport set.
- The chosen design includes reasons and rejected alternatives.
- Breakpoint boundary tests cover one row/column below, at, and above each
  transition without oscillation, state loss, unreachable targets, or clipped
  recovery text.
- The workflow inventory contains an input-equivalence matrix and equivalent
  destructive-action confirmation on keyboard and pointer paths.

**Exit gate:** Focus, Escape, modes, responsive tiers, and navigation are
specified well enough to become automated state and layout tests.

---

## Prompt 02 — Make settings versioned, durable, and reversible

**Entry gate:** Prompt 00 is accepted. This prompt may run in parallel with
Prompt 01 but must finish before any persisted UI v2 preference is introduced.

**Objective:** Ensure UI v2 opt-in, rollback, and layout settings cannot corrupt
or silently discard user configuration.

**Implementation prompt:**

> Refactor `SettingsConfig` persistence in
> `src/tui/widgets/settings.zig`. Introduce an explicit schema version and pure
> version-to-version migration functions. Remove the fixed-size input ceiling;
> parse settings with a bounded, dynamically allocated strategy and a clearly
> documented maximum. Separate disposable shell layout state from durable
> editor preferences where appropriate.
>
> Define and document a platform-specific save protocol. On POSIX, reject or
> explicitly resolve symlink targets; create a unique same-directory temporary
> file with restrictive permissions; serialize and parse-validate the result;
> synchronize its contents where supported; apply the intended permission
> policy; close it; atomically replace the target; then synchronize the parent
> directory where supported. Preserve mode/ownership according to a documented
> policy. Treat backup creation as a separate best-effort atomic operation that
> cannot invalidate the primary save, and never replace the last-known-good
> backup until the new primary parses successfully. Clean temporary files on
> failure.
>
> Define the exact document-size limit and error behavior, concurrent-writer
> behavior using a revision token or explicit last-writer policy, backup
> retention, schema support window, and whether the chosen JSON representation
> can round-trip unknown fields. A newer document must either remain writable
> by an older supported release without losing unknown fields or cause that
> release to refuse saving and leave the document byte-for-byte intact. Define
> a documented downgrade export if direct downgrade is unsupported.
>
> Add fixtures and fault injection for every currently supported legacy shape,
> the new schema,
> corrupt and truncated documents, oversized documents, unknown fields,
> future-version documents, read-only storage, interrupted replacement, and
> supported-binary downgrade behavior. Inject failure after every atomic-save
> step; do not rely solely on permission tests when the test identity can
> bypass permissions. A failed load must use safe defaults and retain
> an actionable diagnostic without destroying the source file.

**Required verification:**

- Migration is deterministic and idempotent.
- A failed save leaves either the old valid file or the new valid file.
- UI v1 cannot silently erase UI v2-only state during rollback.
- Symlink, concurrent-writer, permissions, backup ordering, and parent-sync
  policies are documented and tested where the platform supports them.
- Existing settings tests still pass, plus the new fixture matrix.

**Exit gate:** A persisted `ui_shell` preference can be introduced without
creating a configuration-loss or rollback hazard.

---

## Prompt 03 — Add performance observability and deterministic fixtures

**Entry gate:** Prompt 00 is accepted.

**Objective:** Measure freezes and rendering changes precisely enough to gate
later work.

**Implementation prompt:**

> Extend Vide's profiling and diagnostic infrastructure without changing UI
> behavior. Instrument monotonic durations around poll wake-up, input decode,
> RPC decode, callback dispatch, state update, layout, composition, ANSI
> encoding, writer flush, and the blocking sites inventoried by Prompt 00.
> Prefer scoped instrumentation at shared process, RPC, filesystem, renderer,
> and writer boundaries rather than scattering it through widgets. After the
> effect executor exists, move external-operation timing there. Track maximum,
> p50, p95, and p99 where sampling is meaningful. Also track
> emitted bytes, rendered cells, dirty regions, frame count, queue depth,
> cancelled/stale tasks, coalesced events, and editor/terminal Neovim resize
> requests.
>
> Keep normal execution lightweight with fixed-memory aggregation; retaining
> raw samples or allocating per event is permitted only in diagnostics mode.
> Expose detailed traces through an opt-in
> local diagnostics mode. Do not record file contents, typed text, command
> arguments that may contain user data, or raw keystrokes. If diagnostics can
> be attached to bug reports, require the existing explicit review/consent
> flow.
>
> Extend `scripts/profile_vide.py` so two explicit immutable binaries can be
> compared over multiple iterations on the same machine without modifying or
> resetting the active worktree. Identify each artifact by Git commit, Zig
> version, target, optimization mode, and hash. Retain raw
> samples. Separate local scheduling/composition measurements from terminal-
> visible latency. Add deterministic replay fixtures for representative
> Neovim redraw event streams and canonical final-cell-grid snapshots.
>
> Establish a named reference setup and record initial numbers for startup,
> normal typing/navigation, Git view idle and refresh, a large directory, a
> large file, resize storms, terminal output bursts, and idle wakeups.
> Define iteration count, warm-up, workload seed, baseline selection,
> regression/confidence calculation, reference-runner characteristics,
> variance policy, and exception approver before making performance blocking.

**Required verification:**

- Instrumentation can be disabled and has measured low overhead.
- The profiler compares builds from the same runner instead of merely
  validating a stored JSON record.
- Fixtures cover ASCII, CJK, emoji, combining characters, wide-cell
  continuations, styles, cursor movement, and grid lifecycle events.
- Short maximum-frame stalls remain visible rather than being averaged away.

**Exit gate:** Subsequent phases can state measured improvements or regressions
using reproducible evidence.

---

## Prompt 03B — Introduce the interactive reactor seam

**Entry gate:** Prompt 03 is accepted.

**Objective:** Prevent task scheduling and RPC transport from independently
rewriting the main poll loop.

**Implementation prompt:**

> Introduce a central, single-threaded interactive reactor abstraction without
> changing scheduling behavior. It must register poll interests and dispatch
> readiness for terminal input, resize/signal notification, both Neovim read
> and future write interests, and a portable task-completion notifier. The
> reactor is initially one OS thread and exclusively owns `App`, both
> `RpcClient` transports, both `UiState` values, renderer state, and live
> model/widget arenas.
>
> Specify deterministic phases for readiness collection, transport progress,
> normalized event dispatch, state update, composition, flush, and shutdown.
> Do not add workers or asynchronous RPC in this assignment. Preserve existing
> behavior with focused tests and record portable notifier requirements for
> Linux and macOS rather than prematurely prescribing one primitive.

**Required verification:**

- Existing PTY, resize, dual-Neovim, input, and shutdown tests pass.
- Poll sources can be added and removed without dangling pointers or file-
  descriptor reuse errors.
- Phase order and ownership are documented and asserted where practical.

**Exit gate:** Task completion and bounded RPC transport can integrate through
one reviewed poll/dispatch seam.

---

## Prompt 04 — Introduce a safe background task runner

**Entry gate:** Prompts 00, 03, and 03B are accepted.

**Objective:** Remove process, filesystem, and network stalls from the UI
thread without introducing races or unbounded memory.

**Mandatory execution split:**

- **04A — Task-runner design record:** approve worker-count derivation, queue
  capacities, admission/overflow and priority policy per operation, portable
  notifier, I/O/thread ownership, owner/generation lifecycle, cancellation,
  child termination, shutdown deadlines, allocation ownership, and rollback.
- **04B — Deterministic runner:** implement queues, notifier, lifecycle, and a
  fake scheduler with no production widget migration.
- **04C — Git refresh migration:** migrate read-only Git refresh to immutable
  snapshots and measure it. Git mutations remain for Prompt 13.

**Implementation prompt:**

> Design and implement a fixed-size worker pool for blocking external work.
> Before choosing its implementation, verify the pinned Zig version and the
> concurrency guarantees of the project's `std.Io` backend. Do not share an
> I/O backend across OS threads unless its contract permits it; use per-worker
> supported state or isolated blocking POSIX/process operations if necessary.
> Record the choice. Use bounded command and completion queues and the portable
> pollable notification approved in 04A.
> Each task must carry an operation kind, stable owner ID, and generation ID.
> Implement latest-wins coalescing for refresh-style work. Cancellation may
> discard stale results; process termination is required only for explicitly
> cancellable long-running commands.
> Owner IDs are monotonic logical instance IDs, never widget pointers, array
> indices, or reusable enum values alone. Closing an owner invalidates its
> generation; define wrap behavior. Accepted results transfer ownership once,
> while rejected, stale, duplicate, and unknown-owner results are deinitialized
> exactly once.
>
> Define task payload and result tagged unions with explicit ownership. Workers
> may not retain or mutate pointers to `App`, widgets, resettable widget arenas,
> `Renderer`, `UiState`, or `RpcClient`. A worker must build an independently
> owned immutable result. The UI thread validates owner/generation, transfers
> the result into model state, and deinitializes both accepted and stale
> results correctly.
>
> A worker must never wait indefinitely to publish a completion. Publication
> must be shutdown-aware or nonblocking; if it cannot proceed, the worker
> deinitializes the result. Shutdown wakes command and completion waiters and
> continues draining while workers terminate, or closes completion admission
> before joining. Refresh/read tasks may be coalesced or dropped. Explicit user
> mutations may never be silently dropped: queue rejection returns an
> actionable owned error, and mutations carry idempotency/operation IDs.
> Implement orderly shutdown, child reaping, partial-initialization cleanup,
> and allocation-failure handling.
>
> First provide deterministic fake-scheduler tests. Then migrate Git refresh
> to return a `GitSnapshot` containing branch, recent commits, and status. Do
> not call the current arena-resetting `GitPanel.refresh()` on a worker.

**Required verification:**

- Reordered, duplicated, stale, and cancelled completions are tested.
- Closing the Git panel, switching modes, resizing, and quitting during
  refresh cannot mutate dead state or leak memory.
- Queue capacity is bounded under refresh storms.
- Tests fill both queues and initiate shutdown from every blocked state.
- `std.testing.allocator` leak checks and practical allocation-failure tests
  cover partial initialization and all result-disposal paths.
- The reference Git scenario has no periodic multi-hundred-millisecond input
  stall.
- No background thread accesses either RPC client.

**Exit gate:** Git refresh is asynchronous and the task runner is safe enough
to host later filesystem/process migrations.

---

## Prompt 05 — Make interactive RPC bounded and nonblocking

**Entry gate:** Prompts 03, 03B, and 04A are accepted. This work may proceed in
parallel with 04B/04C because both use the approved reactor and ownership
contracts.

**Objective:** Ensure Neovim traffic cannot freeze or starve terminal input.

**Mandatory execution split:**

- **05A — Framing and decoder:** bounded allocation-safe incremental input and
  adversarial fixtures.
- **05B — Async transport:** poll-driven output, pending requests,
  backpressure, and reactor integration for both Neovim clients.
- **05C — Call-site migration:** a checked inventory classifying every site as
  startup-sync, interactive-notification, interactive-async, or prohibited,
  followed by incremental conversion.
- **05D — Dual-session/shutdown hardening:** EOF, HUP, request cancellation,
  timeouts, ID wrap, child failure, and every populated pending state.

**Implementation prompt:**

> Refactor `src/nvim/rpc.zig`, `src/nvim/helpers.zig`, and the main event loop
> into a bounded interactive RPC state machine. Keep both Neovim clients owned
> by the same UI/RPC execution context. Add outbound queues and pending-request
> tracking keyed by request ID. Interactive requests must complete through
> later messages rather than synchronously waiting inside event handling.
>
> Decode only complete messages already available in the buffered reader.
> Replace retry-by-cursor-rewind with an incremental design that is allocation-
> safe on incomplete input: retain explicit parser state or roll back every
> allocation from the attempt. Define maximum buffered bytes, nesting depth,
> collection/string sizes, and behavior for indefinitely incomplete or
> oversized frames. Preserve complete buffered messages when HUP follows the
> final read. Incomplete input returns control without a fixed wait. Bound
> inbound draining by elapsed time as well as
> message count, and return to terminal input when the budget expires.
> Dispatch notifications and response completions only at documented event-loop
> points; avoid callbacks executing recursively from an outbound send.
>
> Encode each outbound envelope into an owned buffer with a retained write
> offset. Request `POLLOUT` only while bytes remain and advance writes only in
> the reactor transport phase. Never dispatch inbound callbacks while encoding
> or flushing output. Queue protocol-required replies through the same
> transport with defined priority and per-channel ordering. Keep independent
> transport state per Neovim process. Define request-ID wrap,
> unknown/late/duplicate responses, owned result/error completion, pending-call
> failure on EOF/shutdown, request cancellation/timeouts, queue overflow, and
> notification-parameter borrowing lifetime.
>
> Backpressure must be explicit. Bound queues and buffers, define overflow
> behavior, and preserve ordering required by Neovim. Synchronous calls may
> remain during startup before the interactive loop when justified and
> documented. Convert interactive `rpc.call` sites to notifications or async
> request/completion messages incrementally, with tests for interleaved
> notifications, responses, partial frames, child closure, and malformed
> bounded payloads.

**Required verification:**

- No interactive RPC call waits synchronously for a response.
- No partial frame stalls one loop iteration.
- No callback is re-entered from an outbound write.
- RPC bursts cannot starve terminal input under the elapsed-time budget.
- Both embedded Neovim sessions retain correct ordering and shutdown behavior.
- Existing protocol and PTY integration tests pass.
- Decoder tests cover byte-by-byte delivery, truncation at every byte boundary,
  allocation failure, excessive nesting, oversized lengths, multiple frames
  in one read, and valid buffered data followed by HUP.
- The checked RPC inventory contains zero unclassified interactive call sites.
- Leak/deinit tests cover partial initialization and every pending/queued state.

**Exit gate:** RPC scheduling is bounded, single-owner, non-reentrant, and safe
for UI v2 state/effect dispatch.

---

## Prompt 06 — Separate invalidation and Neovim sizing

**Entry gate:** Prompts 03 and 05B are accepted.

**Objective:** Stop ordinary UI updates from resizing Neovim and establish
coarse retained composition.

**Implementation prompt:**

> Replace the overloaded `App.needs_resize` state with explicit invalidation
> domains. At minimum distinguish layout changes, composition damage, physical
> terminal size, editor Neovim size, terminal Neovim size, and cursor damage.
> Represent composition damage initially as coarse regions: chrome, sidebar,
> editor, drawer, and overlay.
>
> Cache the last dimensions sent to each Neovim UI and issue
> `nvim_ui_try_resize` only when the computed dimensions actually change.
> First make `UiState.handleRedraw` return conservative grid-level damage and
> lifecycle changes. Convert it to editor screen-region damage only after the
> complete redraw batch has updated multigrid positions and z-order. It is
> initially correct to damage the complete editor region for scroll, resize,
> float movement, or uncertain composition. Optimize only after correctness
> fixtures pass. Define forced-full-redraw causes explicitly.
>
> Audit every current `needs_resize` assignment and classify it. Add tests
> proving that focus, hover, selection, notifications, async completions, and
> cursor movement do not send resize requests unless layout dimensions changed.

**Required verification:**

- Zero resize RPCs occur for ordinary focus, selection, hover, or notice
  updates.
- Editor and terminal sizes update correctly for terminal resize, sidebar
  changes, drawer orientation/size, and mode transitions.
- Full redraw after resize, resume, theme change, and recovery remains correct.
- Damage never leaves stale cells when a region shrinks, closes, or is covered
  by an overlay.

**Exit gate:** Layout, paint, cursor, and child-UI sizing are independently
observable and correct.

---

## Prompt 07 — Optimize composition and ANSI output

**Entry gate:** Prompts 03 and 06 are accepted.

**Objective:** Reduce frame CPU and terminal output without breaking terminal
correctness.

**Mandatory execution split:**

- **07A — Row-run ANSI encoder:** retain full composition and change only
  terminal encoding/output.
- **07B — Retained coarse-region composition:** use the proven encoder while
  retaining unaffected chrome/sidebar/editor/drawer/overlay regions.
- **07C — Optional fine-grained optimization:** add smaller damage merging only
  if profiling proves it worthwhile. This sub-prompt may be skipped with a
  recorded performance decision.

**Implementation prompt:**

> Refactor workspace composition so unaffected coarse regions retain their
> cells rather than beginning every loop with a full-screen clear and rebuild.
> Continue using a final current-versus-previous cell comparison for safety.
> Compose damaged regions in deterministic z-order and ensure closing or moving
> an overlay damages what it previously covered.
>
> Replace per-changed-cell absolute cursor movement in `Renderer.flush()` with
> row-oriented changed-run encoding. Batch only where doing so is cheaper and
> correct. Handle double-width and continuation cells, combining characters,
> style transitions, unchanged gaps, background erasure, the right margin,
> terminal wrapping, cursor visibility, and final cursor restoration. A small
> cost heuristic may choose between writing a short unchanged gap and emitting
> a cursor movement.
>
> Keep one flush per frame and a forced full-redraw encoder path. Add golden
> tests for encoded terminal behavior and canonical cell-grid results. Measure
> composition time, encoding time, output bytes, resize-storm performance, idle
> CPU, and startup impact against the explicit immutable baseline artifact
> defined by Prompt 03.

**Required verification:**

- Resize-storm output bytes improve materially; retain a target of at least
  50% on the named reference setup unless evidence supports a revised target.
- On the named controlled runner and deterministic fixture, no measured
  composition or ANSI-encoding phase exceeds the agreed algorithmic budget;
  retain 50 ms as an initial investigation threshold rather than attributing
  scheduler or writer stalls without phase evidence. Candidate p99 must remain
  within the documented tolerance and confidence policy.
- Idle CPU/wakeups and startup settled time do not regress more than 10%
  without an accepted explanation.
- Unicode, right-edge, style, overlay, and cursor golden tests pass.
- Forced redraw repairs the screen after simulated terminal corruption.

**Exit gate:** The renderer and composer are efficient enough that shell work
will not conceal existing freezes.

---

## Prompt 08 — Introduce typed state, commands, effects, and focus

**Entry gate:** Prompts 01C, 04B, 05D, 06, and 07B are accepted.

**Objective:** Create one shared behavioral architecture for both shells.

**Mandatory execution split:**

- **08A — Types and ownership:** candidate `UiModel`, `Action`, `Message`, and
  `Effect` descriptors with explicit allocation/deinit contracts.
- **08B — Pure reducer/controller sequencing:** shell-level state only; no
  external execution.
- **08C — Effect executor:** connect approved RPC/task boundaries while keeping
  bounded startup/bootstrap work on Prompt 00's explicit allowlist.
- **08D — Command registry:** stable IDs, labels, shortcuts, availability, and
  conflict detection.
- **08E — Focus/overlay state machine:** implement the approved ordered input
  and restoration contract.
- **08F — Legacy projection adapters:** expose candidate shared semantics to v1
  without yet making the candidate reducer authoritative.

**Implementation prompt:**

> Introduce explicit tagged unions and modules for `UiModel`, user/system
> `Action`, external `Effect`, completion `Message`, and `FocusTarget`. The
> reducer is pure: it updates candidate model state and returns effect
> descriptions. The controller sequences actions and messages. The effect
> executor must be the only interactive place
> that performs RPC, task-runner, filesystem, process, or network operations.
> Bounded synchronous startup/bootstrap code may remain outside it only when
> listed in Prompt 00's allowlist.
> This rule initially applies to shell-level behavior migrated in 08–09.
> Unmigrated legacy widgets may temporarily execute only direct effects
> inventoried and approved by Prompt 00 through explicit compatibility
> adapters; they are unreachable from UI v2 until their slice migrates. Each
> accepted slice moves its effects to the shared executor and deletes its
> exception. No new direct widget effect may be added.
>
> Add one command registry containing stable command IDs, labels, categories,
> current shortcuts, availability predicates, and action construction. Menus,
> the future palette, contextual hints, and key-conflict checks must consume
> this registry rather than defining parallel command lists.
>
> Replace independent focus booleans with exactly one `FocusTarget` plus a
> restoration history for modal overlays and transient surfaces. Encode the UX
> contract from Prompt 01, including focus-specific Escape/pass-through rules.
> Add semantic fields such as role, label, selected/current/focused, disabled,
> loading, and error to the view model so tests can assert meaning independently
> of colors and terminal escape encoding.
> Define an announcement as a visible, persistent-enough status/message region
> plus a semantic test event, not unverified assistive-technology integration.
> Announcements cannot steal focus, overwrite higher-priority messages without
> policy, or disappear before they can be inspected. Test priority,
> replacement, persistence, and history/review behavior.
>
> Keep current widgets operational through narrow adapters. Do not introduce a
> generic function-pointer component interface yet. Make payload ownership and
> deinitialization explicit in every action/effect/message path.

**Required verification:**

- Reducer tests cover sidebar/drawer exclusivity, overlays, modes, async
  completion, errors, cancellation, and focus restoration.
- Property/state tests execute long randomized focus/open/close/resize traces,
  including async removal, tier changes, overlay replacement, terminal exit,
  and restoration-history exhaustion. Hidden, destroyed, disabled, or
  geometrically unreachable controls cannot own keyboard focus or receive user
  input, although hidden sessions may remain alive and receive output.
- Escape and other unhandled input reach focused Neovim or terminal surfaces
  unchanged. Every consumed Escape is justified by the approved per-focus
  routing contract and tested. Every focus target has a visible keyboard route
  back to the editor.
- Shell-level views and migrated slices initiate no effects directly. Every
  legacy direct-effect path is inventoried, unreachable from UI v2, and names
  its removal prompt.
- New feature behavior is added through the shared command/controller path.

**Exit gate:** The candidate shared reducer, effects, commands, focus, and
legacy semantic projection are available for audit. Legacy state remains
authoritative until Prompt 09 cutover.

---

## Prompt 09 — Audit and cut over to the shared model

**Entry gate:** Prompt 08 is accepted.

**Objective:** Detect behavioral divergence before rendering UI v2.

**Mandatory execution split:**

- **09A — Legacy-authoritative audit:** the candidate reducer predicts only;
  deterministic traces establish semantic/effect-descriptor parity.
- **09B — Shared-model cutover:** make shell-level shared state authoritative
  behind a rollback switch while reverse comparison remains enabled.
- **09C — Stabilize and remove audit machinery:** predeclare duration or trace
  count, owner, failure threshold, and rollback trigger; remove temporary audit
  code only after meeting it.

**Implementation prompt:**

> Add a developer-only audit mode. While legacy UI state remains authoritative,
> translate each normalized legacy event into a candidate shared action and
> apply it to an isolated candidate snapshot. Compare semantic projections
> after each stable event-loop turn: active mode,
> active sidebar/drawer, overlay stack, focus owner, panel dimensions, command
> availability, and persisted-state intentions.
>
> Only the authoritative legacy path executes effects. Compare predicted effect
> descriptors without issuing them from audit state. Audit machinery must not
> issue RPC, spawn tasks, save settings, or mutate editor state. It is temporary
> validation infrastructure, never a persistent model owned by UI v2. Redact
> user content from divergence diagnostics.
>
> Build deterministic action traces from the parity inventory and PTY
> workflows. Classify intentional shell-layout differences explicitly. Fix
> shared-model ambiguities rather than adding broad exceptions.
>
> After all required traces pass, make the shared reducer authoritative for UI
> v1 and temporarily compare a legacy projection in the opposite direction.
> Remove audit machinery once the accepted stabilization window completes.
> Authoritative cutover applies to shell-level and already migrated behavior;
> unmigrated widget-internal state remains behind inventoried compatibility
> adapters until its vertical slice is accepted.

**Required verification:**

- Shadow mode cannot produce external side effects.
- Normal, IDE, Zen, sidebar, drawer, overlay, resize, and shutdown traces run
  without unexplained divergence.
- Divergence output identifies the action and semantic field without exposing
  file content or keystrokes.

**Exit gate:** The shared behavioral model is authoritative for UI v1, the
audit has no unexplained divergence, and UI v2 can be only a second composition
consumer rather than a second behavioral model.

---

## Prompt 10 — Implement the editor-only UI v2 shell

**Entry gate:** Prompts 02, 07B, 08F, and 09B are accepted. Prompt 01C records
the product decision. Beginning while reverse audit remains active requires an
explicit recorded decision; default-on work still requires 09C.

**Objective:** Prove shell selection, shared state, responsive layout, and
rollback with the smallest possible UI v2 surface.

**Implementation prompt:**

> Add UI shell selection at one composition boundary. Start with a build-time
> developer option and explicit command-line or environment override. Shell
> persistence remains out of scope until Prompt 20A. Use the CLI/environment/
> settings precedence and exact option names approved by Prompt 00. Provide an
> emergency launch override that bypasses persisted shell selection.
> Build shell-local resources transactionally before publishing them. A failed
> v2 initialization deinitializes partial resources and leaves the shared
> model, RPC sessions, terminal mode, and persisted preference unchanged before
> selecting v1.
>
> Implement an editor-only UI v2 shell using the selected UX prototype. It may
> render tabs, minimal navigation affordance, editor viewport, and status/focus
> information, but must not fork editor state, commands, effects, settings, or
> RPC clients. UI v1 and UI v2 consume the same `UiModel` and Neovim grids.
>
> Implement deterministic responsive tiers and full mode round trips. F11 and
> other transitions must preserve active file, editor cursor, prior valid
> focus, and applicable shell state. Add semantic layout tests and canonical
> cell-grid snapshots at the four reference sizes, true-color, 256-color, and
> portable-symbol modes.

**Required verification:**

- `--ui=v1` and `--ui=v2` choose only composition/layout implementations.
- A v2 initialization failure can return to v1 with an actionable diagnostic;
  runtime corruption does not silently fall back.
- Normal, IDE, and Zen editor workflows work in PTY tests.
- No duplicated Neovim process, editor state, or effect occurs.
- Emergency dimensions never overlap or hide the only recovery instruction.
- Layout tests assert focusable targets and deterministic fallback focus, not
  only rectangle bounds. At every tier, a first-time user can identify the
  editor, available primary regions, current focus, and route to Help without
  pointer hover or icon-font support.

**Exit gate:** The v2 shell safely hosts the editor and can be selected or
recovered without changing application behavior.

---

## Prompt 11 — Port Explorer as the reference vertical slice

**Entry gate:** Prompt 10 is accepted.

**Objective:** Establish the complete pattern for a migrated asynchronous,
keyboard/mouse-accessible UI v2 feature.

**Mandatory execution split:**

- **11A — Read-only Explorer:** navigation, expansion, selection, scroll,
  open, shared geometry, and semantic tests.
- **11B — Async refresh:** owned snapshots, coalescing, state preservation,
  lifecycle, and error tests.
- **11C — Mutation contract and implementation:** approve trash versus
  permanent deletion, confirmation, symlink/workspace-boundary behavior, race
  handling, and recovery before create/rename/delete code.
- **11D — Responsive/PTY hardening:** complete workflow, property,
  performance, allocation, and shutdown verification.

**Implementation prompt:**

> Port Explorer to UI v2 as a full vertical slice. Separate filesystem data,
> selection/expansion/scroll state, commands, async effects, and view
> composition. Directory scans and refreshes must use the task runner with
> independently owned snapshots, generation IDs, stale-result disposal, and
> latest-wins refresh behavior.
>
> Derive row layout and click targets from one geometry result. Implement
> keyboard navigation, pointer task-equivalence, create/rename/delete
> confirmations, context actions, loading, empty, and recoverable error states.
> Preserve selection and scroll where valid after refresh, resize, sidebar
> closure, mode changes, and async completion. Background completion must not
> steal focus or automatically reopen Explorer.
> Treat create, rename, and delete as ordered mutations, never latest-wins
> refreshes. Capture owned root-relative/absolute paths at acceptance and
> revalidate the workspace root and target immediately before mutation. Reject
> traversal outside the configured root under the approved symlink policy. A
> successful mutation schedules refresh after its completion barrier; a stale
> pre-mutation scan cannot replace post-mutation state.
>
> Use the shared command registry and focus/overlay rules. Keep the v1 adapter
> frozen except for shared bug fixes, and record its removal condition.

**Required verification:**

- Explorer has no synchronous traversal or RPC call in event handling.
- Keyboard-only and pointer workflows cover open, expand, collapse, scroll,
  create, rename, delete, cancel, and error recovery.
- Tests cover large directories, permission errors, disappearing paths,
  completion after closure, repeated refresh, and shutdown during scanning.
- Geometry, semantic state, and cell-grid snapshots pass at all responsive
  tiers.
- Semantic snapshots contain no unlabeled action, pointer-only command,
  disabled action without a reason, or nondeterministic navigation order.
- Selection identity survives insertion, removal, filtering, refresh, and
  virtualization without relying only on row index.
- Performance and memory stay within established budgets.

**Exit gate:** Explorer demonstrates the approved architecture and supplies
evidence for or against extracting a common view/component contract.

---

## Prompt 12 — Port Search

**Entry gate:** Prompt 11 is accepted.

**Objective:** Validate text input, result streaming/replacement, and focus
behavior in the shared architecture.

**Implementation prompt:**

> Port Search to UI v2 using the shared model, command registry, task/RPC
> completion mechanisms, focus model, and sidebar host. Define query ownership,
> debounce/coalescing, result generation IDs, stale-result disposal, selection,
> preview/open behavior, empty/loading/error states, and cancellation.
>
> Do not let search completion steal focus, reopen the sidebar, or replace a
> newer query's results. Ensure text input is routed to Search only while its
> input target owns focus and that editor/terminal Escape behavior remains
> intact outside explicit search focus.
> First audit `search_panel.zig`, embedded Lua/Telescope integration, and RPC
> notifications to identify which boundary actually produces results. Apply
> generation IDs there; do not invent a worker-based search engine merely to
> conform to this prompt.

**Required verification:**

- Rapid query changes and reordered completions display only the latest valid
  result set.
- Keyboard and pointer task-equivalence covers query, navigation, open,
  cancellation, and return to editor.
- Search behaves correctly across resize, mode transition, sidebar switching,
  and file disappearance.
- No synchronous side effect is added to the UI path.

**Exit gate:** Two sidebar slices validate the shared state/effect/geometry
approach.

---

## Prompt 13 — Port Git

**Entry gate:** Prompts 11 and 12 are accepted; asynchronous Git snapshots from
Prompt 04 are stable.

**Objective:** Complete the source-control workflow without periodic UI stalls.

**Implementation prompt:**

> Port Git status, branch, history, staging, unstaging, commit, and detailed
> views to the UI v2 sidebar/overlay architecture. Reuse the asynchronous task
> runner and return immutable result snapshots. Coalesce automatic refreshes,
> prioritize explicit user actions, discard stale results, and show persistent
> non-color loading/error state without stealing focus.
>
> Ensure mutations trigger an intentional refresh only after their completion.
> Do not reset live arenas from worker threads. Define behavior outside a Git
> repository, with large status output, slow hooks, detached HEAD, deleted
> files, and subprocess failure.
> Serialize mutations per repository and give each an operation ID. A refresh
> requested during a mutation runs after its completion barrier. A snapshot
> created before the latest completed mutation cannot replace post-mutation
> state. Define explicit progress and cancellation policy for long commit hooks.

**Required verification:**

- The Git view produces no periodic input hitch.
- Actions and refreshes remain ordered under rapid staging/unstaging.
- Closing or switching the panel during work is safe.
- Keyboard/pointer workflows and error recovery pass.
- p99/max frame time, queue depth, memory, and process reaping remain bounded.

**Exit gate:** Explorer, Search, and Git establish whether a small common view
contract is justified. Extract one only if the shared behavior is concrete and
reduces code without hiding ownership or control flow.

---

## Prompt 14 — Implement the unified drawer and port Terminal

**Entry gate:** Prompt 10 is accepted and the focus/Escape contract has passing
tests.

**Objective:** Introduce one predictable auxiliary-surface host and validate it
with the embedded terminal.

**Mandatory execution split:**

- **14A — Drawer host:** orientation, size, tabs, focus, responsive geometry,
  persistence boundary, and semantic/layout tests with fake content.
- **14B — Terminal input contract:** approve focus-return chord, escape prefix,
  collision analysis, pass-through, and discoverability before routing changes.
- **14C — Terminal port:** integrate the existing terminal Neovim session.
- **14D — PTY/responsive hardening:** transport, mode, resize, shutdown, and
  compatibility evidence.

**Implementation prompt:**

> Implement the unified drawer host with bottom and right orientations,
> remembered size per orientation, explicit active tab, non-color focus marker,
> and responsive behavior. Do not move orientation while the drawer owns focus
> unless the current viewport makes it impossible; if it must move, preserve
> content and announce the layout change.
>
> Port the integrated terminal as the first drawer surface. Specify a reliable
> focus-return chord and terminal escape-prefix/pass-through behavior. Never
> consume terminal input as a shell command unless the documented prefix or
> explicit modal context owns it. Preserve terminal process/session state when
> switching drawer tabs, resizing, changing modes, or temporarily hiding the
> drawer.
> The terminal remains owned by Vide's second embedded Neovim session. Its
> input, resize, and redraw use the bounded RPC transport on the interactive
> reactor; hiding the drawer must not detach, recreate, or transfer that
> session. Only independent blocking helper processes belong to workers.
> Test the focus-return chord and escape prefix against common shell/readline
> bindings, Neovim Terminal mode, tmux, SSH, paste, mouse reporting, and
> applications consuming arbitrary controls. Display the return chord when
> terminal focus begins and expose it through Help and the command registry.
>
> Async output may update an unread indicator or status notification but must
> not automatically open the drawer or steal focus.

**Required verification:**

- Terminal typing, control sequences, paste, mouse reporting, splits, resize,
  hide/show, focus return, and shutdown pass PTY tests.
- Drawer geometry and hit targets match at every responsive tier.
- Short terminals prefer a side drawer or mutually exclusive auxiliary view
  according to the UX contract; narrow terminals avoid unusable side drawers.
- Normal/IDE/Zen round trips preserve valid terminal and focus state.

**Exit gate:** The drawer safely hosts an interactive subprocess without input
ambiguity or state loss.

---

## Prompt 15 — Port Problems, Output, and Debug

**Entry gate:** Prompt 14 is accepted.

**Objective:** Complete the unified drawer's read-oriented development tools.

**Implementation prompt:**

> Port Problems, Output, and Debug into the shared drawer. Problems must be a
> first-class surface with readable severity and unread/error counts that do
> not depend solely on color. Use shared list selection, scrolling, loading,
> empty, error, and navigation behavior where it is already proven useful.
>
> Updates arriving in an inactive drawer tab should update badges/status but
> never open the drawer or change focus. Selecting a problem may navigate the
> shared editor through a controller effect and then restore focus according to
> the UX contract. Large output must be bounded or virtualized so composition,
> allocation, and terminal bytes remain within budgets.

**Required verification:**

- Keyboard and pointer workflows cover tab selection, scroll, clear, navigate,
  copy where supported, and return to editor.
- Large output bursts cannot starve terminal input or grow memory without a
  bound.
- Diagnostics changes and async refreshes never steal focus.
- Drawer state survives resize, mode transitions, and hide/show.

**Exit gate:** All primary auxiliary surfaces use one drawer model.

---

## Prompt 16 — Build shared overlays and port Settings

**Entry gate:** Prompts 02, 08, and 10 are accepted.

**Objective:** Establish one accessible modal/non-modal overlay system using a
high-value complex screen.

**Implementation prompt:**

> Implement the UI v2 overlay host from the UX contract. Support explicit
> modal/non-modal classification, stacking rules, maximum safe dimensions,
> full-screen constrained fallback, scroll indicators, visible title and close
> instructions, primary/secondary actions, non-color focus, and restoration to
> the previous valid focus owner.
>
> Port Settings onto this host without changing the shared settings model.
> Group settings by user intent, expose searchable commands and current
> shortcuts, preserve unsaved-change confirmation, and keep previews reversible.
> Saving must use the durable versioned mechanism from Prompt 02. Errors must be
> persistent and actionable rather than color-only or transient.

**Required verification:**

- Overlay title, close instruction, primary action, and scroll indication are
  reachable at every supported tier.
- Nested confirmation and close/restoration sequences pass state tests.
- Settings load, edit, preview, save, cancel, corrupt-file recovery, and
  rollback fixtures pass.
- Escape behavior for modal, non-modal, nested, non-dismissible, and unsaved-
  change overlays matches the approved ordered input contract; dismissal
  restores the most recent valid visible focus owner.

**Exit gate:** The overlay system is stable enough to host the remaining modal
and full-screen native tools.

---

## Prompt 17 — Port Extensions, Mason, and Lazy

**Entry gate:** Prompts 04, 05, and 16 are accepted.

**Objective:** Migrate package and extension management without blocking,
unbounded output, or inconsistent dialogs.

**Mandatory execution split:**

- **17A — Extension Shop:** search/catalog and install/remove workflows.
- **17B — Mason:** package state and install/update/remove workflows.
- **17C — Lazy:** plugin state and update/clean workflows.

Each is a separate accepted slice with its own failure, cancellation,
idempotency, performance, rollback, and removal evidence. Do not hold all three
in one long-lived implementation branch.

**Implementation prompt:**

> Port Extension Shop, Mason, and Lazy workflows to the shared overlay,
> command, effect, and task infrastructure. Separate browsing/search state from
> install/update/remove operations. Model long-running work explicitly with
> progress, cancellation where safe, completion, and recoverable failure.
> Network/process work belongs to bounded tasks; Neovim-owned package commands
> belong to async RPC requests owned by the UI/RPC context.
>
> Never run package actions twice because an overlay reopened or a completion
> was replayed. Require explicit confirmation for destructive operations and
> define what can be safely cancelled. Preserve logs for diagnosis without
> exposing secrets.

**Required verification:**

- Offline, timeout, malformed result, partial install, retry, close-during-work,
  and shutdown scenarios are tested.
- Progress updates remain bounded and do not starve input.
- Focus and overlay restoration follow the shared contract.
- Existing plugin compatibility and smoke tests pass.

**Exit gate:** Package-management surfaces no longer require independent
geometry, focus, or blocking execution paths.

---

## Prompt 18 — Port AI and bug reporting

**Entry gate:** Prompts 14, 16, and 17 are accepted.

**Objective:** Finish migration of externally integrated and privacy-sensitive
surfaces.

**Implementation prompt:**

> Port the AI workspace and bug reporter to the shared drawer/overlay and
> effect architecture. Preserve source-aware context actions and terminal
> sessions without duplicating command definitions. Clearly distinguish local
> UI state, spawned CLI state, editor RPC effects, network submission, and
> consent-sensitive diagnostic attachment.
>
> Background completion must not steal focus or open a surface. Bug-report
> diagnostics must exclude file contents and raw keystrokes and require
> explicit user review/consent before attachment. Submission must handle
> offline, timeout, retry, cancellation, closure, and shutdown safely.

**Required verification:**

- AI launch/focus/restart/context workflows preserve editor and terminal
  ownership rules.
- Consent choices and attached diagnostic contents are tested.
- No duplicate submission or CLI launch occurs under repeated actions.
- Failure remains nonfatal and actionable.

**Exit gate:** Every surface in Prompt 00's inventory—including activity/tab
chrome, editor context menus, log consoles, and detailed Git views—is migrated,
intentionally retired with a product decision, or recorded as blocking. All
remaining surfaces use the shared UI v2 architecture.

---

## Prompt 19 — Apply the visual and accessibility system

**Entry gate:** Prompts 11 through 18 are accepted. Interaction and ownership
patterns are stable.

**Objective:** Make UI v2 visually coherent without changing its behavioral
architecture.

**Implementation prompt:**

> Define and apply semantic theme tokens for region backgrounds, spacing,
> borders, primary/secondary text, focus, selection, current item, disabled,
> loading, warning, error, and success states. Reduce unnecessary borders and
> use spacing/background hierarchy where terminals permit it. Focus and
> selection must remain distinct.
>
> Provide true-color, 256-color, high-contrast/no-color, Nerd Font, and portable
> symbol treatments. Every color-coded state also requires text, symbol, or
> shape. Verify Unicode width and fallback behavior for ASCII, CJK, emoji, and
> combining sequences. If animation is introduced, it must be optional and
> have a reduced-motion path; animation may not increase input latency.
>
> Update reproducible screenshots and cell-grid goldens only after semantic
> review. Do not alter commands, focus rules, effects, or persistence merely to
> accommodate styling.
> Do not assume requested RGB/indexed colors or attributes render faithfully.
> Remain interpretable with user-remapped palettes and suppressed bold,
> italic, underline, dim, reverse, or other attributes. Never use dim or blink
> as the only disabled/urgent cue; avoid rapid flashing and repeated full-region
> inversion. Define truncation/wrapping for paths, diagnostics, commands, and
> long text, preserving distinguishing content and offering the full value
> through a keyboard-accessible detail action rather than hover alone.

**Required verification:**

- Users can identify focus and return to the editor without relying on color.
- Selected versus focused is distinguishable in monochrome and 256-color
  snapshots.
- Portable-symbol mode has no missing glyphs or column drift.
- All responsive tiers retain readable hierarchy and recovery instructions.
- Focus, selection, current item, disabled, loading, warning, and error remain
  pairwise distinguishable where they coexist under monochrome, remapped light
  and dark palettes, common color-vision-deficiency simulations, disabled text
  attributes, and ASCII-only fallback. This is not a claim of screen-reader
  support.

**Exit gate:** UI v2 has one reviewed visual language across every migrated
surface.

---

## Prompt 20 — Run the opt-in beta and harden release evidence

**Entry gate:** Prompts 10 through 19 are accepted and no known P0/P1 issue
blocks core workflows.

**Objective:** Validate UI v2 with real transports and release artifacts before
making it the default.

**Mandatory execution split:**

- **20A — Beta-ready implementation:** explicit opt-in, emergency override,
  local diagnostics, persisted preference, recovery, and documentation.
- **20B — CI/artifact qualification:** exact artifact workflows, resource/flake
  policy, and controlled candidate/baseline jobs.
- **20C — Compatibility evidence:** CI or named manual owners record Linux,
  macOS, WSL, tmux, and SSH results. Missing environments block promotion and
  never authorize fabricated validation.
- **20D — Beta operation:** a release owner runs the predeclared minimum
  duration/cohort, issue-severity policy, rollback triggers, and representative
  user workflow revalidation. This is operational work, not a coding-agent
  assignment.
- **20E — Go/no-go review:** review the collected evidence and exceptions; do
  not infer acceptance from elapsed calendar time.

**Implementation prompt:**

> Enable explicit opt-in beta selection while retaining the emergency v1
> override. Add local, privacy-preserving diagnostics sufficient to understand
> performance, capability profile, viewport, mode, stale/cancelled work, and
> recovery usage. Do not add remote telemetry without a separate product and
> privacy decision.
>
> Expand CI and release validation so exact shipped archive/AppImage artifacts,
> not only source builds, receive launch, version, PTY workflow, terminal
> restoration, settings migration, and relevant compatibility coverage. Record
> observed evidence for Linux, macOS, WSL, tmux, and SSH. Make supported macOS
> behavior blocking rather than permanently `continue-on-error` before
> default-on.
> Maintain a platform evidence matrix with rows for Linux archives/AppImage,
> macOS build/runtime, WSL, SSH, and tmux, and columns for automated blocking
> coverage, scheduled/manual evidence, owner, required workflows, evidence age,
> and default-on/removal status. Do not imply a packaging format exists where
> only source-build/runtime support is offered.
>
> Run multiple-iteration candidate-versus-v1 performance comparisons on the
> same runner. Track absolute stalls and relative regressions. Soak input,
> resize, Git refresh, output bursts, mode changes, shell changes, and shutdown.
> Define the beta cohort or minimum exposure period before starting it.
> Repeat representative implemented-shell workflows with the audience groups
> from Prompt 01 and compare them with prototype findings. Internal dogfood is
> not relabeled as external validation.

**Required verification:**

- All Normal/IDE/Zen core PTY workflows pass in v2.
- Explorer, Search, Git, terminal, settings, and recovery have no open P0/P1
  defects.
- Controlled phase-local composition/encoding results meet Prompt 03's
  deterministic budget and statistical policy; whole-loop wall-clock maxima
  remain diagnostic rather than being misattributed to algorithms. No
  reproducible multi-hundred-ms external-work stall occurs.
- Candidate p95 and p99 input-to-flush satisfy Prompt 03's predeclared absolute
  budget and permitted regression interval against immutable v1 and current-
  main artifacts on the controlled runner. A meaningful regression outside it
  requires an approved exception with owner, rationale, expiry, and issue.
- Idle CPU/wakeups, startup settled time, and memory remain within the
  predeclared 10% goal or have the same recorded, expiring exception.
- Settings migration and downgrade fixtures pass for every released schema.

**Exit gate:** The defined beta cohort or exposure period completes without
unresolved data-loss, startup, terminal-restoration, editor-state, or critical
workflow failures.

---

## Prompt 21 — Make UI v2 the default

**Entry gate:** Prompt 20's beta gate is satisfied.

**Objective:** Change the default safely while retaining explicit recovery.

**Implementation prompt:**

> Make UI v2 the default composition shell. Retain `--ui=v1` and the emergency
> launch override. Automatic fallback is allowed only when v2 initialization
> fails before user work begins; runtime failures must restore the terminal,
> retain diagnostics, and be reported rather than silently switching shells.
>
> Persist the shell preference only through the versioned settings mechanism.
> Update onboarding, help, screenshots, architecture documentation, release
> notes, recovery instructions, and bug-report metadata. Release CI must run
> the complete supported artifact matrix.

**Required verification:**

- Fresh install, upgrade, downgrade, corrupt settings, explicit v1, explicit
  v2, and initialization fallback paths work.
- Users cannot be trapped in a shell that fails during startup.
- Exact release artifacts pass the supported workflow matrix.
- A rollback release can be produced without losing user configuration.

**Exit gate:** UI v2 ships as default with a tested, documented v1 recovery
path.

---

## Prompt 22 — Remove UI v1 and migration adapters

**Entry gate:** UI v2 has been default for two stable releases unless a
documented, substantial beta/default cohort provides equivalent evidence. No
open P0/P1 v2 regression, material rollback usage, or unresolved compatibility
class remains.

**Objective:** Finish the migration without leaving permanent dual-shell
complexity.

**Implementation prompt:**

> Audit the parity inventory and adapter-removal criteria. Resolve every item as
> migrated, intentionally removed with a documented product decision, or still
> blocking. Verify current Linux, macOS, WSL, tmux, SSH, true-color, 256-color,
> portable-symbol, and responsive-tier evidence.
>
> Remove UI v1 composition code, shell-selection branches that exist only for
> v1, expired compatibility adapters, v1-only tests, and obsolete settings
> fields. Preserve settings migration and downgrade documentation needed by
> supported releases. Do not remove shared controller, command, effect, editor,
> RPC, or settings behavior merely because it originated in v1.
>
> Run the full unit, reducer, layout, renderer, replay, PTY, compatibility,
> packaging, performance, soak, and release-artifact suites. Review the deletion
> for unreachable behavior and newly dead code.
> Identify and retain the signed/tagged last-v1 release source and artifact
> path. Prove its settings behavior against every schema it may encounter and
> document the highest schema it can safely read, preserve, or refuse to
> rewrite. A rollback release may use that maintained release line; the main
> branch need not retain v1 code. Search for old flags, settings keys,
> documentation, screenshots, packaging arguments, completion scripts, and
> support instructions and resolve every remaining v1 reference.

**Required verification:**

- The parity inventory has no unexplained gaps.
- No v1-only state or side-effect implementation remains.
- Migration is idempotent and downgrade behavior is documented and tested.
- Current supported-environment evidence passes.
- A rollback from the retained last-v1 release line is documented and cannot
  rewrite an unsupported settings schema.
- No unexplained v1 product surface remains in code, documentation, packaging,
  completions, screenshots, or support instructions.

**Exit gate:** Vide has one UI shell and one shared behavioral architecture,
with migration code retained only where release compatibility requires it.

---

## Program-level stop conditions

Pause UI v2 shell expansion and correct the foundation if any of these occur:

- interactive RPC or external work still blocks the UI thread;
- a worker accesses live UI/RPC state or queue/memory growth is unbounded;
- v1 and v2 require duplicated behavior or persistence logic;
- a settings migration can lose data or prevents safe startup rollback;
- focus ownership becomes ambiguous or Escape is stolen from editor/terminal;
- a migrated slice regresses maximum frame latency materially;
- responsive behavior produces unreachable controls or an invalid editor
  viewport;
- compatibility failures are hidden by silent fallback;
- test-matrix growth outpaces the removal/freeze of migrated v1 paths.

## Lettered sub-prompt execution cards

These cards make every mandatory split independently assignable. The parent
prompt supplies shared context and constraints; the card supplies the stopping
point. A sub-prompt must not perform work assigned to a later card.

### Prompt 01 cards

**01A — Workflow and input contract.** Entry: 00 accepted. Scope: inventories,
ordered input/focus/mode/responsive/task-equivalence/discoverability contracts,
and fixed evaluation script. Exclude prototypes and product selection. Verify
contract review plus traceability to the parity inventory. Exit: UX owner
accepts testable invariants. Rollback: documentation-only revert.

**01B — Prototypes.** Entry: 01A accepted. Scope: three designs at all four
viewports using fake data and the fixed script. Exclude runtime code and winner
selection. Verify identical tasks/information and breakpoint-boundary layouts.
Exit: prototype/evidence bundle is complete. Rollback: remove prototypes only.

**01C — Validation and decision.** Entry: 01B accepted. Scope: execute the
approved study, record observations/confidence, choose or mark provisional.
Exclude runtime implementation. Verify decision gate and participant evidence.
Exit: product/UX owner signs the choice. Rollback: reopen the decision without
affecting runtime code.

### Prompt 04 cards

**04A — Task design.** Entry: 00, 03, 03B accepted. Scope: one approved design
record covering every item in the parent split, including Zig `std.Io`
thread-safety. Exclude worker code and Git migration. Verify deadlock, ownership,
capacity, portability, and shutdown review. Exit: architecture owner approval.
Rollback: replace the record before implementation.

**04B — Deterministic runner.** Entry: 04A accepted. Scope: queues, workers,
notifier, lifecycle, fake scheduler, allocation/deadlock tests. Exclude
production widgets and RPC access. Verify filled-queue shutdown, failures,
deinit, and bounds. Exit: disabled-by-default runner passes tests. Rollback:
disable/remove the runner with no persisted impact.

**04C — Git refresh.** Entry: 04B accepted. Scope: read-only `GitSnapshot`
refresh and reference measurement. Exclude stage/unstage/commit. Verify stale,
close, shutdown, process-reap, and latency cases. Exit: old periodic refresh is
disabled behind the compatibility seam. Rollback: select the old refresh path.

### Prompt 05 cards

**05A — RPC framing.** Entry: 03B and 04A accepted. Scope: incremental bounded
decoder and adversarial fixtures. Exclude outbound transport and call-site
conversion. Verify every byte boundary, allocation failure, size/depth limits,
multi-frame/HUP behavior. Exit: decoder can replace the old reader behind a
developer switch. Rollback: select old decoder.

**05B — Async transport.** Entry: 05A accepted. Scope: owned outbound buffers,
pending requests, read/write poll interests, ordering/backpressure, and both
transport instances. Exclude application call-site migration. Verify partial
writes, EOF, IDs, pending cleanup, fairness, and dual-session behavior. Exit:
transport API is integrated behind a switch. Rollback: startup-select old
transport before interactive work.

**05C — Call sites.** Entry: 05B accepted. Scope: complete RPC inventory and
incremental conversion of interactive sites. Exclude startup allowlisted calls.
Verify zero unclassified sites and focused behavior per conversion. Exit: no
interactive synchronous call remains. Rollback: per-call compatibility adapter
only while recorded; no global duplicate client.

**05D — Shutdown hardening.** Entry: 05B and 05C accepted. Scope: timeouts,
cancellation, HUP/EOF, child failure, ID wrap, and every populated state.
Exclude UI model work. Verify leak/allocation-failure and PTY shutdown suites.
Exit: architecture/RPC owner approves transport foundation. Rollback: block
later phases rather than weakening shutdown guarantees.

### Prompt 07 cards

**07A — ANSI encoder.** Entry: 03 and 06 accepted. Scope: row-run output only;
retain full composition. Verify Unicode/style/right-edge/cursor goldens and
controlled bytes/time. Exit: encoder switch is safe. Rollback: select old
encoder.

**07B — Retained composition.** Entry: 07A accepted. Scope: coarse-region
retention and conservative damage. Exclude arbitrary rectangle merging. Verify
overlay removal, shrink, resize, resume, themes, full recovery, and cell grids.
Exit: full workspace clear is no longer the normal path. Rollback: force full
composition while keeping 07A.

**07C — Optional fine damage.** Entry: 07B accepted plus profile evidence.
Scope: only the measured bottleneck. Verify statistically against immutable
artifacts and all correctness goldens. Exit: performance owner accepts benefit.
Rollback: retain coarse regions; no other phase depends on 07C.

### Prompt 08 cards

**08A — Types/ownership.** Entry: 01C, 04B, 05D, 06, 07B accepted. Scope:
candidate tagged unions, payload ownership, deinit, semantic fields. Exclude
effects and legacy cutover. Verify compile-time/unit/leak/failure cases. Exit:
architecture review accepts the type contract. Rollback: types remain unused.

**08B — Reducer.** Entry: 08A accepted. Scope: pure shell-level reducer and
controller sequencing. Exclude external execution and widget internals. Verify
determinism, invariants, errors/cancellation descriptions. Exit: deterministic
candidate state traces pass. Rollback: legacy remains authoritative.

**08C — Effect executor.** Entry: 08B, 04B, and 05D accepted. Scope: execute
candidate shell effects through approved task/RPC boundaries. Exclude unmigrated
widget effects. Verify ownership, cancellation, and no direct shell effects.
Exit: executor passes fake and integration tests. Rollback: audit mode predicts
effects without executing them.

**08D — Command registry.** Entry: 08A accepted. Scope: IDs, labels, categories,
shortcuts, availability, action construction, conflicts. Exclude palette UI.
Verify uniqueness, current shortcuts, and parity coverage. Exit: shell commands
have one registry. Rollback: registry can remain unused.

**08E — Focus/overlay state.** Entry: 01C and 08B accepted. Scope: one focus
owner, restoration, ordered routing, modal stack, semantic announcements.
Exclude visual overlays. Verify randomized traces and routing table. Exit: UX
owner accepts focus/input semantics. Rollback: legacy focus remains authoritative.

**08F — Legacy projections.** Entry: 08B–08E accepted. Scope: narrow adapters
mapping legacy shell state/actions to candidate semantics and enumerating widget
exceptions. Exclude authoritative cutover. Verify parity traces and zero new
direct effects. Exit: Prompt 09 can audit both projections. Rollback: disable
candidate audit.

### Prompt 09 cards

**09A — Legacy-authoritative audit.** Entry: 08F accepted. Scope: compare
candidate and legacy semantic/effect projections; execute legacy effects only.
Verify all deterministic inventory traces and privacy-safe diagnostics. Exit:
no unexplained divergence. Rollback: disable/delete audit state.

**09B — Shared cutover.** Entry: 09A accepted. Scope: make shared shell-level
state authoritative behind a startup rollback switch; reverse-compare legacy.
Exclude audit removal and widget-internal migration. Verify PTY/parity traces
and immediate rollback. Exit: architecture owner approves authoritative shared
shell model. Rollback: restart with legacy-authoritative switch.

**09C — Stabilization/removal.** Entry: 09B accepted and a predeclared trace
count/duration, owner, thresholds, and triggers. Scope: observe reverse audit,
resolve divergence, then remove temporary machinery. Verify threshold evidence.
Exit: temporary dual evaluation is gone. Rollback: retain audit longer; do not
recreate a UI-v2-specific model.

### Prompt 11 cards

**11A — Read-only Explorer.** Entry: 10 accepted. Scope: model, layout,
navigation, expansion, scroll, selection, open, semantics. Exclude async scans
and mutations. Verify keyboard/pointer final-state equivalence and viewports.
Exit: fake-snapshot Explorer works in v2. Rollback: hide v2 Explorer.

**11B — Async Explorer.** Entry: 11A and 04B accepted. Scope: scan snapshots,
generation/coalescing, preservation, errors/lifecycle. Exclude mutations. Verify
large/error/disappearance/close/shutdown/allocation cases. Exit: real read-only
Explorer is nonblocking. Rollback: disable real v2 Explorer data adapter.

**11C — Explorer mutations.** Entry: 11B and an approved destructive-action
contract. Scope: ordered create/rename/delete with boundaries and recovery.
Exclude styling. Verify symlinks, races, roots, confirmations, stale scans, and
failure. Exit: safety/product owner accepts mutations. Rollback: disable
mutation commands while preserving read-only Explorer.

**11D — Explorer hardening.** Entry: 11C accepted. Scope: PTY, responsive,
property, semantic, performance, and soak evidence. Exclude new features. Exit:
reference-slice gate passes and v1 Explorer freezes. Rollback: shell-level
feature selection returns users to v1 Explorer.

### Prompt 14 cards

**14A — Drawer host.** Entry: 10 accepted. Scope: fake-content drawer layout,
orientation/size/tabs/focus/responsive semantics. Exclude terminal integration.
Verify geometry, tiers, preservation, and no unsolicited opening. Exit: host is
accepted. Rollback: hide drawer host.

**14B — Terminal input contract.** Entry: 14A and 01C accepted. Scope: approve
return chord/prefix, collision matrix, Help/hints, routing. Exclude runtime
routing changes. Verify shell/readline, Neovim Terminal, tmux, SSH, paste, mouse,
and arbitrary controls. Exit: UX/terminal owners approve. Rollback:
documentation-only revert.

**14C — Terminal port.** Entry: 14B and 05D accepted. Scope: host the existing
terminal Neovim session without transfer/recreation. Exclude broad compatibility
qualification. Verify input/redraw/resize/hide/focus/session preservation. Exit:
v2 terminal works behind its slice flag. Rollback: use v1 terminal host.

**14D — Terminal hardening.** Entry: 14C accepted. Scope: PTY, transport,
responsive, modes, shutdown, and compatibility evidence. Exclude new terminal
features. Exit: terminal owners accept the slice. Rollback: keep the v1 host
available until beta gates pass.

### Prompt 17 cards

**17A — Extension Shop.** Entry: 04B, 05D, 16 accepted. Scope: catalog/search
and install/remove using shared overlays/effects. Verify offline, retries,
idempotency, close/shutdown, and compatibility. Exit: slice accepted. Rollback:
select v1 Extension Shop.

**17B — Mason.** Entry: 17A foundation patterns and 16 accepted. Scope: Mason
state/actions only. Verify RPC ownership, long work, partial failure, retry,
and focus. Exit: slice accepted. Rollback: select v1 Mason.

**17C — Lazy.** Entry: 17B foundation patterns and 16 accepted. Scope: Lazy
state/update/clean only. Verify destructive confirmation, logs, failure,
idempotency, and plugin smoke. Exit: slice accepted. Rollback: select v1 Lazy.

### Prompt 20 cards

**20A — Beta readiness.** Entry: 10–19 and 09C accepted. Scope: opt-in,
emergency override, persisted preference, diagnostics, recovery, in-app Help.
Exclude release promotion. Verify startup/rollback/settings/privacy. Exit:
release owner declares a beta candidate. Rollback: default remains v1.

**20B — CI/artifacts.** Entry: 20A accepted. Scope: exact-artifact tests,
resource/flake policy, controlled benchmarks. Exclude manual environment claims.
Verify source/archive/AppImage coverage actually available. Exit: release CI
owner accepts automation. Rollback: beta cannot promote.

**20C — Compatibility evidence.** Entry: 20B accepted. Scope: named CI/manual
runs for the platform matrix. Exclude fabricated emulation. Verify owners,
workflows, dates, artifacts, and gaps. Exit: every required row is current or
promotion is blocked. Rollback: extend beta.

**20D — Beta operation.** Entry: 20A–20C accepted and predeclared cohort/time,
severity, privacy, rollback, and workflow-study protocol. Scope: operational
observation and issue response, not coding. Verify qualifying evidence and
representative users. Exit: release owner closes the observation window.
Rollback: disable opt-in distribution or ship a recovery release.

**20E — Go/no-go.** Entry: 20D complete. Scope: evidence/exception review only.
Verify every default-on gate, exception owner/expiry, and rollback readiness.
Exit: named owners record GO or NO-GO. Rollback: NO-GO keeps v1 default and
opens bounded corrective prompts.

## Definition of UI v2 completion

UI v2 is complete when Vide has one shared controller/effect/settings/editor
architecture, one default native shell, no blocking work in interactive paths,
bounded RPC and background scheduling, predictable focus and recovery,
responsive and accessible composition, verified supported-terminal behavior,
and no remaining UI v1 implementation except deliberately retained migration
compatibility.
