# Prompt 05C checked RPC inventory

Status: implementation review pending. Audited 2026-08-26.

## Classification

- `src/main.zig:startup through initial-file open` — bounded startup-sync calls
  before async transport enablement: UI attach, initialization commands, theme,
  terminal metadata, and initial file open.
- Every `RpcClient.notify` site — interactive notification; encoded into an
  owned bounded envelope after startup selection.
- Every `RpcClient.call` site reachable after reactor construction —
  interactive async compatibility adapter. After `enableAsyncTransport`,
  `call` admits an async request and returns immediately; it never waits for a
  response. Command effects preserve FIFO order. Result-sensitive Settings,
  Mason, Lazy, Output, and Debug refreshes use registered completion handlers;
  the dormant Explorer status helper is not called by production code.
- `RpcClient.send`, `waitResponse`, and the legacy reader — startup-sync only
  after async transport selection; unreachable from interactive calls.

There are no unclassified direct RPC call sites. Worker threads have no RPC
access. The editor and terminal each retain one client and one independent
transport; no duplicate or compatibility client exists.

## Checked exceptions and follow-up

- Startup calls end before `enableAsyncTransport()` and remain synchronously
  bounded by the existing startup contract.
- Native Zen handoff and reload combine save/session creation into one async
  request. Their completion handlers publish a deferred exit only after a
  successful response; RPC errors keep the current session alive. Prompt 05D
  owns timeout hardening. No reactor iteration waits for them.
