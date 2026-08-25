# Prompt 01C low-fidelity Wizard-of-Oz facilitator runbook

Status: ready for moderated prototype discoverability sessions. This runbook
uses the accepted-for-study, non-interactive 01B cell deck. It does not itself
execute Prompt 01C; Prompt 01C remains pending until the fixed sessions and
decision gate are completed.

## What this study can and cannot show

The study can show whether participants notice labels, understand mnemonics,
find Help/Commands, choose plausible keyboard or pointer routes, understand
focus/recovery text, and compare the three shell concepts. The facilitator
advances deterministic frames after a participant names or attempts an action.

It cannot prove key delivery, terminal/Neovim pass-through, RPC effects,
pointer hit testing, command-ID dispatch, retained live process state, redraw,
or resize-state preservation. Record those as `not executable in low-fi`, not
as passes. A static pointer task means the participant points to or names a
visible control; it is not a click test.

## One-time setup

From the repository root:

```bash
cd /home/roubs/Projects/vide
python3 docs/ui-v2/generate_01b.py
python3 docs/ui-v2/verify_01a.py
python3 docs/ui-v2/verify_01b.py
python3 docs/ui-v2/verify_01c.py
```

Use a terminal able to show 120x40. `tmux` may provide fixed logical geometry:

```bash
tmux new-session -s vide-01c
```

Inside tmux, press `Ctrl-b`, then `:`, enter `set-option window-size manual`,
and use `resize-window -x WIDTH -y HEIGHT`. `stty size` prints rows then
columns. The harness itself always emits the exact requested cell grid, so the
facilitator may also share only that output area.

Render syntax:

```bash
python3 docs/ui-v2/prototype_harness_01b.py ALTERNATIVE STATE WIDTH HEIGHT
```

Alternatives are `a-labeled`, `b-mnemonic`, and `c-command`. Common states are
`default`, `action-menu`, `problems`, `terminal`, `git`, `settings-dirty`,
`nested-confirmation`, `help`, `command-palette`, `zen`, `disabled-reason`,
`file-search`, `text-search`, `telescope`, `splits`, `delete-confirmation`,
`focus-editor`, and `focus-auxiliary`. A/B also have `focus-navigation`.

## Participant and order setup

Recruit at least two IDE-oriented beginners, two experienced Neovim users, and
one SSH/keyboard-only user. Record all metadata and consent fields from
`evaluation-script-01a.md`. Assign the least-used next order in the repeating
sequence `ABC, BCA, CAB, ACB, CBA, BAC`. Never mention the engineering
hypothesis or describe one concept as preferred.

For each alternative, set `ALTERNATIVE` mentally to its harness name. Do not
change labels, task wording, fixture data, or shortcut information between
alternatives. Render a fresh start state before every task.

## Facilitator interaction protocol

| Participant does | Facilitator does |
| --- | --- |
| Interprets the current frame, attempts/names a K route, or points to a P target | Reads fixed wording, records the attempt, and advances only on a storyboard-valid action |
| Explains expectations and recovery in their own words | Records verbatim answers and never supplies product vocabulary unless help is requested |
| Experiences one alternative at a time | Renders deterministic next states and labels every simulated effect |

1. Render the task's start frame at its fixed viewport.
2. Read the T1-T22 instruction verbatim. Do not explain control locations.
3. For K tasks, ask the participant to name/press the route they would use.
   For P tasks, ask them to point to the visible target or name where they
   would click. Do not let pointer use answer a K task.
4. Record the attempted key/control and inferred command ID. If it corresponds
   to the fixed storyboard, render the next frame below. The facilitator is
   simulating the documented effect, not confirming that an event worked.
5. If the route is unavailable in the current frame, allow Help/palette or
   other visible/searchable discovery routes. If the participant asks for
   help, record the request and exact hint before advancing.
6. For edit/effect steps that have no distinct frame, say only the fixed
   simulated outcome, such as “the comment is now saved,” and record
   `facilitator-simulated`. Never add product guidance.
7. After the task, ask only the three fixed follow-ups and record answers
   verbatim within consent limits.
8. Reset by rendering the listed start state again. Do not carry a prior frame
   or invented model state into the next task.

Use this command template for every frame:

```bash
python3 docs/ui-v2/prototype_harness_01b.py a-labeled default 80 24
```

Replace all four arguments according to the table. For B/C substitute
`b-mnemonic`/`c-command`; never show two alternatives simultaneously.

## Per-task frame script

`→` means: advance only after the participant identifies the documented
action. Parenthesized text is a facilitator simulation/observation, not a
frame. Every command shown below uses `ALTERNATIVE` in place of the chosen
harness name.

| Task | Start and facilitator advances |
| --- | --- |
| T1 K 120x40 | `default` → (`file.open`; simulate edit/save) → `default`; record route to previous buffer and Editor final concept |
| T2 P 120x40 | `default` → `action-menu` after participant identifies `[Actions]` → (`file.open`, edit, `[Save Ctrl-S]`) → `default` |
| T3 K 80x24 | `default` → `problems` after `!1`/`problem.open` → (`Open Details`, `Go to location`) → `default` |
| T4 K 80x24 | `default` → `terminal` after Terminal/`terminal.toggle`; participant names literal Escape and `Ctrl-\\ e` → `default` → `terminal` |
| T5 P 80x24 | `default` → `terminal` after visible Terminal `[Open]`; `[Return to editor]` → `default`; `[Open]` → `terminal` |
| T6 K 60x20 | `default` → `git` after `git.focus`; simulate Stage/message; Cancel/Return → `default` |
| T7 P 60x20 | same states as T6; participant points to Stage, commit field, Cancel, and Return |
| T8 K 60x20 | `default` → `settings-dirty` after `settings.open`; Close → `nested-confirmation`; Cancel → `settings-dirty`; Discard → `default` |
| T9 K 40x12 | `default` → `help` after F1; identify `app.quit`; Close/return → `default` |
| T10 K | 120x40 `default` → 120x40 `terminal` → 40x12 `default` → 60x20 `default` → 120x40 `default`; ask what the participant expects retained; mark actual retention not executable |
| T11 K 120x40 | all A/B/C: `focus-auxiliary` → `zen` → `focus-auxiliary`; restore the Explorer/Auxiliary owner and same row selection as simulated |
| T12 K 80x24 | `t12-parent-help` → `t12-dismissible-child` → `t12-restored-parent` → `t12-blocked-child` → `t12-stop` |
| T13 K 80x24 | start `default`; only after the participant discovers disabled Commit through visible `disabled [? why]` or a valid palette route, advance to `disabled-reason`; record the reason; facilitator supplies the resolved prerequisite; retry the same command ID → `default` |
| T14 K each viewport | render `default` at 120x40, 80x24, 60x20, and 40x12 independently; do not explain marker meanings |
| T15 P 60x20 | same frames as T8; participant points to visible controls |
| T16 K 80x24 | `default` → `file-search` after `search.files`; select `events.zig` → `default`; simulate prior-buffer return |
| T17 K 80x24 | `default` → `text-search` after `search.text`; select result → `default`; ask expected retained query/results |
| T18 K 120x40 | `default` → `telescope`; movement/Escape → `default` → `telescope`; Enter → `default`; mark pass-through not executable |
| T19 K 120x40 | `default` → `splits` after split route; simulate move; `Close grid 2` → `default`; mark Neovim grid behavior not executable |
| T20 K 120x40 | A/B: `focus-editor` → `focus-navigation` → `focus-auxiliary` → `focus-editor`, then reverse; C: `focus-editor` → `focus-auxiliary` → `focus-editor`, then reverse |
| T21 K 80x24 | all A/B/C start `focus-auxiliary`; delete route → `delete-confirmation`; Cancel → `focus-auxiliary`, restoring Explorer/Auxiliary row selection and tree |
| T22 P 80x24 | all A/B/C start `focus-auxiliary`; participant points to Actions/context/delete; `delete-confirmation`; Cancel → `focus-auxiliary` with the same row selection/tree |

Example T3 sequence for A:

```bash
python3 docs/ui-v2/prototype_harness_01b.py a-labeled default 80 24
python3 docs/ui-v2/prototype_harness_01b.py a-labeled problems 80 24
python3 docs/ui-v2/prototype_harness_01b.py a-labeled default 80 24
```

Example T12 sequence for C:

```bash
python3 docs/ui-v2/prototype_harness_01b.py c-command t12-parent-help 80 24
python3 docs/ui-v2/prototype_harness_01b.py c-command t12-dismissible-child 80 24
python3 docs/ui-v2/prototype_harness_01b.py c-command t12-restored-parent 80 24
python3 docs/ui-v2/prototype_harness_01b.py c-command t12-blocked-child 80 24
python3 docs/ui-v2/prototype_harness_01b.py c-command t12-stop 80 24
```

## Logging and scoring

Create one record per participant × alternative × task. Copy the observation
fields from `evaluation-script-01a.md`. Add these low-fi fields:

- `prototype_route_found`: yes / with-help / no;
- `frame_sequence_shown`;
- `facilitator_simulations`;
- `not_executable_assertions` (event delivery, hit test, state retention, etc.);
- `participant_interpreted_focus/recovery`: verbatim explanation.

Use `complete` only to mean the participant completed the moderated **concept
route**. Never translate it into runtime completion. Mark interaction claims
`not executable in low-fi`. Record a discoverability failure when the route
exists but is not found without help; record `unrepresented` if the deck lacks
the needed route.

Do not use the current-UI dogfood report as an A/B/C participant record. Link
D01-D10 only as hypotheses to retest.

## Boundary readiness versus live boundary proof

Before sessions, inspect the checked-in below/at/above deck and run
`verify_01b.py`. You may show exact boundary frames using `default` plus the
desired dimensions. Re-rendering ten times checks deterministic generation
only. It does not execute a resize or prove focus/state/redraw/hit-test
preservation. Record the live ten-crossing acceptance item as pending until an
interactive implementation exists.

## Study completion handoff

After the minimum sessions, aggregate raw records without ranking by speed.
Resolve P02-P08 and compare D01-D10. Apply the fixed decision gate. If it
passes, create a superseding non-provisional 01C report with the UX-owner
decision and reasons for selecting/rejecting alternatives. If it does not,
keep 01C pending, version prototype corrections, and rerun affected comparisons.
