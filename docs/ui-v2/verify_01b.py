#!/usr/bin/env python3
"""Static verification for Prompt 01B prototype evidence."""

from pathlib import Path
import subprocess
import sys

from generate_01b import valid_state

ROOT = Path(__file__).parent
ASSETS = ROOT / "prototypes-01b"
SIZES = ((120, 40), (80, 24), (60, 20), (40, 12))
ALTS = ("a-labeled", "b-mnemonic", "c-command")
WIDTHS = (39, 40, 41, 59, 60, 61, 78, 79, 80, 111, 112, 113)
HEIGHTS = (11, 12, 13, 14, 15, 16, 19, 20, 21, 26, 27, 28)
STATES = ("default", "action-menu", "problems", "terminal", "git", "settings-dirty", "nested-confirmation", "help", "command-palette", "zen", "disabled-reason", "file-search", "text-search", "telescope", "splits", "delete-confirmation", "focus-editor", "focus-navigation", "focus-auxiliary", "t12-parent-help", "t12-dismissible-child", "t12-restored-parent", "t12-blocked-child", "t12-stop")


def exact(path: Path, width: int, height: int) -> str:
    assert path.is_file(), f"missing {path}"
    lines = path.read_text().splitlines()
    assert len(lines) == height, f"{path}: expected {height} rows, got {len(lines)}"
    for number, line in enumerate(lines, 1):
        assert len(line) == width, f"{path}:{number}: expected {width} cells, got {len(line)}"
    return "\n".join(lines)

for alt in ALTS:
    for width, height in SIZES:
        path = ASSETS / f"{alt}-{width}x{height}.txt"
        text = exact(path, width, height)
        for token in ("FOCUS: Editor", "F1 Help"):
            assert token in text, f"{path}: missing {token}"
        if width == 40 or height == 12:
            for token in ("Emergency", "Resize", "Quit"):
                assert token in text, f"{path}: missing recovery token {token}"
            for token in (">sel", "!error", "unread", "Loading", "disabled"):
                assert token in text, f"{path}: emergency Help omits T14 state {token}"

for alt in ALTS:
    for width in WIDTHS:
        text = exact(ASSETS / "boundaries" / f"{alt}-{width}x27.txt", width, 27)
        expected = "below-emergency" if width < 40 else "emergency" if width < 60 else "constrained" if width < 79 else "compact" if width < 112 else "comfortable"
        marker = "Too small" if expected == "below-emergency" else "Emergency" if expected == "emergency" else expected
        assert marker in text, f"{alt} {width}x27 expected {expected}"
    for height in HEIGHTS:
        text = exact(ASSETS / "boundaries" / f"{alt}-120x{height}.txt", 120, height)
        expected = "below-emergency" if height < 12 else "emergency" if height < 15 else "constrained" if height < 20 else "compact" if height < 27 else "comfortable"
        marker = "Too small" if expected == "below-emergency" else "Emergency" if expected == "emergency" else expected
        assert marker in text, f"{alt} 120x{height} expected {expected}"
    for state in STATES:
        if alt == "c-command" and state == "focus-navigation":
            assert not (ASSETS / "states" / f"{alt}-{state}-80x24.txt").exists(), f"{alt}/{state}: invalid T20 stop generated"
            continue
        state_text = exact(ASSETS / "states" / f"{alt}-{state}-80x24.txt", 80, 24)
        assert state_text.count("[FOCUS:") == 1, f"{alt}/{state}: expected exactly one focus owner"
    for state in ("help", "command-palette"):
        emergency = exact(ASSETS / "states" / f"{alt}-{state}-40x12.txt", 40, 12)
        assert emergency.count("[FOCUS:") == 1
        assert emergency != (ASSETS / f"{alt}-40x12.txt").read_text().rstrip("\n"), f"{alt}: emergency {state} did not render"

state_tokens = {
    "action-menu": ("Save Ctrl-S", "Split Vertical"), "problems": ("Go to location",),
    "terminal": ("Escape -> terminal", "Return to editor"), "git": ("Stage", "Commit"),
    "settings-dirty": ("dirty prompt", "Discard"), "nested-confirmation": ("Choose an action",),
    "help": ("Quit: app.quit", "disabled"), "zen": ("Leave Zen",),
    "command-palette": ("Filter: searchable", "file.open", "file.save", "search.files", "search.text", "terminal.toggle", "git.focus", "split.vertical", "app.quit"),
    "disabled-reason": ("Missing author", "Retry same command"), "file-search": ("events.zig",),
    "text-search": ("FocusTarget",), "telescope": ("Escape cancels in Neovim",),
    "splits": ("Close grid 2",), "delete-confirmation": ("Default: Cancel",),
    "t12-parent-help": ("Open supplied child",), "t12-dismissible-child": ("Escape -> parent Help",),
    "t12-restored-parent": ("focus restored here",), "t12-blocked-child": ("Non-dismissible",),
    "t12-stop": ("no input leakage",),
}
for alt in ALTS:
    for state, tokens in state_tokens.items():
        text = (ASSETS / "states" / f"{alt}-{state}-80x24.txt").read_text()
        for token in tokens:
            assert token in text, f"{alt}/{state} missing {token}"
text_c = (ASSETS / "c-command-120x40.txt").read_text()
assert "[Commands]" in text_c, "C lacks explicit pointer command control"
for alt in ALTS:
    telescope = (ASSETS / "states" / f"{alt}-telescope-80x24.txt").read_text()
    assert "[FOCUS: Editor grid]" in telescope and "Neovim-owned Telescope" in telescope
    assert "FOCUS: Neovim Telescope" not in telescope
    assert "[FOCUS: Editor grid 2]" in (ASSETS / "states" / f"{alt}-splits-80x24.txt").read_text()
    assert "VideZen | [FOCUS: Editor]" in (ASSETS / "states" / f"{alt}-zen-80x24.txt").read_text()
    editor_ring = (ASSETS / "states" / f"{alt}-focus-editor-80x24.txt").read_text()
    auxiliary_ring = (ASSETS / "states" / f"{alt}-focus-auxiliary-80x24.txt").read_text()
    if alt == "c-command":
        assert "Traversal 1/2" in editor_ring and "F6 -> Auxiliary" in editor_ring
        assert "Traversal 2/2" in auxiliary_ring and "F6 -> Editor" in auxiliary_ring
    else:
        navigation_ring = (ASSETS / "states" / f"{alt}-focus-navigation-80x24.txt").read_text()
        assert "Traversal 1/3" in editor_ring and "F6 -> Navigation" in editor_ring
        assert "Traversal 2/3" in navigation_ring and "F6 -> Auxiliary" in navigation_ring
        assert "Traversal 3/3" in auxiliary_ring and "F6 -> Editor" in auxiliary_ring

transitions = (ROOT / "transitions-01b.md").read_text()
for token in ("T12a", "T12b", "T20 A/B forward", "T20 A/B reverse", "T20 C forward", "T20 C reverse", "focus-editor", "focus-navigation", "focus-auxiliary"):
    assert token in transitions, f"transition evidence omits {token}"

# Emergency alternatives intentionally converge after their identity header:
# editor/recovery/help/quit outrank navigation presentation at this minimum.
for width, height in ((40, 12), (41, 27), (120, 13)):
    rendered = []
    for alt in ALTS:
        path = ASSETS / f"{alt}-{width}x{height}.txt" if (width, height) == (40, 12) else ASSETS / "boundaries" / f"{alt}-{width}x{height}.txt"
        rendered.append(path.read_text().splitlines()[1:])
    assert rendered[0] == rendered[1] == rendered[2], f"unjustified emergency divergence at {width}x{height}"

# Constrained shells share editor+one-auxiliary allocation after the header;
# C retains its explicit Commands entry in that header.
constrained = [(ASSETS / f"{alt}-60x20.txt").read_text().splitlines()[1:] for alt in ALTS]
assert constrained[0] == constrained[1] == constrained[2], "constrained body layouts diverged"
assert "[Commands]" in (ASSETS / "c-command-60x20.txt").read_text(), "C constrained header lost pointer Commands"
for width in (60, 61, 78):
    assert "[Commands]" in (ASSETS / "boundaries" / f"c-command-{width}x27.txt").read_text(), f"C constrained {width} lost Commands"

assert valid_state("a-labeled", "focus-navigation")
assert not valid_state("c-command", "focus-navigation")
assert not valid_state("a-labeled", "focus-terminal")
harness = ROOT / "prototype_harness_01b.py"
valid_run = subprocess.run([sys.executable, str(harness), "c-command", "focus-auxiliary", "80", "24"], capture_output=True, text=True)
assert valid_run.returncode == 0 and len(valid_run.stdout.splitlines()) == 24
for invalid in (("a-labeled", "focus-terminal"), ("c-command", "focus-navigation")):
    run = subprocess.run([sys.executable, str(harness), invalid[0], invalid[1], "80", "24"], capture_output=True, text=True)
    assert run.returncode != 0, f"harness accepted invalid pair {invalid}"
    assert "Traceback" not in run.stderr, f"harness crashed for invalid pair {invalid}"
    assert "invalid choice" in run.stderr or "not available" in run.stderr, f"harness gave unclear error for {invalid}"

contract = (ROOT / "prototype-contract-01b.md").read_text()
for task in range(1, 23):
    assert f"T{task}" in contract, f"storyboard omits T{task}"
for command in ("file.open", "file.save", "problem.open", "terminal.toggle", "git.focus", "settings.open", "help.open", "palette.open", "focus.next_region", "mode.zen", "app.quit"):
    assert command in contract, f"command map omits {command}"
print("Prompt 01B prototype checks passed")
