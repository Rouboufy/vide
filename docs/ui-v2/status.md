# UI v2 program status

This record follows `docs/ui-v2-implementation-playbook.md`. “Accepted” is
reserved for an integrated change with recorded evidence and named-owner
approval. Unknown approvals are not inferred from a commit.

| Prompt | Status / approval role | Prerequisite commits | Implementation commit or PR | Evidence paths and exact commands | Decision date / exceptions / follow-up | Persisted-state impact and rollback |
| --- | --- | --- | --- | --- | --- | --- |
| 00 Program contract | Approved for architecture/RPC, UX, settings/migration, renderer/performance, and release by Rouboufy; integration pending | none; audited baseline `226a8420b203f9acc70c638f424f3b8543356fd7` | uncommitted documentation change on `main` | `docs/ui-v2/program-contract.md`; `git diff --check`; `for f in src/tui/widgets/*.zig; do b=$(basename "$f"); rg -q "$b" docs/ui-v2/program-contract.md \|\| echo "MISSING $b"; done`; `rg -n '\.call\(' src/main.zig src/tui src/nvim/helpers.zig`; `rg -n '\bspawn\s*\(|\.wait\s*\(' src/main.zig src/tui src/nvim/helpers.zig`; `rg -n 'std\.Io\.Dir|std\.fs\.|posix\.open|openat|deleteFile|deleteTree|createFile|writeFile|readFile|openFile|renameAbsolute|access\(' src/main.zig src/tui src/nvim/helpers.zig`; `rg -n 'https?://|curl|wget|fetch|network' src/main.zig src/tui src/nvim`; no runtime tests required because behavior is unchanged | Approved 2026-08-25 by Rouboufy; no approved exceptions; follow-up: owners must resolve all **Unknown** entries before the consuming prompt's exit gate | no persisted-state impact; rollback by reverting only `docs/ui-v2/program-contract.md` and this row |

## Runtime prompt deployment metadata

Prompt 00 changes no runtime module, introduces no feature flag or
compatibility seam, and has no partial rollout. Expected files are
`docs/ui-v2/program-contract.md` and `docs/ui-v2/status.md`; all runtime modules
are out of scope. Disable/rollback is documentation-only and does not revert
unrelated work.
