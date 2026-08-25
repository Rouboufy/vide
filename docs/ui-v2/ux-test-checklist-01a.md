# UI v2 UX testing checklist

Use this operational checklist with `evaluation-script-01a.md`. The script is
the fixed source of truth; this checklist explains how to run it and judge the
results. Do not mark prototype behavior as production behavior.

## 1. Decide what kind of test you are running

- [ ] **Prototype review:** Prompt 01B has produced all three alternatives.
- [ ] **External validation:** participants include at least two IDE-oriented,
  two Neovim-oriented, and one SSH/keyboard-focused user.
- [ ] **Internal dogfood:** if the participant minimum is unavailable, label
  the entire run `provisional/internal`. Do not treat it as user validation or
  use it to satisfy the default-on release gate.
- [ ] Name one evaluator who gives instructions and takes notes.
- [ ] Name the product/UX decision owner. The evaluator may be different.
- [ ] Choose a session version, such as `01B-prototype-v1`. Never mix results
  from changed prototype versions without identifying the version.

**Pass condition:** the report identifies the test type, evaluator, decision
owner, prototype version, and whether the evidence is provisional.

## 2. Verify the prototypes before inviting participants

- [ ] Alternative A is labeled collapsible navigation.
- [ ] Alternative B is a mnemonic text rail.
- [ ] Alternative C is command-first with no permanent rail.
- [ ] Every alternative exists at exactly 120x40, 80x24, 60x20, and 40x12.
- [ ] Each version uses the same labels, shortcuts, data, terminal capability,
  font/glyph setting, and starting state.
- [ ] Each visible clickable action displays a label or has a text alternative
  available without hover.
- [ ] Help is available with `F1`.
- [ ] Forward/reverse region traversal is available with `F6`/`Shift-F6`.
- [ ] The command palette is available with `Ctrl-Shift-P` when no modal is
  open.
- [ ] Terminal focus visibly explains the `Ctrl-\` prefix and `Ctrl-\`, then
  `e` return sequence.
- [ ] Modal prototypes demonstrate contextual F1 Help and visibly refuse F6,
  Shift-F6, and Ctrl-Shift-P with “Resolve or cancel this dialog first.”
- [ ] The 40x12 version includes unclipped resize/recovery guidance plus
  keyboard access to Help and quit.

**How to test:** inspect every alternative/viewport side by side. Build a list
of every visible action and find its keyboard or command-palette path. If any
clickable action lacks one, stop and fix the prototype before participant use.

**Pass condition:** all 12 prototype combinations exist and expose equivalent
commands and state, even when their geometry differs.

## 3. Prepare the deterministic task fixture

Before **every task**, restore all of the following—not merely before every
participant or alternative:

- [ ] VideNormal is active.
- [ ] The editor owns focus.
- [ ] `src/main.zig` is active at the agreed cursor position.
- [ ] The undo state is clean.
- [ ] Explorer is collapsed at the repository root.
- [ ] `src/tui/events.zig` contains one known fixture diagnostic.
- [ ] Git contains one unstaged fixture file.
- [ ] `fixture-delete.txt` exists for T21/T22.
- [ ] No terminal session has started.
- [ ] No overlay is open.
- [ ] Panel size is the documented default.
- [ ] Help and the command palette are available.
- [ ] Search uses the same fixed results.
- [ ] Network-dependent effects are disabled or identically simulated.

**How to test:** create a reset button, snapshot, or written reset procedure.
After restoring, compare visible state and model-state annotations against a
reference screenshot/state sheet. For paired tests T1/T2, T4/T5, T6/T7,
T8/T15, and T21/T22, confirm both paths start from the identical snapshot.

**Pass condition:** no task inherits a changed buffer, running terminal,
staged file, open overlay, focus owner, or selection from an earlier task.

## 4. Prepare each participant record

- [ ] Assign an anonymous participant ID; do not store unnecessary identity.
- [ ] Record audience: IDE-oriented, Neovim-oriented, or SSH-focused.
- [ ] Record familiarity with Vide, Neovim, terminal IDEs, and SSH.
- [ ] Record terminal name/version and whether the session is local or SSH.
- [ ] Record keyboard layout, pointer availability, actual input method, and
  relevant accessibility needs.
- [ ] Record date, evaluator, viewport, prototype version, and consent for
  retaining notes.
- [ ] Assign presentation order using `ABC, BCA, CAB, ACB, CBA, BAC`, always
  choosing the least-used next sequence.
- [ ] With only five participants, record the unused order and note limited
  order balance.

**Pass condition:** someone reading the result can distinguish participant
experience, environment, order effects, and input method without knowing the
participant's identity.

## 5. Run each task without coaching

For T1 through T22:

- [ ] Restore the fixture before presenting the task.
- [ ] Set the exact viewport named by the script.
- [ ] Read the task instruction verbatim.
- [ ] Do not name a control, location, shortcut, or preferred route.
- [ ] If the participant asks for help, record the request before helping.
- [ ] Give the smallest useful hint and record its exact wording.
- [ ] Record every wrong-region focus event at the moment it happens.
- [ ] Record whether the task was complete, complete-with-help, incomplete, or
  unreachable.
- [ ] Record final focus and compare it with the expected focus.
- [ ] Record what state survived: buffer, cursor, undo, query/results, tree
  selection, staged state, form text, terminal output/session, and overlays.
- [ ] Afterward ask only: “What did you expect to happen?”, “What, if
  anything, was hard to find?”, and “How would you return to the editor?”
- [ ] Record qualitative answers and confidence as low, medium, or high.
- [ ] Treat elapsed time as diagnostic context, never the sole ranking.

## 6. Check the high-risk behaviors explicitly

### Focus ownership and traversal

- [ ] At launch, the editor is visibly the sole keyboard focus owner.
- [ ] T20 visits every visible region once in a stable forward order.
- [ ] Shift-F6 reverses that order and returns to the editor.
- [ ] A click changes focus only to the visible target under the pointer.
- [ ] Hidden, disabled, destroyed, or responsive-tier-excluded surfaces cannot
  retain keyboard focus.
- [ ] If the prior owner becomes invalid, focus moves to the newest valid
  visible history target, then deterministically to the editor.
- [ ] Output arriving in a hidden terminal never steals focus.
- [ ] A failed action retains the initiating focus unless that target vanished.

**Failure evidence:** record prior focus, input, expected target, actual target,
layout tier, overlay stack, and whether typed input reached the wrong region.

### Editor and terminal input pass-through

- [ ] In T18, ordinary navigation and Escape reach Telescope/Neovim unchanged.
- [ ] Plain Escape inside the terminal is terminal input and does not close or
  leave the terminal.
- [ ] `Ctrl-\`, then `e` returns from terminal to editor.
- [ ] `Ctrl-\`, then `t` toggles the terminal.
- [ ] `Ctrl-\`, then `?` exposes the terminal Help topic.
- [ ] `Ctrl-\`, then `Ctrl-\` sends one literal `Ctrl-\` to the terminal.
- [ ] An unknown suffix forwards both the prefix and suffix unchanged, in
  order, to the terminal.
- [ ] Resize/resume preserves an active prefix; destroying the terminal clears
  it; mouse and paste do not become prefix suffixes.
- [ ] Native surfaces consume or ignore unhandled input locally and never send
  it to an editor or terminal hidden behind them.

**Pass condition:** no shell-consumed Escape lacks an explicit routing rule,
and no editor/terminal input is silently lost or interpreted by the shell.

### Modal, overlay, and restoration behavior

- [ ] Opening an overlay records the current valid focus target.
- [ ] Closing it restores that target; if invalid, fallback is deterministic.
- [ ] A click outside a modal follows that modal's stated policy and never
  activates content behind it.
- [ ] Settings with clean state may close; dirty state opens an unsaved-change
  confirmation.
- [ ] Canceling that confirmation preserves the unsaved form exactly.
- [ ] Confirming discard closes Settings and restores the invoker.
- [ ] A nested Escape closes at most one authorized overlay level per press.
- [ ] A non-dismissible or submitting dialog consumes Escape and displays
  `Action required` or its specific reason.
- [ ] Modal F1 displays contextual Help without moving focus.
- [ ] Modal F6, Shift-F6, and Ctrl-Shift-P do not escape the focus trap and
  display `Resolve or cancel this dialog first`.
- [ ] Repeated Escape at the base state is harmless and does not change focus.

### Keyboard and pointer equivalence

Compare the paired tasks from identical reset snapshots:

- [ ] T1/T2: open, edit, save, return; same buffers and editor focus.
- [ ] T4/T5: terminal open/return/reopen; same live session and final state.
- [ ] T6/T7: Git stage/message/cancel; same stage state and final focus.
- [ ] T8/T15: dirty Settings cancel/discard; same confirmation and restoration.
- [ ] T21/T22: destructive delete cancellation; identical warning, default
  button, no mutation, Explorer selection, and final focus.
- [ ] Record the shared command ID for both paths; matching labels alone do not
  prove equivalence.
- [ ] Verify every context-menu command is also accessible through keyboard or
  the command registry.

**Pass condition:** completion, cancellation, error recovery, confirmation,
final focus, and preserved state match. A mouse-owning terminal application's
internal mouse action is the documented exception; entering/leaving the
terminal still requires equivalence.

### Discoverability and semantic states

- [ ] A beginner can find Explorer, Search, Problems, Terminal, Settings,
  Help, and editor return without evaluator instruction.
- [ ] A keyboard-only user can find every essential task through labels,
  contextual hints, Help, shortcuts, or palette search.
- [ ] Primary regions retain persistent labels or mnemonic text when space
  permits.
- [ ] Entering terminal or another specialized focus shows contextual return
  instructions.
- [ ] An icon-only control has a text alternative without hover.
- [ ] In T14, the participant can identify focus without color.
- [ ] Selection and current state are distinguishable without color.
- [ ] Errors include readable text or `!`, a message, and recovery action.
- [ ] Unread state includes a textual count.
- [ ] Loading state includes text/spinner plus a label.
- [ ] Disabled controls expose a reachable textual reason.
- [ ] T13 proves the participant can discover a disabled reason, resolve the
  prerequisite, retry, and retain state after refusal.

## 7. Test every responsive boundary

Use a stable height of 27 rows for width tests:

- [ ] Test 39, 40, and 41 columns.
- [ ] Test 59, 60, and 61 columns.
- [ ] Test 78, 79, and 80 columns.
- [ ] Test 111, 112, and 113 columns.

Use a stable width of 120 columns for height tests:

- [ ] Test 11, 12, and 13 rows.
- [ ] Test 14, 15, and 16 rows.
- [ ] Test 19, 20, and 21 rows.
- [ ] Test 26, 27, and 28 rows.

At every size, and separately with editor, auxiliary, terminal, and modal
focus:

- [ ] Confirm no overlapping controls or clipped recovery text.
- [ ] Confirm paint geometry and pointer hit targets select the same cell.
- [ ] Confirm exactly one valid visible focus owner.
- [ ] Confirm Help and quit remain keyboard-accessible in emergency mode.
- [ ] Confirm editor access and one auxiliary are preserved in constrained
  mode, using the documented full-content swap if simultaneous layout cannot
  fit.
- [ ] Confirm hidden state, selections, forms, terminal sessions, and editor
  state survive every transition.
- [ ] Confirm resize triggers a forced full redraw.
- [ ] Alternate across each boundary ten times and confirm no oscillation.
- [ ] Add below/at/above cases for any slice declaring larger minimum content.

**Pass condition:** no overlap, unreachable control, invalid focus, state loss,
hit-test mismatch, oscillation, or clipped recovery text occurs.

## 8. Record each defect reproducibly

For every defect, record:

- [ ] Participant and prototype version.
- [ ] Alternative and viewport.
- [ ] Task and exact step.
- [ ] Prior focus and overlay stack.
- [ ] Exact input or pointer target.
- [ ] Expected and actual focus owner/outcome.
- [ ] State lost or unexpectedly changed.
- [ ] Whether recovery was visible and successful.
- [ ] Screenshot or cell capture when permitted.
- [ ] Severity: unreachable/trapped, data/state loss, wrong focus/input,
  discoverability, semantic indicator, responsive layout, or cosmetic.

Do not silently repair a prototype during a participant's comparison. Assign a
new version and rerun every affected alternative/task comparison.

## 9. Complete the decision gate

Do not approve a design unless every answer below is yes:

- [ ] No essential workflow is unreachable.
- [ ] No participant becomes trapped without visible recovery.
- [ ] Participants can identify the focused region.
- [ ] Participants can identify how to return to the editor.
- [ ] There is no material beginner discoverability regression.
- [ ] There is no material keyboard-only or SSH workflow regression.
- [ ] Editor and terminal input is not consumed incorrectly by the shell.
- [ ] Keyboard and pointer paths have equivalent outcomes and destructive
  confirmation.
- [ ] Responsive boundary testing has no unresolved blocking defect.
- [ ] Reasons for choosing one design and rejecting both alternatives are
  evidence-based and recorded.
- [ ] Participant coverage, environment, raw records, defects, confidence,
  exceptions, decision owner, and follow-ups are documented.
- [ ] If external participant minimum was not met, the result remains clearly
  provisional and is not used for default-on approval.

## Session result template

Copy this block for each task observation:

```text
Participant:
Audience / familiarity:
Prototype version / alternative / order:
Terminal / local-or-SSH / input method:
Task / viewport:
Starting snapshot verified: yes | no
Completion: complete | complete-with-help | incomplete | unreachable
Keyboard or pointer route:
Command ID(s):
Help requested and hint given:
Wrong-region focus events:
Expected final focus / actual final focus:
Expected preserved state / actual preserved state:
Cancellation or error recovery:
Discoverability failure:
Unrecoverable error:
Elapsed time (context only):
Participant expectations and feedback:
Participant confidence: low | medium | high
Defect IDs:
```

