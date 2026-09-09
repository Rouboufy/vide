# Prompt 01C pre-study expert inspection and readiness record

Status: **pre-study expert inspection only; Prompt 01C pending**. This is not participant validation,
a completed fixed-script study, or an approved product
decision. It may guide engineering exploration and study preparation only.

## Non-decision engineering hypothesis

The non-decision engineering hypothesis is **Alternative A, labeled
collapsible navigation**. A uniquely spells out Settings, Terminal, Problems,
and the other primary regions when the effective tier is comfortable, while
retaining the same compact, constrained, and emergency behavior as B. That may
address current-UI primary-region discovery failures. It does not uniquely
improve Zen discovery or shared F6 semantics. This hypothesis must not be used
as a selected design or disclosed as a preference during participant sessions.

The comparison set is Alternative A, Alternative B, and Alternative C.

Alternative B saves 15 columns whenever width permits A's labeled rail and the
effective tier is comfortable; a restrictive height can make the effective
tier compact and collapse A despite the same width. B makes `S`, `!`, `G`,
`T`, `C`, and `?` depend on learned meaning. Alternative C's `[Commands]` is
clear and economical but
turns primary-region discovery into an extra menu/search step and removes the
navigation focus stop. That is a material risk for IDE beginners and users who
do not yet know the product vocabulary. These are comparative risks, not
rejection reasons; no alternative is rejected before the study.

## Evaluation identity and limits

- Evaluation date: 2026-08-25.
- Evaluator type: internal expert inspection by an implementation agent; no
  participant identity is asserted.
- Eventual decision owner: Rouboufy, after the requested external UX rerun.
- Fixed inputs: T1-T22 verbatim, the deterministic reset fixture, alternatives
  A/B/C, and 120x40, 80x24, 60x20, and 40x12.
- Evidence: exact primary, state, and boundary grids; transition specification;
  01A/01B contracts, generators, harnesses, and verifiers; and separate
  current-UI dogfood evidence.
- Not collected: participants, completion status, time, help requests,
  wrong-region events, confidence statements, or quotes. None are fabricated.
- Static frames can prove that a route/state is represented and geometry is
  deterministic. They cannot prove noticeability, event delivery, or pointer
  dispatch to the documented command ID.

## Raw structured internal observations

Legend: `R` means a deterministic visible or searchable route exists; `S`
means semantics/restoration are specified; `I` means actual interaction is
unverified. These are traceability observations, not completion results.

| Task | Shared evidence and expected outcome | A observation | B observation | C observation | Confidence / open risk |
| --- | --- | --- | --- | --- | --- |
| T1 K | Explorer/`file.open`, `file.save`, buffer return; editor final | R/S; full Explorer label at 120 | R/S; `E` mnemonic | R/S; `[Commands]` then registry | medium / editing and key dispatch I |
| T2 P | Explorer row and Actions `Save Ctrl-S` map to T1 outcome | R/S | R/S | R/S | medium / Actions entry and hit testing I |
| T3 K | `!1 Problems`, details, location, editor return | R/S; full label at 120, `!1` at 80 | R/S; `!1` | R/S; header indicator plus registry | medium / `!1` meaning may be missed |
| T4 K | Terminal route, literal Escape, `Ctrl-\\ e`, retained session | R/S; labeled or `T` | R/S; `T` | R/S; registry plus footer Terminal control | medium / pass-through I |
| T5 P | Footer `[Open]` and `[Return to editor]` | R/S | R/S | R/S | medium / hit testing I |
| T6 K | Source Control, Stage, message, Cancel, editor return | R/S; label lost at 60 but registry available | R/S; rail suspended at 60 | R/S; Commands remains visible | medium / constrained entry must be learned |
| T7 P | Git controls expose Stage, Commit, Cancel, Return | R/S | R/S | R/S | medium / pointer dispatch I |
| T8 K | `settings.open`; dirty close; Cancel then Discard | R/S | R/S | R/S | medium / modal routing I |
| T9 K | Emergency editor, Help, quit discovery, editor restore | R/S; shared emergency body | R/S; same | R/S; same | high for static visibility; interaction I |
| T10 K | Selection/session retention and valid fallback across resize | S; four primary tiers | S; same below comfortable | S; same constrained/emergency body | low / assets do not execute retained state |
| T11 K | Explorer owner saved; Zen editor-only; restore Explorer | R/S | R/S | R/S via command registry | medium / C entry least contextual; transition I |
| T12 K | Help parent, dismissible child, blocked child, no leakage | R/S; five states | R/S | R/S | medium / actual Escape routing I |
| T13 K | disabled reason, prerequisite, same-command retry | R/S | R/S | R/S | medium / prerequisite is facilitator-supplied |
| T14 K | textual focus/selection/error/unread/loading/disabled markers | R at all sizes | R at all sizes | R at all sizes | medium / constrained abbreviations risk confusion |
| T15 P | Settings pointer route has same dirty policy | R/S | R/S | R/S | medium / pointer equivalence I |
| T16 K | `search.files`, fixed result, open and buffer return | R/S; label/mnemonic | R/S; `S` | R/S; Commands | medium / dispatch and buffer state I |
| T17 K | `search.text`, retained query/results and return | R/S | R/S | R/S | medium / retention not executable |
| T18 K | Neovim Telescope receives Escape/Enter; editor restored | R/S | R/S | R/S | low / pass-through cannot be proven statically |
| T19 K | vertical split; Neovim owns grids/focus/close | R/S | R/S | R/S | low / RPC and Neovim behavior not executable |
| T20 K | F6: A/B Editor→Navigation→Auxiliary; C Editor→Auxiliary | R/S; three stops | R/S; three stops | R/S; two stops by design | medium / routing and no-leakage I |
| T21 K | Explorer delete, same warning, Cancel default, restore | R/S | R/S | R/S | medium / mutation prevention and dispatch I |
| T22 P | same confirmation/default/focus/tree as T21 | R/S | R/S | R/S | medium / hit testing and command-ID equality I |

All tasks use the same wording, fixture, viewport, and information across
A/B/C. No task was scored complete, incomplete, helped, timed, or assigned a
participant confidence value.

## Focus, input, and recovery inspection

- Every state has exactly one textual focus owner. C intentionally has no
  Navigation focus state; its F6 ring is Editor/Auxiliary.
- Push/pop restoration is specified for palette, terminal, dirty Settings,
  nested confirmation, Zen, Telescope, splits, traversal, and deletion.
- Terminal states say `Escape -> terminal` and `Ctrl-\\ e -> editor`.
  Telescope is Neovim-owned. These match 01A on paper.
- Non-dismissible T12 states require an action and state that repeated Escape
  stops without leaking. Static evidence cannot verify event delivery.
- Keyboard and pointer storyboards name equivalent outcomes and destructive
  defaults. Static frames do not emit command logs, so runtime command-ID
  equality remains an implementation-test obligation.

## Responsive and boundary evidence

The deck covers 39/40/41, 59/60/61, 78/79/80, and 111/112/113 columns at 27
rows, plus 11/12/13, 14/15/16, 19/20/21, and 26/27/28 rows at 120 columns for
all alternatives. Exact-cell verification passes. Repeated generation is
deterministic, so there is no generator-level tier oscillation. Emergency
keeps editor, resize recovery, Help, and quit. Constrained keeps editor plus
one auxiliary; C retains `[Commands]`.

The ten-crossing requirement is only **partially evidenced**: static files
cannot carry a live focus owner, selection, terminal process, overlay stack,
or hit-test layout across resize. No claim is made that ten live crossings
preserve state, match hit testing, or force a correct redraw.

## Defect and risk register

| ID | Scope | Severity | Evidence | Required resolution/evidence |
| --- | --- | --- | --- | --- |
| P01 | all | blocking for product approval | static frames; no event router/command log | external interactive rerun and later routing tests |
| P02 | all | empirical discoverability risk | `[Actions]` is visibly named, and its state contains pointer Save | observe whether participants infer that visible `[Actions]` contains Save without coaching |
| P03 | A/B | medium | compact Settings is `[]` in A and `C` in B | test interpretation; full text must remain available without hover |
| P04 | B | high comparative | mnemonic-only rail persists when 120x40 has room | beginner/SSH evidence must show no discoverability regression |
| P05 | C | high comparative | regions require Commands; no Navigation traversal stop | test Problems, Settings, Git, Terminal, and Zen without help |
| P06 | all | medium | constrained grid truncates inline status words | T14 must confirm state identification at 60x20 without explanation |
| P07 | all | high | resize retention is described, not executable | ten live crossings with owner/state records |
| P08 | all | high | pass-through and pointer equivalence are specifications | automated routing/shared-layout hit-test evidence later |

Current-UI D01-D10 remain separate, non-comparative evidence. The deck designs
routes for them, but a static route is not proof of an implemented fix.

## Qualitative tradeoffs and confidence

- A hypothesis: best comfortable-width primary-region learning surface; highest width cost; smaller
  tiers inherit mnemonic and registry dependence. Comparative confidence:
  medium.
- B risk: stable compact identity and 15 more editor columns where A is labeled;
  strongest dependence on
  abbreviations with no demonstrated user benefit. Confidence: medium.
- C risk: maximum editor width and clearest universal Commands affordance; less
  ambient awareness and one fewer traversal landmark. Confidence: medium.
- Overall product-decision confidence: none until real discovery, recovery, and focus
  behavior is exercised.

## Exact external rerun instructions

1. Use an interactive facilitator or behaviorally equivalent build containing
   all three alternatives; record its exact commit. Static files alone are
   insufficient for completion scoring.
2. Recruit at least five consented participants: two IDE-oriented beginners,
   two experienced Neovim users, and one SSH/keyboard-only user.
3. Record every participant metadata field in the fixed script.
4. Use the repeating Latin square `ABC, BCA, CAB, ACB, CBA, BAC`; do not name
   the engineering hypothesis.
5. Before every task restore the deterministic fixture. Use identical labels,
   shortcuts, data, capabilities, glyph mode, and simulation labels for A/B/C.
6. Run T1-T22 verbatim at specified viewports. K is keyboard-only; P starts
   from an equivalent reset. Do not reveal controls unless asked; record hints.
7. Record every observation field from the fixed script, including command ID,
   prior/final focus, state, wrong-region events, help, recovery, qualitative
   answer, confidence, and diagnostic elapsed time.
8. Ask only the three fixed follow-ups. Do not silently modify a prototype;
   version and rerun every affected comparison.
9. Cross every listed width/height boundary ten times with Editor, Auxiliary,
   Terminal, and Modal focus. Record clipping, oscillation, owner, selection,
   terminal output, overlay stack, hit test, and forced redraw.
10. Retest P02-P08 and D01-D10. A listed route counts as discovered only if the
    participant finds it without a hint.
11. Approve only if no essential workflow is unreachable, nobody is trapped,
    editor return is identifiable, destructive paths are equivalent, and
    beginner/keyboard discoverability does not regress. Supersede this report
    with raw evidence, defects, confidence, UX-owner decision, rejection
    reasons, exceptions, and follow-ups.

## Verification performed

```text
python3 docs/ui-v2/verify_01a.py
python3 docs/ui-v2/generate_01b.py
python3 docs/ui-v2/verify_01b.py
python3 docs/ui-v2/verify_01c.py
python3 -m py_compile docs/ui-v2/verify_01c.py
git diff --check
```

No runtime code or persisted state changes. The fixed study has not run, so
Prompt 01C remains pending. Rollback is documentation-only.
