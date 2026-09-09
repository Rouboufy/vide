#!/usr/bin/env python3
"""Generate Prompt 01B's deterministic, exact-cell ASCII shell assets."""

from pathlib import Path

OUT = Path(__file__).with_name("prototypes-01b")
SIZES = ((120, 40), (80, 24), (60, 20), (40, 12))
WIDTH_BOUNDARIES = tuple((w, 27) for w in (39, 40, 41, 59, 60, 61, 78, 79, 80, 111, 112, 113))
HEIGHT_BOUNDARIES = tuple((120, h) for h in (11, 12, 13, 14, 15, 16, 19, 20, 21, 26, 27, 28))
STATES = (
    "default", "action-menu", "problems", "terminal", "git", "settings-dirty",
    "nested-confirmation", "help", "command-palette", "zen", "disabled-reason", "file-search",
    "text-search", "telescope", "splits", "delete-confirmation", "focus-editor",
    "focus-navigation", "focus-auxiliary", "t12-parent-help",
    "t12-dismissible-child", "t12-restored-parent", "t12-blocked-child", "t12-stop",
)
ALTS = {
    "a-labeled": "A Labeled collapsible navigation",
    "b-mnemonic": "B Mnemonic text rail",
    "c-command": "C Command-first / no permanent rail",
}


def valid_state(alt: str, state: str) -> bool:
    """Return whether a facilitator state exists for this alternative."""
    return alt in ALTS and state in STATES and not (alt == "c-command" and state == "focus-navigation")


def fit(text: str, width: int) -> str:
    return text[:width].ljust(width)


def row(parts: list[tuple[str, int]]) -> str:
    return "|".join(fit(text, width) for text, width in parts)


def nav(alt: str, width: int) -> list[str]:
    if alt == "a-labeled" and width >= 112:
        return ["[E] Explorer", " S  Search", "!1 Problems", " G  Source Control", " T  Terminal", "[] Settings", " ?  Help"]
    if alt == "a-labeled":
        return ["[E]", " S ", "!1 ", " G ", " T ", "[] ", " ? "]
    if alt == "b-mnemonic":
        return ["[E]", " S ", "!1 ", " G ", " T ", " C ", " ? "]
    return []


def axis_tier(value: int, boundaries: tuple[int, int, int, int]) -> str:
    emergency, constrained, compact, comfortable = boundaries
    if value < emergency:
        return "below-emergency"
    if value < constrained:
        return "emergency"
    if value < compact:
        return "constrained"
    if value < comfortable:
        return "compact"
    return "comfortable"


RANK = {"below-emergency": 0, "emergency": 1, "constrained": 2, "compact": 3, "comfortable": 4}


def state_aux(state: str, alt: str) -> list[str]:
    decks = {
        "default": ["[Explorer] current", "> src/ selected", "  tui/", "    app.zig", "    events.zig ! Error", "  main.zig", "", "[Open] [New] [Actions]", "Problems !1", "Git 1 unread", "Extensions Loading...", "Commit disabled [? why]", "Terminal [Open]", "Settings [Open]", "Help [?]"],
        "action-menu": ["[ACTIONS]", "[Open File]", "[Save Ctrl-S]", "[Search Files]", "[Search Text]", "[Split Vertical]", "[Close]", "Return: Escape"],
        "problems": ["[Problems !1]", "> Error: fixture", "  events.zig:42", "[Open Details]", "[Go to location]", "[Return to editor]"],
        "terminal": ["[Terminal]", "$ printf ok", "ok", "Escape -> terminal", "Ctrl-\\ e -> editor", "[Return to editor]", "[Hide; retain session]"],
        "git": ["[Source Control]", "> fixture.txt", "[Stage]", "Commit: fixture", "[Commit] [Cancel]", "Cancel keeps stage", "[Return to editor]"],
        "settings-dirty": ["[DIALOG Settings *]", "> Theme: light", "[Save] [Close]", "Close -> dirty prompt", "F6 blocked: resolve", "[Cancel] [Discard]"],
        "nested-confirmation": ["[DIALOG Unsaved]", "Discard changes?", "[Cancel] [Discard]", "Escape: one level", "Choose an action", "No outside dismissal"],
        "help": ["[Help]", "Invoked by: Editor", "> selected", "! Error: fixture", "1 unread", "Loading...", "disabled [? why]", "Quit: app.quit", "[Return to editor]"],
        "command-palette": ["[Command Palette]", "Filter: searchable", "> file.open", "  file.save", "  search.files", "  search.text", "  problem.open", "  terminal.toggle", "  git.focus", "  settings.open", "  split.vertical", "  mode.zen", "  focus.editor", "  app.quit", "[Run] [Close]"],
        "zen": ["[VideZen]", "Editor owns viewport", "Shell state retained", "[Leave Zen]", "restore prior focus"],
        "disabled-reason": ["[Command details]", "Commit disabled", "Reason: Missing author", "identity", "[Resolve fixture]", "[Retry same command]"],
        "file-search": ["[Search Files]", "Query: events.zig", "> src/tui/events.zig", "[Open] [Cancel]", "results retained"],
        "text-search": ["[Search Text]", "Query: FocusTarget", "> events.zig:88", "  app.zig:31", "[Open] [Cancel]", "results retained"],
        "telescope": ["[Neovim Telescope]", "> first result", "  second result", "Escape -> Neovim", "[Accept first]", "shell pass-through"],
        "splits": ["[Editor grids]", "| grid 1 | grid 2 |", "        > focused", "[Move] [Close split]", "Neovim owns grids"],
        "delete-confirmation": ["[DIALOG Delete]", "fixture-delete.txt", "cannot be undone", "[Cancel] [Delete]", "Default: Cancel", "restore Explorer"],
        "focus-editor": ["Traversal 1/4", "Editor focused", "F6 -> Navigation", "Shift-F6 -> Terminal"],
        "focus-navigation": ["Traversal 2/4", "Navigation focused", "F6 -> Auxiliary", "Shift-F6 -> Editor"],
        "focus-auxiliary": ["Traversal 3/4", "Auxiliary focused", "F6 -> Terminal", "Shift-F6 -> Navigation"],
        "t12-parent-help": ["[Help parent]", "invoker: Editor", "[Open supplied child]", "[Return to editor]"],
        "t12-dismissible-child": ["[DIALOG Child]", "Dismissible", "[Cancel]", "Escape -> parent Help", "input trapped here"],
        "t12-restored-parent": ["[Help parent restored]", "Child dismissed", "focus restored here", "[Open blocked child]"],
        "t12-blocked-child": ["[DIALOG Required]", "Non-dismissible", "Choose an action", "Escape: no dismissal", "[Continue]"],
        "t12-stop": ["[DIALOG Required]", "Still owns focus", "Escape repeated: stopped", "Choose [Continue]", "no input leakage"],
    }
    if state.startswith("focus-"):
        if alt == "c-command":
            ring = {"focus-editor": ["Traversal 1/2", "Editor focused", "F6 -> Auxiliary", "Shift-F6 -> Auxiliary"], "focus-auxiliary": ["Traversal 2/2", "Auxiliary focused", "F6 -> Editor", "Shift-F6 -> Editor"]}
        else:
            ring = {"focus-editor": ["Traversal 1/3", "Editor focused", "F6 -> Navigation", "Shift-F6 -> Auxiliary"], "focus-navigation": ["Traversal 2/3", "Navigation focused", "F6 -> Auxiliary", "Shift-F6 -> Editor"], "focus-auxiliary": ["Traversal 3/3", "Auxiliary focused", "F6 -> Editor", "Shift-F6 -> Navigation"]}
        return ring[state]
    return decks[state]


def make(alt: str, width: int, height: int, state: str = "default") -> list[str]:
    title = ALTS[alt]
    wt = axis_tier(width, (40, 60, 79, 112))
    ht = axis_tier(height, (12, 15, 20, 27))
    tier = wt if RANK[wt] <= RANK[ht] else ht
    if tier in ("below-emergency", "emergency"):
        border = "+" + "-" * (width - 2) + "+"
        def editor_line(text: str) -> str:
            return "|" + fit(text, width - 2) + "|"
        if state in ("help", "command-palette"):
            owner = "Help" if state == "help" else "Command Palette"
            entries = ["FOCUS and states", "> selected  ! Error", "1 unread  Loading...", "disabled [? why]", "Quit: app.quit"] if state == "help" else ["file.open  file.save", "terminal.toggle", "help.open  mode.zen", "focus.editor  app.quit", "[Run] [Close]"]
            core = [fit(f"VIDE | {title.split(' ', 1)[0]} | Emergency", width), fit(f"[FOCUS: {owner}]", width), border]
            core += [editor_line(entry) for entry in entries]
            core += [border, fit("Resize >=60x15 restores surfaces", width), fit("State and sessions retained", width)]
            while len(core) > height:
                core.pop(-3)
            while len(core) < height:
                core.insert(-2, fit("", width))
            return core
        core = [
            fit(f"VIDE | {title.split(' ', 1)[0]} | VideNormal", width),
            fit("[FOCUS: Editor] src/main.zig", width),
            border,
            editor_line(" 1  const std = @import(\"std\");"),
            editor_line(" 2  // editor remains usable"),
            border,
            fit("Emergency: auxiliaries suspended" if tier == "emergency" else "Too small: resize to recover editor", width),
            fit("Resize to >=60x15 to restore them", width),
            fit("F1 Help: >sel !error 1 unread", width),
            fit("Loading... disabled [? why]", width),
            fit("F1 Help | Ctrl-Shift-P Commands", width),
            fit(":q Quit | state and sessions retained", width),
        ]
        if height < len(core):
            # Below 12 rows, recovery/help/quit take precedence over editor sample.
            core = core[:2] + core[-(height - 2):]
        while len(core) < height:
            core.insert(-6, editor_line(" ~"))
        return core

    owners = {
        "terminal": "Terminal", "git": "Source Control", "settings-dirty": "Settings dialog",
        "nested-confirmation": "Unsaved dialog", "help": "Help", "command-palette": "Command Palette",
        "problems": "Problems", "disabled-reason": "Command details", "file-search": "File Search",
        "text-search": "Text Search", "delete-confirmation": "Delete dialog",
        "focus-navigation": "Navigation", "focus-auxiliary": "Auxiliary",
        "t12-parent-help": "Help", "t12-dismissible-child": "Child dialog",
        "t12-restored-parent": "Help", "t12-blocked-child": "Required dialog", "t12-stop": "Required dialog",
    }
    owner = owners.get(state, "Editor")
    header = f"VIDE | VideNormal | {tier} | [FOCUS: {owner}]"
    if alt == "c-command":
        header = f"VIDE|{tier}|[Commands]|[FOCUS: {owner}]"
    footer = "F1 Help | F6/Shift-F6 Regions | Ctrl-Shift-P Commands | Save Ctrl-S"
    tab = "[src/main.zig*]  src/tui/events.zig  !1 Problem  Loading...  Git 1"
    nav_lines = nav(alt, width)

    if state in ("zen", "telescope", "splits"):
        label = "VideZen | [FOCUS: Editor]" if state == "zen" else "Editor overlay | [FOCUS: Editor grid]" if state == "telescope" else "Editor splits | [FOCUS: Editor grid 2]"
        lines = [fit(label, width)]
        if state == "zen": content = ["src/main.zig", "", " 1 const app = Vide.init();", "", "Editor owns full viewport", "Shell state retained", "[Leave Zen]"]
        elif state == "telescope": content = ["+ Neovim-owned Telescope +", "> first result", "  second result", "Move: Down", "Escape cancels in Neovim", "Enter accepts first", "Shell input pass-through"]
        else: content = ["src/main.zig", "+ editor grid 1 +|+ editor grid 2 +", "| original buffer |>| focused buffer  |", "| cursor/state    || cursor/state     |", "[Move grid] [Close grid 2]", "Neovim owns both grids"]
        for i in range(height - 2): lines.append(fit(content[i] if i < len(content) else "~", width))
        lines.append(fit("F1 Help | Ctrl-Shift-P Commands", width))
        return lines

    if tier == "constrained":
        aux_w = 19
        editor_w = width - aux_w - 1
        aux = state_aux(state, alt)
        body_h = height - 3
        body = []
        for i in range(body_h):
            left = tab if i == 0 else (f"{i:>2}  " + ("const app = Vide.init();" if i == 2 else "~"))
            right = aux[i] if i < len(aux) else ""
            body.append(row([(left, editor_w), (right, aux_w)]))
        return [fit(header, width), *body, fit(footer, width), fit("Terminal hidden, session retained | Return: Ctrl-\\ e", width)]

    rail_w = 18 if alt == "a-labeled" and wt == "comfortable" else (3 if alt != "c-command" else 0)
    aux_w = 28 if width >= 112 else 24
    separators = (1 if rail_w else 0) + 1
    editor_w = width - rail_w - aux_w - separators
    body_h = height - 3
    aux = state_aux(state, alt)
    body = []
    for i in range(body_h):
        parts = []
        if rail_w:
            labels = nav_lines
            parts.append((labels[i] if i < len(labels) else "", rail_w))
        left = tab if i == 0 else (f"{i:>2}  " + ("const app = Vide.init();" if i == 2 else "~"))
        parts.extend(((left, editor_w), (aux[i] if i < len(aux) else "", aux_w)))
        body.append(row(parts))
    return [fit(header, width), *body, fit(footer, width), fit("Terminal: [Open] | when focused: Ctrl-\\ e returns | Escape passes through", width)]


def main() -> None:
    OUT.mkdir(exist_ok=True)
    boundaries = OUT / "boundaries"
    states = OUT / "states"
    boundaries.mkdir(exist_ok=True)
    states.mkdir(exist_ok=True)
    for alt in ALTS:
        for width, height in SIZES:
            lines = make(alt, width, height)
            assert len(lines) == height, (alt, width, height, len(lines))
            assert all(len(line) == width for line in lines)
            (OUT / f"{alt}-{width}x{height}.txt").write_text("\n".join(lines) + "\n")
        for width, height in WIDTH_BOUNDARIES + HEIGHT_BOUNDARIES:
            lines = make(alt, width, height)
            assert len(lines) == height and all(len(line) == width for line in lines)
            (boundaries / f"{alt}-{width}x{height}.txt").write_text("\n".join(lines) + "\n")
        invalid_focus_states = set()
        if alt == "c-command":
            invalid_focus_states.add("focus-navigation")
        for state in STATES:
            if not valid_state(alt, state):
                continue
            lines = make(alt, 80, 24, state)
            (states / f"{alt}-{state}-80x24.txt").write_text("\n".join(lines) + "\n")
        for state in invalid_focus_states:
            (states / f"{alt}-{state}-80x24.txt").unlink(missing_ok=True)
        # Remove assets generated by older deck schemas.
        (states / f"{alt}-focus-terminal-80x24.txt").unlink(missing_ok=True)
        for state in ("help", "command-palette"):
            lines = make(alt, 40, 12, state)
            (states / f"{alt}-{state}-40x12.txt").write_text("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
