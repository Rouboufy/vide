# Vide UI v2 checklist

Use this checklist alongside `docs/ui-v2-implementation-playbook.md`.

> **👤 UX INPUT** means this step needs hands-on user experience evaluation,
> user testing, or a product decision. An implementation agent can prepare the
> work, but should not approve the result on your behalf.

## Contracts and preparation

- [X] 00 — Establish the UI v2 program contract
- [ ] **01A — Workflow and input contract — 👤 UX INPUT**
- [ ] **01B — Prototypes — 👤 UX INPUT**
- [ ] **01C — Validation and product decision — 👤 UX INPUT**
- [X] 02 — Make settings versioned, durable, and reversible
- [X] 03 — Add performance observability and deterministic fixtures
- [X] 03B — Introduce the interactive reactor seam

## Responsiveness foundation

- [X] 04A — Task-runner design record
- [X] 04B — Deterministic task runner
- [X] 04C — Git refresh migration
- [X] 05A — RPC framing and decoder
- [X] 05B — Asynchronous RPC transport
- [X] 05C — RPC call-site migration
- [ ] 05D — Dual-session and shutdown hardening
- [ ] 06 — Separate invalidation and Neovim sizing
- [ ] 07A — Row-run ANSI encoder
- [ ] 07B — Retained coarse-region composition
- [ ] 07C — Optional fine-grained damage optimization

## Shared application architecture

- [ ] 08A — Types and ownership
- [ ] 08B — Pure reducer and controller sequencing
- [ ] 08C — Effect executor
- [ ] 08D — Command registry
- [ ] **08E — Focus and overlay state machine — 👤 UX INPUT**
- [ ] 08F — Legacy projection adapters
- [ ] 09A — Legacy-authoritative audit
- [ ] 09B — Shared-model cutover
- [ ] 09C — Stabilization and audit removal

## UI v2 shell and vertical slices

- [ ] **10 — Implement the editor-only UI v2 shell — 👤 UX INPUT**
- [ ] 11A — Read-only Explorer
- [ ] 11B — Asynchronous Explorer refresh
- [ ] 11C — Explorer mutations
- [ ] **11D — Explorer responsive and PTY hardening — 👤 UX INPUT**
- [ ] 12 — Port Search
- [ ] 13 — Port Git
- [ ] 14A — Unified drawer host
- [ ] **14B — Terminal input contract — 👤 UX INPUT**
- [ ] 14C — Terminal port
- [ ] 14D — Terminal PTY and responsive hardening
- [ ] 15 — Port Problems, Output, and Debug
- [ ] **16 — Build shared overlays and port Settings — 👤 UX INPUT**
- [ ] 17A — Port Extension Shop
- [ ] 17B — Port Mason
- [ ] 17C — Port Lazy
- [ ] 18 — Port AI and bug reporting
- [ ] **19 — Apply the visual and accessibility system — 👤 UX INPUT**

## Beta, release, and cleanup

- [ ] 20A — Beta-ready implementation
- [ ] 20B — CI and artifact qualification
- [ ] 20C — Compatibility evidence
- [ ] **20D — Beta operation — 👤 UX INPUT**
- [ ] **20E — Go/no-go review — 👤 UX INPUT**
- [ ] **21 — Make UI v2 the default — 👤 UX INPUT**
- [ ] **22 — Remove UI v1 and migration adapters — 👤 UX INPUT**
