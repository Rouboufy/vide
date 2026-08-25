# Prompt 03B interactive reactor contract

Vide's interactive runtime remains single-threaded. The reactor owns the poll
registration table and readiness snapshots. The thread running it exclusively
owns `App`, the editor and terminal `RpcClient` transports, both `UiState`
values, the renderer, and all live model and widget arenas. Callbacks run to
completion on that thread and may not retain pointers into a readiness snapshot.

Each cycle has one order: readiness collection, transport progress, normalized
event dispatch, state update, composition, flush, then (when requested)
shutdown. Work discovered during a later phase is handled in the next cycle.
The first frame is an explicit bootstrap before this repeating sequence. The
production loop uses `PhaseTracker` to reject an out-of-order transition, and
readiness is dispatched in stable registration order through `ReadySet.dispatch`.
Shutdown is entered through that same checked transition from whichever runtime
phase requests termination; it is terminal and cannot be entered twice or
followed by another runtime phase.
Registration tokens contain a slot generation. A removed token therefore
cannot remove or modify a later source even when the operating system reuses
the same descriptor number. Generations are 64-bit and registration fails
closed rather than wrapping after exhaustion. An exhausted free slot is skipped
while another reusable slot exists. Readiness order follows registration
chronology even when removal and slot reuse change the physical slot indexes.

The initial sources are terminal input, the SIGWINCH notification pipe, and
read readiness for both Neovim transports. Source kinds are also reserved for
both Neovim write interests and task completion, so those features integrate
through this seam rather than adding another poll loop.

## Portable task-completion notifier requirements

The future notifier must expose a pollable read descriptor, use nonblocking
drain and notification operations, coalesce notifications safely, wake a
blocked reactor without lost wakeups, and have explicit close/unregister
ordering. It must work on Linux and macOS, survive descriptor-number reuse via
reactor tokens, and carry no task payload through the descriptor; completed
results stay in a bounded queue owned by the reactor. An implementation may
use different OS primitives, but callers depend only on this contract.
