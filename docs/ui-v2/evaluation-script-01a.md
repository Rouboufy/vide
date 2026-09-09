# UI v2 fixed workflow evaluation script (Prompt 01A)

Status: fixed input to Prompts 01B and 01C. Changing a task, seed state,
viewport, instruction, or metric invalidates cross-alternative comparison and
requires a documented UX-owner revision before the next session.

## Alternatives and presentation order

Evaluate all three cell-level alternatives: labeled collapsible navigation,
mnemonic text rail, and command-first/no-permanent-rail. Each must be shown at
120x40, 80x24, 60x20, and 40x12. Use a balanced Latin-square presentation
order across participants; do not identify a preferred design. Use the six
permutations in repeating order `ABC, BCA, CAB, ACB, CBA, BAC`, assigning each
new participant the least-used next sequence; with five participants report
the unused sequence and treat order balance as limited. The evaluator
may explain the task goal but not the control location or shortcut unless the
participant explicitly asks for help, which is recorded.

Each alternative uses identical data, current command labels/shortcuts,
terminal capabilities, font/glyph mode, viewport, and reset snapshot. Do not
rank by completion time alone.

## Participant record and minimum

Record anonymous participant ID, audience (IDE-oriented, Neovim-oriented, or
SSH-focused), self-rated familiarity with Vide/Neovim/terminal IDEs, terminal
and version, local or SSH, keyboard layout, pointer availability/use, viewport,
accessibility needs, alternative order, evaluator, decision owner, date, and
consent to retain notes. The validation minimum is two IDE-oriented users, two
Neovim-oriented users, and one SSH-focused user.

If unavailable, run the same script as internal dogfood and label every result
`provisional/internal`; it may find defects and provisional preferences but is
not user validation and cannot satisfy the default-on release gate.

## Deterministic reset fixture

Start each alternative from the same fixture: VideNormal; editor focused on
`src/main.zig` at the same cursor; clean undo state; Explorer collapsed at the
repository root; one known error diagnostic in `src/tui/events.zig`; Git has
one unstaged fixture file; terminal session not started; no overlay; default
panel size; Help and palette available; fixed sample search results; and no
network-dependent operation. Restore this snapshot before every task. Paired
keyboard/pointer tasks therefore start from byte-for-byte equivalent model
state; task-specific setup below is applied only after restoration. Use
simulated deterministic effects for Git and diagnostics if the prototype
cannot execute them, and label simulation identically.

## Scripted tasks

Run these tasks verbatim. K means keyboard-only; P means pointer path where a
pointer is available. For SSH-focused participants all tasks are K.

| Task | Viewport | Instruction | Success and expected final state |
| --- | --- | --- | --- |
| T1 K | 120x40 | “Open `src/tui/events.zig`, add a harmless comment, save it, and return to `src/main.zig`.” | open/edit/save/return; editor focused; both buffers retained |
| T2 P | 120x40 | Repeat T1 using visible pointer controls where practical. | same command outcomes, confirmation policy, final focus, state |
| T3 K | 80x24 | “Find the known problem, open its details, go to its location, then return to editing.” | diagnostic found; editor focused at location; details recoverable |
| T4 K | 80x24 | “Open the terminal, type `printf ok`, use Escape as terminal input, return to the editor, then reopen the terminal.” | literal Escape not shell-consumed; editor return identifiable; session retained |
| T5 P | 80x24 | Repeat the open-terminal/return/reopen outcome using pointer controls where practical. | equivalent outcome and terminal state |
| T6 K | 60x20 | “Inspect source control, stage the fixture file, write `fixture` as the commit message, cancel, and return to the editor.” | no commit; message/cancel policy correct; editor focused; stage state defined |
| T7 P | 60x20 | Repeat T6 using pointer controls where practical. | identical confirmation/cancellation, stage state, final focus |
| T8 K | 60x20 | “Open Settings, change a value without saving, try to close it, cancel the close, then discard and return.” | unsaved confirmation; first cancel preserves edit; discard restores invoker |
| T9 K | 40x12 | “Keep editing, find Help, identify how to quit, then return without quitting.” | editor usable; recovery text unclipped; Help and quit discoverable; editor restored |
| T10 K | 120x40→40x12→60x20→120x40 | “Open Explorer, select a row, open terminal, return to editor, resize as directed, then restore the original size.” | no trap/overlap; focus valid at every step; selection and terminal retained |
| T11 K | 120x40 | “Focus the Explorer, enter Zen, continue editing, then leave Zen.” | editor state retained; Explorer focus and selection restored |
| T12 K | 80x24 | “Open Help, then a nested confirmation supplied by the prototype; press Escape repeatedly and recover.” | one overlay level per authorized dismissal; non-dismissible state explains action; no input leakage |
| T13 K | 80x24 | “Find a disabled command, learn why it is disabled, resolve the supplied prerequisite, and retry it.” | reason discoverable; refusal loses no state; retry uses same command |
| T14 K | each viewport | “Without activating anything, name the focused region, selected item, any error, unread count, loading item, and disabled control.” | states identified without relying on color |
| T15 P | 60x20 | Repeat T8 using pointer controls where practical. | identical dirty confirmation, cancellation/discard, and final focus |
| T16 K | 80x24 | “Search for `events.zig`, open it, then return to `src/main.zig`.” | file-search path discoverable; editor final focus; both buffers retained |
| T17 K | 80x24 | “Search the project for `FocusTarget`, open a result, then return.” | text-search path discoverable; query/results retained; editor final focus |
| T18 K | 120x40 | “Open the supplied Telescope picker, move once, cancel with Escape, reopen it, and accept the first result.” | all plugin input reaches Neovim; cancel and accept work; editor focus |
| T19 K | 120x40 | “Create a vertical editor split, move to the other split, then close the new split.” | split commands discoverable; correct grid focused; original buffer retained |
| T20 K | 120x40 | “Move forward through every visible region, then backward to the editor, naming each region.” | documented order and reverse order; no trap or input leakage; editor focus |
| T21 K | 80x24 | “From Explorer, request deletion of `fixture-delete.txt`, read the warning, then cancel.” | no mutation; confirmation/default recorded; Explorer focus and tree retained |
| T22 P | 80x24 | Repeat T21 using pointer controls. | identical warning/default/cancel outcome, final focus, and tree state |

### Essential-workflow coverage

| Essential workflows | Script evidence |
| --- | --- |
| B1, N1, S1 open/edit/save | T1/T2 |
| B2 file search | T16 |
| B3 project search | T17 |
| B4 diagnostic inspection | T3 |
| B5, N4, S3 terminal Escape/return | T4/T5 |
| B9, N7 Zen restoration | T11 |
| B10 Help/recovery | T9, T13 |
| N2 Neovim/plugin overlay pass-through | T18 |
| N3 editor splits | T19 |
| N10, S8 responsive recovery | T9, T10, boundary checks |
| S2 region traversal | T20 |
| S4 nested modal recovery | T12 |
| S10 disabled reason/retry | T13 |

After each task ask only: “What did you expect to happen?”, “What, if
anything, was hard to find?”, and “How would you return to the editor?” Record
answers verbatim within consent limits.

## Observation record

For every participant × alternative × task × viewport record:

- completion: complete, complete-with-help, incomplete, or unreachable;
- cancellation/error recovery outcome and preserved state;
- unrecoverable error count and description;
- wrong-region focus events (input went to or visibly targeted another region);
- help requests, with evaluator hint and point in task;
- discoverability failures (participant could not identify an available path);
- focus/selection/error/unread/loading/disabled-state identification;
- keyboard or pointer command path and resulting command ID;
- final focus versus expected focus;
- qualitative feedback and participant confidence (low/medium/high);
- elapsed time as diagnostic context only.

Log defects separately with alternative, viewport, exact prior focus, overlay
stack, input, expected/actual owner, and whether state was lost. Do not silently
fix a prototype between alternatives for one participant; version it and rerun
affected comparisons.

## Boundary and evaluator checks

Before participant use, exercise 39/40/41, 59/60/61, 78/79/80, and
111/112/113 columns at a stable 27 rows; and 11/12/13, 14/15/16, 19/20/21,
and 26/27/28 rows at a stable 120 columns. Repeat each boundary crossing ten
times with editor, auxiliary, terminal, and modal focus. Record overlap,
clipping, oscillation, invalid focus, state loss, hit-test mismatch, and forced
redraw result. Larger slice-declared minima add equivalent below/at/above cases.

The evaluator also checks that every T1–T22 action is visible or searchable,
every pointer action reports the same command ID as its keyboard path, every
destructive action presents the same confirmation/default, and every
shell-consumed Escape matches the routing table and test case.

## Decision gate and report

Prompt 01C may approve a design only when no essential workflow is unreachable,
no participant is trapped without visible recovery, focus and editor return
are identifiable, and there is no material discoverability regression for
beginner or keyboard-only workflows. Report participant coverage, raw records,
defects, qualitative themes, confidence, decision owner, reasons for the chosen
design, reasons each alternative was rejected, exceptions, and follow-ups.
Insufficient external participation must remain provisional.
