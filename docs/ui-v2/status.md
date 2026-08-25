# UI v2 program status

This record follows `docs/ui-v2-implementation-playbook.md`. “Accepted” is
reserved for an integrated change with recorded evidence and named-owner
approval. Unknown approvals are not inferred from a commit.

| Prompt | Status / approval role | Prerequisite commits | Implementation commit or PR | Evidence paths and exact commands | Decision date / exceptions / follow-up | Persisted-state impact and rollback |
| --- | --- | --- | --- | --- | --- | --- |
| 00 Program contract | Accepted; architecture/RPC, UX, settings/migration, renderer/performance, and release approved by Rouboufy | none; audited baseline `226a8420b203f9acc70c638f424f3b8543356fd7` | `f0af0c657773582d00ecdc04ae92aafc299d85a2` on `dev` | `docs/ui-v2/program-contract.md`; `git diff --check`; `for f in src/tui/widgets/*.zig; do b=$(basename "$f"); rg -q "$b" docs/ui-v2/program-contract.md \|\| echo "MISSING $b"; done`; `rg -n '\.call\(' src/main.zig src/tui src/nvim/helpers.zig`; `rg -n '\bspawn\s*\(|\.wait\s*\(' src/main.zig src/tui src/nvim/helpers.zig`; `rg -n 'std\.Io\.Dir|std\.fs\.|posix\.open|openat|deleteFile|deleteTree|createFile|writeFile|readFile|openFile|renameAbsolute|access\(' src/main.zig src/tui src/nvim/helpers.zig`; `rg -n 'https?://|curl|wget|fetch|network' src/main.zig src/tui src/nvim`; no runtime tests required because behavior is unchanged | Accepted 2026-08-25 by Rouboufy; no approved exceptions; follow-up: owners must resolve all **Unknown** entries before the consuming prompt's exit gate | no persisted-state impact; rollback by reverting `f0af0c657773582d00ecdc04ae92aafc299d85a2` and the status-record commit without reverting unrelated later work |
| 01A Workflow and input contract | UX-approved by Rouboufy; integration pending | Prompt 00 implementation `f0af0c657773582d00ecdc04ae92aafc299d85a2`, acceptance record `4246ab1` | uncommitted working tree | `docs/ui-v2/ux-contract-01a.md`; `docs/ui-v2/evaluation-script-01a.md`; `docs/ui-v2/ux-test-checklist-01a.md`; `docs/ui-v2/ux-dogfood-2026-08-25.md` (non-gating current-UI dogfood); `docs/ui-v2/verify_01a.py`; `git diff --check`; `python3 docs/ui-v2/verify_01a.py`; runtime tests not applicable because no runtime behavior changes | UX-approved 2026-08-25 by Rouboufy; no approved exceptions; follow-up: integrate this documentation, then begin 01B; D01–D10 remain non-gating current-UI observations for later comparison | no persisted-state impact; rollback by reverting the 01A implementation and acceptance-record commits without reverting unrelated later work; no feature flag, compatibility seam, or partial rollout |

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
