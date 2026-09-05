#!/usr/bin/env python3
"""Exercise workspace UI and focus restoration against a real terminal grid."""
import argparse
import json
import pathlib
import shlex
import subprocess
import tempfile
import time

ROOT = pathlib.Path(__file__).resolve().parents[1]


def run(capture=None):
    with tempfile.TemporaryDirectory(prefix="vide-workspace-test-") as directory:
        base = pathlib.Path(directory)
        for name in ("config", "data/vide", "state", "cache"):
            (base / name).mkdir(parents=True, exist_ok=True)
        (base / "data/vide/settings.json").write_text('{"mode":"normal","nerd_fonts":false}')
        sample = base / "sample.zig"
        sample.write_text('const answer: u32 = 42;\n')
        socket = str(base / "tmux.sock")

        def tmux(*args):
            return subprocess.check_output(["tmux", "-S", socket, *args], text=True)

        def screen():
            return tmux("capture-pane", "-p", "-t", "ui")

        def wait_for(predicate, description, timeout=6):
            deadline = time.monotonic() + timeout
            while time.monotonic() < deadline:
                grid = screen()
                if predicate(grid):
                    return grid
                time.sleep(0.05)
            raise AssertionError(description + "\n" + screen())

        def send(*keys):
            for key in keys:
                tmux("send-keys", "-t", "ui", key)
                # A standalone Escape must finish the terminal's Alt-key
                # disambiguation window before the following keystroke.
                time.sleep(0.08)

        def text(value):
            tmux("send-keys", "-l", "-t", "ui", value)

        def palette(query):
            send("F1")
            wait_for(lambda s: "Commands / type to filter" in s, "Palette did not open")
            text(query)
            send("Enter")

        env = {
            "XDG_CONFIG_HOME": str(base / "config"),
            "XDG_DATA_HOME": str(base / "data"),
            "XDG_STATE_HOME": str(base / "state"),
            "XDG_CACHE_HOME": str(base / "cache"),
            "VIDE_DISABLE_PLUGINS": "1",
            "VIDE_SKIP_ONBOARDING": "1",
            "TERM": "xterm-256color",
        }
        command = shlex.join(["env", *(f"{k}={v}" for k, v in env.items()), str(ROOT / "zig-out/bin/vide"), str(sample)])
        try:
            tmux("new-session", "-d", "-s", "ui", "-x", "100", "-y", "30", "-c", str(base), command)
            normal = wait_for(lambda s: "WORKSPACE" in s and "sample.zig" in s and "OPEN FILES" in s, "Workspace did not render")
            assert "[?] Help" not in normal, "Legacy status chrome remains"
            if capture:
                destination = pathlib.Path(capture)
                destination.mkdir(parents=True, exist_ok=True)
                (destination / "normal.txt").write_text(normal)
                (destination / "normal.ansi").write_text(tmux("capture-pane", "-p", "-e", "-t", "ui"))

            # Section rules and their blank gutters are not action targets.
            project_header = next(i for i, line in enumerate(normal.splitlines()) if "PROJECT" in line)
            for row in (project_header - 1, project_header):
                text(f"\x1b[<0;4;{row + 1}M\x1b[<0;4;{row + 1}m")
                send("Escape")
                assert "OPEN FILES" in screen(), "Section spacing activated a tool"

            # Added section spacing must keep the last action reachable when short.
            tmux("resize-window", "-t", "ui", "-x", "100", "-y", "12")
            send("F6", *(["Down"] * 12))
            wait_for(lambda s: "> Settings" in s, "Short sidebar did not scroll to focused Settings")
            send(*(["Up"] * 12))
            wait_for(lambda s: "> [No Name]" in s or "> sample.zig" in s, "Short sidebar did not scroll back to file")
            send("Escape")
            tmux("resize-window", "-t", "ui", "-x", "100", "-y", "30")
            wait_for(lambda s: "PROJECT" in s and "Settings" in s, "Sidebar sections did not return after resize")

            # The same workspace actions are reachable through mouse hit tests.
            project_row = next(i for i, line in enumerate(screen().splitlines()) if "Project files" in line)
            text(f"\x1b[<0;4;{project_row + 1}M\x1b[<0;4;{project_row + 1}m")
            wait_for(lambda s: "< Workspace [Esc]" in s, "Mouse did not open project files")
            text("\x1b[<0;4;2M\x1b[<0;4;2m")
            wait_for(lambda s: "WORKSPACE" in s and "OPEN FILES" in s, "Mouse did not return to workspace")
            file_row = next(i for i, line in enumerate(screen().splitlines()[2:], 2) if "sample.zig" in line)
            text(f"\x1b[<0;4;{file_row + 1}M\x1b[<0;4;{file_row + 1}m")
            wait_for(lambda s: "Editor" in s.splitlines()[-1], "Mouse file selection did not focus editor")

            send("i")
            text("// saved ")
            send("Escape", "C-s")
            wait_for(lambda _: sample.read_text().startswith("// saved "), "Ctrl-S did not save")

            send("F6")
            wait_for(lambda s: "Workspace" in s.splitlines()[-1], "F6 did not focus sidebar")
            send("F11")
            zen = wait_for(lambda s: "WORKSPACE" not in s and "Return" in s, "Zen did not hide shell")
            if capture:
                (destination / "zen.txt").write_text(zen)
            send("i")
            text("zen-edit ")
            send("Escape", "C-s")
            wait_for(lambda _: "zen-edit" in sample.read_text(), "Zen input went to hidden sidebar")
            send("F11")
            wait_for(lambda s: "Workspace" in s.splitlines()[-1] and "WORKSPACE" in s, "Zen did not restore sidebar focus")
            send("Escape")

            send("F1")
            text("keyboard")
            menu = wait_for(lambda s: "keyboard" in s and "Keyboard shortcuts" in s and "Commands / type to filter" in s, "Palette did not filter")
            if capture:
                (destination / "commands.txt").write_text(menu)
            send("Enter")
            wait_for(lambda s: "Next Region" in s and "Save File" in s, "Shortcut editor did not open")
            send("Right")
            send(*(["Down"] * 8), "Enter", "F2", "C-s")
            wait_for(lambda _: json.loads((base / "data/vide/settings.json").read_text()).get("keybindings", {}).get("focus_next") == "<F2>", "Keyboard-only binding edit/save did not persist")
            wait_for(lambda s: "Keybindings / Enter" not in s, "Settings did not close")
            send("F2")
            wait_for(lambda s: "Workspace" in s.splitlines()[-1], "Remapped focus shortcut did not apply")
            palette("keyboard")
            wait_for(lambda s: "Next Region" in s, "Could not reopen keybindings")
            send("Right", "p", "C-s")
            wait_for(lambda _: json.loads((base / "data/vide/settings.json").read_text()).get("keybindings", {}).get("focus_next") == "<F6>", "Familiar preset did not restore focus binding")

            palette("terminal")
            wait_for(lambda s: "Terminal" in s.splitlines()[-1], "Terminal did not take focus")
            text("export VIDE_WORKSPACE_TEST=alive")
            send("Enter")
            time.sleep(0.2)
            send("F11")
            wait_for(lambda s: "Return" in s and "WORKSPACE" not in s, "Terminal focus prevented zen")
            send("F11")
            wait_for(lambda s: "Terminal" in s.splitlines()[-1] and "WORKSPACE" in s, "Terminal focus did not restore")
            text("printf %s \"$VIDE_WORKSPACE_TEST\" > " + shlex.quote(str(base / "terminal-alive")))
            send("Enter")
            wait_for(lambda _: (base / "terminal-alive").exists() and (base / "terminal-alive").read_text() == "alive", "Zen restarted or lost the terminal session")
            send("F6")
            wait_for(lambda s: "Editor" in s.splitlines()[-1], "F6 did not leave terminal")

            # The narrow fallback keeps commands reachable without a sidebar.
            tmux("resize-window", "-t", "ui", "-x", "30", "-y", "12")
            send("F1")
            wait_for(lambda s: "Commands / type to filter" in s, "Narrow palette inaccessible")
            send("Escape")
            tmux("resize-window", "-t", "ui", "-x", "100", "-y", "30")
            wait_for(lambda s: "WORKSPACE" in s, "Sidebar did not return after resize")
            send("F6")
            palette("new file")
            wait_for(lambda s: "Editor" in s.splitlines()[-1], "New file kept focus in the sidebar")
            send("i")
            text("new-file-input")
            wait_for(lambda s: "new-file-input" in s, "New file did not accept editor input")
            send("Escape")
            send("C-q")
        finally:
            subprocess.run(["tmux", "-S", socket, "kill-server"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    print("Workspace UI integration passed: save, palette, settings, zen, focus, terminal session, resize")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--capture", type=pathlib.Path)
    run(parser.parse_args().capture)
