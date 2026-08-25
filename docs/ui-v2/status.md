# UI v2 program status

This record follows `docs/ui-v2-implementation-playbook.md`. “Accepted” is
reserved for an integrated change with recorded evidence and named-owner
approval. Unknown approvals are not inferred from a commit.

| Prompt | Status / approval role | Prerequisite commits | Implementation commit or PR | Evidence paths and exact commands | Decision date / exceptions / follow-up | Persisted-state impact and rollback |
| --- | --- | --- | --- | --- | --- | --- |
| 00 Program contract | Accepted; architecture/RPC, UX, settings/migration, renderer/performance, and release approved by Rouboufy | none; audited baseline `226a8420b203f9acc70c638f424f3b8543356fd7` | `f0af0c657773582d00ecdc04ae92aafc299d85a2` on `dev` | `docs/ui-v2/program-contract.md`; `git diff --check`; `for f in src/tui/widgets/*.zig; do b=$(basename "$f"); rg -q "$b" docs/ui-v2/program-contract.md \|\| echo "MISSING $b"; done`; `rg -n '\.call\(' src/main.zig src/tui src/nvim/helpers.zig`; `rg -n '\bspawn\s*\(|\.wait\s*\(' src/main.zig src/tui src/nvim/helpers.zig`; `rg -n 'std\.Io\.Dir|std\.fs\.|posix\.open|openat|deleteFile|deleteTree|createFile|writeFile|readFile|openFile|renameAbsolute|access\(' src/main.zig src/tui src/nvim/helpers.zig`; `rg -n 'https?://|curl|wget|fetch|network' src/main.zig src/tui src/nvim`; no runtime tests required because behavior is unchanged | Accepted 2026-08-25 by Rouboufy; no approved exceptions; follow-up: owners must resolve all **Unknown** entries before the consuming prompt's exit gate | no persisted-state impact; rollback by reverting `f0af0c657773582d00ecdc04ae92aafc299d85a2` and the status-record commit without reverting unrelated later work |
| 01A Workflow and input contract | Accepted; UX approved by Rouboufy; independent UX architecture audit passed | Prompt 00 implementation `f0af0c657773582d00ecdc04ae92aafc299d85a2`, acceptance record `4246ab1` | `137d8a8` on `dev`; acceptance recorded by the commit containing this row | `docs/ui-v2/ux-contract-01a.md`; `docs/ui-v2/evaluation-script-01a.md`; `docs/ui-v2/ux-test-checklist-01a.md`; `docs/ui-v2/ux-dogfood-2026-08-25.md` (non-gating current-UI dogfood); `docs/ui-v2/verify_01a.py`; `git diff --check`; `python3 docs/ui-v2/verify_01a.py`; independent agent audit confirmed 01A/01B/01C phase boundaries and no remaining content blocker; runtime tests not applicable because no runtime behavior changes | Accepted 2026-08-25 by Rouboufy; no approved exceptions; D01–D10 remain non-gating current-UI observations for later comparison | no persisted-state impact; rollback by reverting `137d8a8` and the acceptance-record commit without reverting unrelated later work; no feature flag, compatibility seam, or partial rollout |
| 01B Low-fidelity prototypes | Accepted for provisional 01C; UX/accessibility and terminal-layout expert reviews passed under Rouboufy's delegated instruction | Prompt 01A implementation `137d8a8`, acceptance record `bc7866d` | `c27f690` on `dev`; acceptance record `c51a783`; facilitator-sequence correction `24d1ed2` | `docs/ui-v2/prototype-contract-01b.md`; `docs/ui-v2/transitions-01b.md`; `docs/ui-v2/prototypes-01b/*.txt`; `docs/ui-v2/prototypes-01b/states/*.txt`; `docs/ui-v2/prototypes-01b/boundaries/*.txt`; `docs/ui-v2/generate_01b.py`; `docs/ui-v2/prototype_harness_01b.py`; `docs/ui-v2/verify_01b.py`; `python3 docs/ui-v2/generate_01b.py`; `python3 docs/ui-v2/verify_01b.py`; `python3 docs/ui-v2/verify_01a.py`; `python3 -m py_compile docs/ui-v2/generate_01b.py docs/ui-v2/prototype_harness_01b.py docs/ui-v2/verify_01b.py`; `git diff --check`; two independent expert reviews cleared UX/accessibility, focus/input, state transitions, exact geometry, boundaries, and harness validation; runtime tests not applicable because no runtime behavior changes | Accepted 2026-08-25 for provisional internal evaluation; no design selected, no approved exceptions, and no participant/external validation claimed; follow-up: Prompt 01C evaluates all alternatives with the fixed script | no persisted-state impact; rollback by reverting `c27f690`, `c51a783`, and the 01B portions of `24d1ed2` without reverting accepted 01A or unrelated work; no feature flag, compatibility seam, or partial rollout |
| 01C Validation and product decision | Pending; pre-study expert inspection/readiness complete; UX approval and participant validation pending | Prompt 01B implementation `c27f690`, acceptance record `c51a783`, facilitator correction `24d1ed2` | readiness evidence `24d1ed2` on `dev`; no validation implementation or PR because the study is not executed | `docs/ui-v2/evaluation-01c-provisional.md` (pre-study inspection, not validation); `docs/ui-v2/facilitator-runbook-01c.md`; `docs/ui-v2/verify_01c.py`; `python3 docs/ui-v2/verify_01a.py`; `python3 docs/ui-v2/generate_01b.py`; `python3 docs/ui-v2/verify_01b.py`; `python3 docs/ui-v2/verify_01c.py`; `python3 -m py_compile docs/ui-v2/verify_01c.py`; `git diff --check`; no participant measures or runtime-test claims | Readiness inspected 2026-08-25; A labeled collapsible navigation is a non-decision engineering hypothesis only; eventual decision owner Rouboufy; no approved exceptions; fixed T1-T22 sessions and live ten-crossing evidence remain required | no persisted-state impact; rollback by reverting `24d1ed2` and this status-record commit without reverting accepted 01A/01B or unrelated work; no feature flag, compatibility seam, or partial rollout |
| 02 Settings durability | Accepted; settings/migration approved by Rouboufy | Prompt 00 `f0af0c657773582d00ecdc04ae92aafc299d85a2` | current on `dev` | `src/tui/widgets/settings.zig`; `zig fmt --check src/tui/widgets/settings.zig`; `git diff --check`; `zig build test --summary all` (38/38 tests passing); `python3 docs/ui-v2/verify_01a.py && python3 docs/ui-v2/verify_01b.py && python3 docs/ui-v2/verify_01c.py` | Accepted 2026-08-25 by Rouboufy; no approved exceptions; future UI v2 preferences can be added safely | Persisted settings upgraded to versioned schema v1, bounded at 64 KiB with atomic replacement and .bak backup; rollback safe by reverting without destroying configuration |
| 03 Performance observability | Accepted; renderer/performance approved by Rouboufy | Prompt 00 implementation `f0af0c657773582d00ecdc04ae92aafc299d85a2` | `ec18b43ea04094ebf35a420695bacf1b5971b09f` on `dev` | `src/metrics.zig`; `scripts/profile_vide.py`; `tests/performance_profile.py`; `docs/performance-profile.json`; `zig build test --summary all` (43/43 tests passing); `python3 tests/performance_profile.py`; `git diff --check`; `zig fmt --check src/metrics.zig` | Accepted 2026-08-25 by Rouboufy; no approved exceptions; `pty_integration.py` passed on the stashed pre-Prompt-03 tree, so no PTY exception was required; subsequent prompts may gate on reproducible measured regressions | No persisted-state impact; `metrics.global` is process-local and zero-cost unless `VIDE_DIAGNOSTICS=1` or `--diagnostics`; `diagnostics.json` written to `XDG_DATA_HOME/vide/`; rollback by reverting implementation commit without reverting unrelated work |
| 03B Interactive reactor seam | Accepted; reactor seam approved by Rouboufy | Prompt 03 implementation `ec18b43ea04094ebf35a420695bacf1b5971b09f`, acceptance record `3026f86` | `7098b0a` on `dev`, with phase-boundary corrections `098ed75` and `a9c83a2`; review record `e9d900f`; acceptance recorded by `079b856` | `src/reactor.zig`; `src/main.zig`; `src/root.zig`; `docs/ui-v2/reactor-03b.md`; `zig fmt --check src/reactor.zig src/main.zig src/root.zig`; `zig build test --summary all` (51/51 tests passing); `zig build && python3 tests/pty_integration.py`; `git diff --check` | Accepted 2026-08-26 by Rouboufy; no approved exceptions; PTY coverage passed for normal, IDE, and Zen modes, including input, resize, dual-Neovim progress, terminal restoration, startup failure, and orderly Ctrl-Q shutdown | No persisted-state impact; runtime remains single-threaded and scheduling behavior is unchanged; rollback by reverting `7098b0a`, `098ed75`, `a9c83a2`, `e9d900f`, `079b856`, and this status-record commit without reverting Prompt 03 or unrelated work |
| 04A Task-runner design record | Draft; review and approval pending | Prompts 00, 03, and 03B accepted | Draft committed by the commit containing this row; no implementation or PR | `docs/ui-v2/task-runner-04a.md`; pinned Zig 0.16.0 and local standard-library concurrency contract inspected; `git diff --check` | Started 2026-08-26; worker sizing, capacities, admission policy, notifier, ownership, cancellation, deadlines, and rollback remain subject to approval | Documentation only; 04B gate remains closed; rollback by reverting the draft commit without runtime or persisted-state impact |

## Runtime prompt deployment metadata

Prompt 00 changes no runtime module, introduces no feature flag or
compatibility seam, and has no partial rollout. Expected files are
`docs/ui-v2/program-contract.md` and `docs/ui-v2/status.md`; all runtime modules
are out of scope. Disable/rollback is documentation-only and does not revert
unrelated work.

Prompt 01A changes no runtime module, introduces no feature flag or
compatibility seam, and has no partial rollout. Expected files are
`docs/ui-v2/ux-contract-01a.md`, `docs/ui-v2/evaluation-script-01a.md`,
`docs/ui-v2/ux-test-checklist-01a.md`, the dated dogfood evidence,
`docs/ui-v2/verify_01a.py`, and the 01A row in this record. Runtime code, cell
prototypes, style, participant validation, and product selection are out of
scope. Disable/rollback is documentation-only and does not revert unrelated
work.

Prompt 01B changes no runtime module, introduces no feature flag or
compatibility seam, and has no partial rollout. Expected files are
`docs/ui-v2/prototype-contract-01b.md`, `docs/ui-v2/prototypes-01b/*.txt`,
the state and boundary decks, `docs/ui-v2/transitions-01b.md`, `docs/ui-v2/generate_01b.py`,
`docs/ui-v2/prototype_harness_01b.py`, `docs/ui-v2/verify_01b.py`, and the 01B row in
this record. Runtime implementation, styling, participant evaluation, and
product selection are out of scope. Disable/rollback is documentation-only
and does not revert unrelated work.

Prompt 01C remains pending. Its pre-study readiness work changes no runtime
module, introduces no feature flag or compatibility seam, and has no partial
rollout. Readiness files are `docs/ui-v2/evaluation-01c-provisional.md`,
`docs/ui-v2/facilitator-runbook-01c.md`, `docs/ui-v2/verify_01c.py`, and the 01C
row in this record. Participant validation and the product decision have not
occurred. Disable/rollback is documentation-only and does not revert unrelated
work.

Prompt 02 touches `src/tui/widgets/settings.zig` and changes settings persistence
at runtime to use schema version 1 with bounded dynamic loading (up to 64 KiB),
POSIX atomic file replacement, parent directory sync, and .bak backup.
Unversioned v0 files are migrated in-memory without losing configuration. Rollback
leaves valid settings files intact and backward-compatible.

Prompt 03 adds `src/metrics.zig` with a process-local `Metrics` singleton
(opt-in via `--diagnostics` CLI flag or `VIDE_DIAGNOSTICS` env var), instruments
`src/main.zig`, `src/nvim/rpc.zig`, `src/nvim/helpers.zig`,
`src/tui/renderer.zig`, `src/tui/terminal.zig`, and
`src/tui/widgets/git_utils.zig` with `ScopedTimer` calls that are no-ops when
disabled, extends `scripts/profile_vide.py` with deterministic multi-iteration
binary comparison and nine benchmark scenarios, and extends
`tests/performance_profile.py` with schema v2 validation. Introduces no runtime
feature flag, compatibility seam, or partial rollout beyond the diagnostics
opt-in. Disable/rollback does not revert unrelated work.

Prompt 03B adds `src/reactor.zig`, replaces the main loop's ad hoc poll array
with a single-threaded reactor registration table, and asserts the documented
cycle phases. It reserves source kinds for future Neovim write readiness and
task completion but starts no workers and changes no persisted state. The
reactor continues to own both Neovim transports and all UI state on the main
thread. Disable/rollback reverts `7098b0a`, `098ed75`, `a9c83a2`, `e9d900f`,
the `079b856` acceptance record, and this status-record commit; it does not
require reverting Prompt 03 or unrelated work.
