# Prompt 04A task-runner design record

Status: Draft for review. This record starts Prompt 04A; it does not approve
the design or open the Prompt 04B implementation gate.

## Constraints and selected architecture

Vide remains a single-reactor application. The reactor thread owns `App`, both
`RpcClient` values, both `UiState` values, the renderer, widgets, models, and
their arenas. A fixed pool executes only independently owned blocking jobs.
Workers cannot retain pointers into reactor-owned state, call Neovim, render,
or mutate a widget or model.

The project pins Zig 0.16.0 in `build.zig.zon`. The pinned standard library's
`std.Io.Threaded` implementation describes itself as thread-safe, but 04B will
not share the application's `std.Io` value across Vide's worker threads. Each
worker will initialize and deinitialize its own supported `std.Io.Threaded`
backend and use the resulting `std.Io` only on that worker. This keeps backend
lifetime and cancellation state isolated and avoids making every future
backend choice part of the runner contract. Direct POSIX primitives are used
only for the runner's queues and notifier where their ownership is explicit.

## Pool size and bounded storage

At initialization, derive the worker count as `clamp(cpu_count - 1, 1, 4)`;
if CPU discovery fails, use one. The count is fixed until shutdown. This leaves
one logical CPU for the reactor and places a conservative ceiling on child
process and filesystem concurrency.

Storage is allocated during runner initialization and never grows:

| Resource | Capacity | Rule |
| --- | ---: | --- |
| high-priority command queue | 16 | explicit user mutations and latency-sensitive reads |
| normal command queue | 48 | refreshes, scans, diagnostics, and background reads |
| completion queue | 64 | one slot per admitted command across both command queues |
| active child registry | worker count | at most one child owned by each worker |

Admission reserves a completion slot before publishing a command. Therefore a
worker never waits for completion capacity. The reservation is released only
after the reactor consumes the result or the worker deinitializes a result
during shutdown. Queue operations use a mutex and condition variable; payload
execution occurs without either lock held.

Workers prefer the high-priority queue, but after four consecutive high
commands they take one normal command when available. FIFO order is stable
within a priority. A queue-full response is synchronous and owned by the
caller; no accepted task is silently overwritten.

## Operation policy

Each operation kind declares one of these policies in its tagged-union case:

- `refresh_latest`: normal priority, latest-wins for the same owner and kind.
  A queued predecessor is replaced and deinitialized; a running predecessor
  may finish but its generation makes the result stale.
- `read_once`: normal priority by default, rejects with `RunnerBusy` when full.
  Callers may retry after a later reactor cycle.
- `interactive_read`: high priority and rejects with an actionable busy error.
- `mutation`: high priority, never coalesced or dropped, and carries a unique
  operation ID so a caller can distinguish rejection from accepted execution.

04B introduces the policy machinery and fake operations only. 04C assigns Git
refresh to `refresh_latest`. Later migration prompts must document the policy,
capacity impact, and user-visible rejection behavior of every new operation.

## Identity, generations, and cancellation

`OwnerId` and `Generation` are nonzero `u64` values. Owner IDs are allocated
monotonically by the reactor and are never pointers, indexes, widget tags, or
reused IDs. Generation is scoped to an owner and increments when newer work
invalidates older work. Owner or generation exhaustion fails closed: no new
work is admitted for that owner, and the UI reports that the operation cannot
start. Closing an owner removes it from the reactor registry, making every
later completion stale.

Every task carries operation kind, owner ID, generation, and an independently
owned payload. Every mutation also carries a monotonic operation ID. Canceling
queued work removes and deinitializes it. Canceling running refresh/read work
marks its result stale. The runner does not admit an operation that can enter
an arbitrarily blocking in-process syscall: every operation kind must either
use APIs designed for a cancellation latency of at most 1.5 seconds, or be
`terminable` and perform the potentially blocking work in a child process. This
rule applies equally to reads and mutations, but is a design bound rather than
a promise that the kernel can always interrupt I/O.

Workers register a spawned child's PID/handle in their own active-child slot
before waiting. For a terminable task, cancellation sends graceful termination,
waits up to 500 ms, then force-terminates it; the worker subsequently waits to
reap the child before exiting. Mutation requests carry
their operation ID through the backend boundary. If shutdown begins after a
mutation was accepted, Vide records its outcome as unknown until its bounded
call returns or its terminable child is reaped; it never reports such a mutation
as canceled. A later reconciliation read uses the operation ID to resolve an
unknown outcome without blindly repeating the mutation.

Each active-child slot is protected by the runner mutex and carries the worker
index, task operation ID, and a slot generation alongside the PID/handle. The
worker is the only thread that spawns, signals, waits for, reaps, or clears its
child; the reactor never signals a PID directly. Shutdown sets that slot's
atomic cancellation request while holding the mutex and wakes the owning
worker. Child adapters use bounded wait/poll intervals of at most 50 ms rather
than an indefinite wait, so the worker rechecks cancellation after publishing
the handle and between waits. It performs the graceful/forced sequence, reaps
the exact child, then clears the slot under the mutex before another child can
reuse it. Generation and operation-ID checks make a late cancellation request
harmless after PID reuse. The reactor may observe slot state for diagnostics
but waits for the worker's cleared-slot condition rather than racing `wait` or
termination.

## Payload, result, and allocator ownership

Commands and completions are tagged unions. Each union case provides one
`deinit(allocator)` path. The runner allocator owns copied strings, argument
vectors, byte buffers, and immutable snapshots. Admission transfers a payload
to the runner exactly once; rejection leaves it with the caller. A worker
transfers a result exactly once into its reserved completion slot. If result
construction or publication fails, that worker deinitializes all partial state.

On notification, the reactor drains completions. It validates operation kind,
owner, generation, and operation ID before moving an accepted immutable result
into model-owned storage. Stale, duplicate, unknown-owner, and rejected results
are deinitialized exactly once without touching UI state. Completion handling
is bounded per cycle; if more remain, the reactor schedules another immediate
cycle so rendering and input are not starved.

## Portable completion notification

The notifier implements the Prompt 03B contract as a nonblocking pipe on Linux
and macOS. The read end is registered once as `.task_completion` in the reactor;
workers share only the write end. Publishing the first transition from zero to
one queued completions writes one byte. `EAGAIN` means a wakeup is already
pending and is success. Under the queue lock, the reactor drains completions,
drains the pipe to `EAGAIN`, then rechecks the queue before sleeping. If work
arrived across that boundary it processes it or rearms the byte, preventing a
lost wakeup. Bytes carry no payload.

Shutdown leaves completion admission and both notifier descriptors open while
workers can publish. After every worker has exited and been joined, the reactor
closes completion admission, drains and deinitializes all remaining
completions, drains the pipe, unregisters the reactor token, and finally closes
both descriptors. Publication is nonblocking and transfers ownership to the
completion queue before notification; notification failure leaves no result in
the worker. Because descriptors remain open until after join, `EPIPE` is an
invariant violation rather than a normal shutdown ownership path.

## Shutdown and partial initialization

Normal shutdown targets two seconds under ordinary OS scheduling and the
operation-admission contract above. It is not an absolute deadline: an
uninterruptible kernel operation can delay child reaping or worker exit. Zig
0.16 has no timed thread join, and the runner neither detaches workers nor frees
resources they may still access:

1. Stop command admission and mark queued commands canceled.
2. Broadcast to all command waiters and request cancellation of terminable
   active children.
3. Keep draining completions while workers exit; workers never wait to publish.
4. Reap terminable children and join workers. If the two-second target expires,
   record a shutdown-delay diagnostic and continue waiting; ownership remains
   intact until all joins complete.
5. Close completion admission, drain/deinitialize all queue entries, unregister
   the notifier, and release the runner allocation.

Initialization records each completed stage. Failure unwinds only initialized
workers, synchronization primitives, descriptors, queues, and backend values in
reverse order. A partially spawned pool follows the same wake/join procedure.
No runner resource may outlive the reactor that owns it.
04B tests each operation adapter's declared cancellation bound with fake clocks
and blocking points; later prompts may not add an adapter without the same
evidence.

## Deterministic 04B verification contract

04B must provide a fake scheduler and allocator-failure coverage without real
sleep timing. Tests must cover worker-count boundaries, both queue limits,
priority fairness, FIFO order, latest-wins replacement, mutation rejection,
owner close, stale and duplicate completion, generation/operation-ID
exhaustion, notifier coalescing and drain/rearm races, descriptor reuse,
publication during shutdown, child escalation through a fake child controller,
partial initialization, and exactly-once deinitialization for every path.

ThreadSanitizer, where supported by the pinned toolchain and CI runner, is
additional evidence rather than a substitute for deterministic tests. 04B must
also rerun the Prompt 03B unit and PTY suites and show that an idle runner adds
no wakeups.

## Rollout and rollback

04A changes documentation only. Its history starts at `7252773`, with later
edits in mixed reactor-review commits `098ed75`, `a9c83a2`, and `5b9cd91`;
rollback therefore removes the 04A document and its status entry as a
content-level change rather than reverting those mixed commits wholesale. 04B
will add the dormant runner and notifier without migrating production widgets.
04C is the first runtime consumer and must remain separately revertible to
synchronous Git refresh. No task-runner state is persisted across process
restarts.

## Review decisions required before acceptance

- Approve the worker-count formula and the 16/48/64 capacities.
- Approve priority fairness and per-operation admission behavior.
- Approve per-worker `std.Io.Threaded` ownership for Zig 0.16.0.
- Approve the pipe notifier and its close/rearm ordering on Linux and macOS.
- Approve monotonic identity exhaustion, cancellation semantics, the 500 ms
  child grace period, and the non-absolute two-second shutdown target.
- Approve ownership transfer, exactly-once destruction, test obligations, and
  the 04B/04C rollback boundary.
