#!/usr/bin/env python3
"""Verify agent workspace input, session switching, and compact rendering."""
import os
import pathlib
import shlex
import subprocess
import tempfile
import time

ROOT = pathlib.Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="vide-ai-ui-") as directory:
    base = pathlib.Path(directory)
    for name in ("config", "data/vide", "state", "cache", "bin"):
        (base / name).mkdir(parents=True)
    (base / "data/vide/settings.json").write_text('{"mode":"normal","nerd_fonts":false}')
    sample = base / "sample.py"
    sample.write_text('print("hello")\n')
    for name in ("codex", "claude"):
        command = base / "bin" / name
        command.write_text("#!/bin/sh\nexec cat\n")
        command.chmod(0o755)
    socket = str(base / "tmux.sock")

    def tmux(*args):
        return subprocess.check_output(["tmux", "-S", socket, *args], text=True)

    def screen():
        return tmux("capture-pane", "-p", "-t", "ui")

    def wait_for(text):
        deadline = time.monotonic() + 6
        while time.monotonic() < deadline:
            grid = screen()
            if text in grid:
                return grid
            time.sleep(0.05)
        raise AssertionError(text + " missing:\n" + screen())

    def click(label):
        grid = wait_for(label)
        row, line = next((row, line) for row, line in enumerate(grid.splitlines()) if label in line)
        col = line.index(label)
        tmux("send-keys", "-l", "-t", "ui", f"\x1b[<0;{col + 1};{row + 1}M\x1b[<0;{col + 1};{row + 1}m")
        time.sleep(0.1)

    env = {
        **{f"XDG_{name.upper()}_HOME": str(base / name) for name in ("config", "data", "state", "cache")},
        "PATH": str(base / "bin") + os.pathsep + os.environ["PATH"],
        "VIDE_DISABLE_PLUGINS": "1", "VIDE_SKIP_ONBOARDING": "1", "TERM": "xterm-256color", "SHELL": "/bin/sh",
    }
    command = shlex.join(["env", *(f"{k}={v}" for k, v in env.items()), str(ROOT / "zig-out/bin/vide"), str(sample)])
    try:
        tmux("new-session", "-d", "-s", "ui", "-x", "120", "-y", "36", "-c", str(base), command)
        wait_for('sample.py')
        time.sleep(0.3)
        click("AI assistants")
        wait_for("AI CHAT")
        assert 'Context' not in screen() and 'Actions' not in screen()
        click("Open chat")
        wait_for("Return to chat")
        click("Codex v")
        wait_for("CHOOSE AGENT")
        click("Claude Code")
        wait_for("Open chat")
        assert "Send file" not in screen(), "Actions target the previous agent"
        click("Open chat")
        wait_for("Return to chat")
        click("Claude Code v")
        click("Codex")
        click("Return to chat")
        grid = wait_for("Chat open")
        pathlib.Path('/tmp/vide-ai-expanded.txt').write_text(grid)
        wait_for("Send selection")
        wait_for("Send file")
        wait_for("Review changes")
        tmux("resize-window", "-t", "ui", "-x", "65", "-y", "20")
        wait_for("AI CHAT")
        click("Stop chat")
        grid = wait_for("Chat stopped")
        pathlib.Path('/tmp/vide-ai-compact.txt').write_text(grid)
        click("Restart chat")
        wait_for("Chat open")
        tmux("send-keys", "-t", "ui", "F1")
        wait_for("Commands / type to filter")
        tmux("send-keys", "-l", "-t", "ui", "Open terminal right")
        wait_for("Open terminal right")
        tmux("send-keys", "-t", "ui", "Enter")
        time.sleep(0.4)
        marker = base / 'right-terminal'
        tmux("send-keys", "-l", "-t", "ui", "printf terminal-ok > " + shlex.quote(str(marker)))
        tmux("send-keys", "-t", "ui", "Enter")
        deadline = time.monotonic() + 5
        while not marker.exists() and time.monotonic() < deadline:
            time.sleep(0.05)
        assert marker.read_text() == 'terminal-ok', screen()
        tmux("send-keys", "-t", "ui", "F1")
        wait_for("Commands / type to filter")
        tmux("send-keys", "-l", "-t", "ui", "Close buffer")
        tmux("send-keys", "-t", "ui", "Enter")
        time.sleep(0.3)
        grid = screen()
        assert 'E89:' not in grid and 'Press ENTER' not in grid, grid
        tmux("send-keys", "-t", "ui", "F1")
        wait_for("Commands / type to filter")
        tmux("send-keys", "-t", "ui", "Escape")
        time.sleep(0.1)
        tmux("send-keys", "-t", "ui", "C-t")
        wait_for("TERMINAL")
        time.sleep(0.3)
        tmux("send-keys", "-l", "-t", "ui", "exit")
        tmux("send-keys", "-t", "ui", "Enter")
        time.sleep(0.3)
        tmux("send-keys", "-t", "ui", "C-t")
        time.sleep(0.1)
        tmux("send-keys", "-t", "ui", "C-t")
        time.sleep(0.3)
        marker = base / 'bottom-reopened'
        tmux("send-keys", "-l", "-t", "ui", "printf reopened > " + shlex.quote(str(marker)))
        tmux("send-keys", "-t", "ui", "Enter")
        deadline = time.monotonic() + 5
        while not marker.exists() and time.monotonic() < deadline:
            time.sleep(0.05)
        assert marker.read_text() == 'reopened', screen()
        tmux("send-keys", "-t", "ui", "C-q")
    finally:
        subprocess.run(["tmux", "-S", socket, "kill-server"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
print("AI/terminal UI passed: chat actions, right terminal close, bottom terminal exit and reopen with working shell input")
