#!/usr/bin/env python3
"""Static completeness checks for Prompt 01C pre-study readiness evidence."""

from pathlib import Path

ROOT = Path(__file__).parent
text = (ROOT / "evaluation-01c-provisional.md").read_text()

for token in (
    "pre-study expert inspection", "Prompt 01C pending", "not participant validation",
    "Alternative A", "Alternative B", "Alternative C",
    "non-decision engineering hypothesis",
    "Exact external rerun instructions", "39/40/41", "111/112/113",
    "11/12/13", "26/27/28", "P01", "P08", "D01-D10", "Rouboufy",
):
    assert token in text, f"01C report missing {token!r}"

for task in range(1, 23):
    rows = [line for line in text.splitlines() if line.startswith(f"| T{task} ")]
    assert len(rows) == 1, f"expected one observation row for T{task}"

for claim in ("participant passed", "participants passed", "zero help requests", "completion time was"):
    assert claim not in text.lower(), f"unsupported participant claim: {claim}"

status = (ROOT / "status.md").read_text()
assert "01C Validation and product decision" in status
assert "evaluation-01c-provisional.md" in status
assert "participant validation pending" in status
assert "non-decision engineering hypothesis" in status

contract = (ROOT / "prototype-contract-01b.md").read_text()
assert "accepted for the provisional study" in contract
assert "Prompt 01C remains pending" in contract

runbook = (ROOT / "facilitator-runbook-01c.md").read_text()
for token in (
    "Wizard-of-Oz", "ABC, BCA, CAB, ACB, CBA, BAC", "T1 K 120x40",
    "T22 P 80x24", "not executable in low-fi", "prototype_harness_01b.py",
    "participant does", "facilitator", "Reset", "Prompt 01C remains pending",
):
    assert token.lower() in runbook.lower(), f"01C runbook missing {token!r}"

for exact in (
    "| T11 K 120x40 | all A/B/C: `focus-auxiliary` → `zen` → `focus-auxiliary`",
    "| T13 K 80x24 | start `default`; only after the participant discovers disabled Commit",
    "| T21 K 80x24 | all A/B/C start `focus-auxiliary`; delete route → `delete-confirmation`; Cancel → `focus-auxiliary`",
    "| T22 P 80x24 | all A/B/C start `focus-auxiliary`; participant points to Actions/context/delete; `delete-confirmation`; Cancel → `focus-auxiliary`",
):
    assert exact in runbook, f"01C runbook sequence mismatch: {exact!r}"

transitions = (ROOT / "transitions-01b.md").read_text()
for exact in (
    "| T11 | `focus-auxiliary` -- `mode.zen` -- `zen` -- Leave Zen -- `focus-auxiliary`",
    "| T13 | `default` -- participant discovers disabled Commit",
    "| T21/22 | `focus-auxiliary` -- delete key/click / Explorer delete -- `delete-confirmation` -- Cancel -- `focus-auxiliary`",
):
    assert exact in transitions, f"01B transition mismatch: {exact!r}"

print("Prompt 01C pre-study readiness checks passed")
