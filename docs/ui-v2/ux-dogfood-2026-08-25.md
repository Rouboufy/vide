# UI v2 UX dogfood report — 2026-08-25

Status: provisional internal dogfood; not external user validation and not an
01C product decision.

## Session metadata

- Date/time supplied: 2026-08-25, 10:33
- Participant: project owner; anonymous participant ID not supplied
- Input emphasis: keyboard-related testing, with pointer counterparts where
  named
- Build/prototype version: not supplied; results appear to exercise the current
  UI rather than all three Prompt 01B alternatives
- Terminal, local/SSH status, viewport per task, keyboard layout, familiarity,
  reset-fixture confirmation, evaluator, and presentation order: not recorded

Because the three Prompt 01B alternatives and required deterministic fixtures
were not identified, this report is defect/discoverability evidence only. It
cannot compare alternatives or satisfy the participant gate.

## Raw participant report

The following preserves the supplied outcomes with spelling normalized only
for readability:

- T1K + T2P:
  1. `Ctrl-S` to save does not function.
  2. No shortcut was found to switch between tabs.
  3. No way to save by clicking was found.
- T3: could not find the prepared problem/diagnostic; the owner also could not
  find it.
- T4: OK.
- T5: cannot open the terminal using only the pointer.
- T6: OK with help; the shortcut menu is hard to find using only the keyboard.
- T7: OK.
- T8: failed; no keyboard route to Settings was found.
- T9: reported as the same failure as T8.
- T10: OK.
- T11: failed; no route was found.
- T12: failed.
- T13: failed.
- T14: failed.
- T15: OK.
- T16: OK.
- T17: OK.
- T18: assignment was not understood.
- T19: completed, but the keyboard shortcut was not found without help.
- T20: failed; Git/Explorer could not be traversed with the keyboard.
- T21: succeeded with the pointer, but no keyboard route was found.
- T22: OK.

## Actionable findings

| ID | Evidence | Classification | Severity | Required follow-up |
| --- | --- | --- | --- | --- |
| D01 | T1: `Ctrl-S` did not save | keyboard behavior or shortcut discoverability | high | confirm expected policy in VideNormal and VideIDE; test actual command receipt and visible shortcut metadata |
| D02 | T1: no keyboard tab-switch route found | discoverability/keyboard reachability | high | expose current next/previous-tab commands in Help/palette and contextual tab hint; verify outcome and focus |
| D03 | T2: no clickable Save found | pointer equivalence/discoverability | high | provide a visible File/Save control where the chosen shell policy requires it and bind it to the same command ID |
| D04 | T5: terminal could not be opened by pointer | pointer equivalence | high | add or expose a labeled Terminal control using `terminal.toggle`; compare with T4 keyboard outcome |
| D05 | T6: shortcut/help menu difficult to find | keyboard discoverability | medium | make Help/palette entry persistent or contextually hinted and test without evaluator help |
| D06 | T8: Settings keyboard entry not found | keyboard reachability/discoverability | high | expose `settings.open` through a documented shortcut, mnemonic, or searchable palette reachable from the current focus |
| D07 | T11: Zen entry/restoration route not found | mode discoverability | high | expose `mode.zen` in visible mode controls and Help/palette; rerun with Explorer focused and assert restoration |
| D08 | T19: split completed only with help finding keyboard shortcut | keyboard discoverability | medium | show current split commands/shortcuts in Help/palette and relevant context |
| D09 | T20: Git/Explorer keyboard traversal failed | keyboard reachability | blocking | implement/prove stable region traversal plus list/tree navigation; no essential region may be a keyboard trap |
| D10 | T21: deletion reachable by pointer but not keyboard | pointer-only destructive action | blocking | add keyboard/context-command route to the identical confirmation and verify no mutation on cancel |

“High” means an essential or parity path failed but may have an alternate route
that was not discovered. “Blocking” means the observed behavior directly
violates the no-pointer-only/no-keyboard-trap gate and must be resolved before
UX acceptance.

## Invalid or inconclusive task executions

These outcomes must not be counted as product failures until rerun with their
required setup:

| Task | Why this run is inconclusive | Correct rerun setup |
| --- | --- | --- |
| T3 | No known diagnostic fixture was available or identifiable | inject one visible deterministic diagnostic in `src/tui/events.zig`, then test Problems discovery and jump |
| T9 | Reported as “same as T8,” but T9 tests emergency Help/quit at 40x12, not Settings | set exactly 40x12 and ask the T9 wording verbatim; record Help, quit discovery, clipping, and restored editor focus |
| T12 | The script requires a supplied nested confirmation prototype | prepare Help plus a nested dismissible/non-dismissible confirmation with observable focus stack |
| T13 | The script requires a supplied disabled command and resolvable prerequisite | seed a named disabled command, visible reason, deterministic prerequisite, and retry result |
| T14 | The script requires focus, selection, error, unread, loading, and disabled states to be simultaneously represented | seed and label all six states at each viewport before asking the participant to identify them |
| T18 | “Supplied Telescope picker” and intended actions were not explained by the fixture | pre-open/provide a deterministic Telescope picker; retain the verbatim task but ensure the evaluator knows expected move/cancel/reopen/accept states |

T11 is retained as a genuine discoverability finding because its task wording
is sufficient once Explorer and the mode commands are present. If VideZen was
not available in the tested build, reclassify it as inconclusive on rerun.

## Successful evidence to retain

- T4 supports the keyboard terminal open/input/return path in the tested build;
  exact Escape and prefix subcases were not individually recorded.
- T6/T7 support Git workflow completion, although T6 required help.
- T10 supports the tested resize workflow; exact boundary sizes, focus at each
  step, and preserved model state were not recorded.
- T15 supports the pointer Settings cancellation/discard path.
- T16 and T17 support file-search and project-text-search discovery.
- T19 supports the split outcome, with a keyboard discoverability defect.
- T22 supports pointer destructive-action cancellation.

These are provisional observations, not passes for every acceptance assertion.

## Rerun checklist

- [ ] Record build/prototype version, terminal, input method, viewport, and
  participant profile.
- [ ] Test all three 01B alternatives; if they do not exist, label the run as
  current-UI dogfood rather than UI v2 validation.
- [ ] Restore the deterministic fixture before every task.
- [ ] Rerun T1/T2 separately from identical state and record final focus,
  buffers, command IDs, and whether Save was absent or merely undiscovered.
- [ ] Rerun T3, T9, T12, T13, T14, and T18 with the fixtures above.
- [ ] For every “OK,” record the route used, help requested, final focus, and
  preserved state rather than only the outcome.
- [ ] Rerun D01–D10 after prototype changes and link each finding to a result.
- [ ] Keep the decision provisional until the external participant minimum is
  met and all essential workflows are reachable.

