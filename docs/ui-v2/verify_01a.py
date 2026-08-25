#!/usr/bin/env python3
"""Structural checks for the Prompt 01A documentation contract."""

from pathlib import Path
import re

ROOT = Path(__file__).resolve().parent
contract = (ROOT / "ux-contract-01a.md").read_text()
script = (ROOT / "evaluation-script-01a.md").read_text()
checklist = (ROOT / "ux-test-checklist-01a.md").read_text()
dogfood = (ROOT / "ux-dogfood-2026-08-25.md").read_text()

inventory = contract.split("### Per-workflow equivalence record", 1)[0]
for prefix in ("B", "N", "S"):
    ids = re.findall(rf"^\| {prefix}(\d+)(?: E)? \|", inventory, re.MULTILINE)
    assert ids == [str(i) for i in range(1, 11)], (prefix, ids)

equivalence = contract.split("### Per-workflow equivalence record", 1)[1]
for prefix in ("B", "N", "S"):
    ids = re.findall(rf"^\| {prefix}(\d+) \|", equivalence, re.MULTILINE)
    assert ids == [str(i) for i in range(1, 11)], ("equivalence", prefix, ids)

for viewport in ("120x40", "80x24", "60x20", "40x12"):
    assert viewport in script, viewport

for alternative in (
    "labeled collapsible navigation",
    "mnemonic text rail",
    "command-first/no-permanent-rail",
):
    assert alternative in script, alternative

for topic in (
    "Ordered input-resolution contract",
    "Restoration and fallback",
    "Keyboard and pointer task equivalence",
    "Responsive invariants and boundaries",
    "Non-dismissible modal",
    "Nested confirmation",
):
    assert topic.lower() in contract.lower(), topic

for exact_input in ("`F1`", "`F6`/`Shift-F6`", "`Ctrl-Shift-P`", "`Ctrl-\\`", "`e` invokes"):
    assert exact_input in contract, exact_input
assert "A top modal shadows their normal execution" in " ".join(contract.split())
assert "Resolve or cancel this dialog first" in contract

for surface in (
    "Activity/navigation", "Explorer", "Search", "Git sidebar", "AI sidebar",
    "Extensions sidebar", "Integrated terminal", "Settings", "Help",
    "Command palette", "Mason and Lazy", "Detailed Git", "Bug report",
    "Neovim/plugin/Telescope floats",
):
    assert re.search(rf"^\| {re.escape(surface)} \|", contract, re.MULTILINE), surface

tasks = re.findall(r"^\| T(\d+) [KP] \|", script, re.MULTILINE)
assert tasks == [str(i) for i in range(1, 23)], tasks

assert "Restore this snapshot before every task" in script
for pair in ((1, 2), (4, 5), (6, 7), (8, 15), (21, 22)):
    for task in pair:
        assert f"| T{task} " in script, pair

coverage = script.split("### Essential-workflow coverage", 1)[1]
for workflow in ("B1", "B2", "B3", "B4", "B5", "B9", "B10",
                 "N1", "N2", "N3", "N4", "N7", "N10",
                 "S1", "S2", "S3", "S4", "S8", "S10"):
    assert re.search(rf"\b{workflow}\b", coverage), workflow

for boundary in ("39/40/41", "59/60/61", "78/79/80", "111/112/113",
                 "11/12/13", "14/15/16", "19/20/21", "26/27/28"):
    assert boundary in script, boundary

assert "For T1 through T22" in checklist
for task in (1, 2, 4, 5, 6, 7, 8, 15, 21, 22):
    assert f"T{task}" in checklist, task
for section in (
    "Focus ownership and traversal",
    "Editor and terminal input pass-through",
    "Modal, overlay, and restoration behavior",
    "Keyboard and pointer equivalence",
    "Discoverability and semantic states",
    "Test every responsive boundary",
    "Complete the decision gate",
    "Session result template",
):
    assert section in checklist, section
for finding in range(1, 11):
    assert f"D{finding:02}" in dogfood, finding
for task in (3, 9, 12, 13, 14, 18):
    assert re.search(rf"^\| T{task} \|", dogfood, re.MULTILINE), task
assert "provisional internal dogfood" in dogfood.lower()
print("Prompt 01A documentation checks passed")
