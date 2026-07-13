#!/usr/bin/env python3
import argparse
import fcntl
import json
import os
import pathlib
import platform
import pty
import select
import signal
import struct
import subprocess
import tempfile
import termios
import time

ROOT = pathlib.Path(__file__).resolve().parents[1]


def read_until_idle(fd, timeout=5.0, idle=0.2):
    output = bytearray()
    start = last = time.perf_counter()
    first_output = None
    while time.perf_counter() - start < timeout:
        ready, _, _ = select.select([fd], [], [], 0.05)
        if ready:
            try:
                chunk = os.read(fd, 65536)
            except OSError:
                break
            if not chunk:
                break
            if first_output is None:
                first_output = time.perf_counter()
            output.extend(chunk)
            last = time.perf_counter()
        elif output and time.perf_counter() - last >= idle:
            break
    return bytes(output), first_output


def run_session(binary, cwd, base, args=(), plugins=False, exercise=False):
    data = base / "data/vide"
    data.mkdir(parents=True, exist_ok=True)
    (data / "settings.json").write_text('{"mode":"normal","nerd_fonts":false}', encoding="utf-8")
    if plugins:
        installed = pathlib.Path.home() / ".local/share/vide/lazy"
        if not installed.is_dir():
            return {"available": False, "reason": "no installed plugin tree"}
        (data / "lazy").symlink_to(installed, target_is_directory=True)

    pid, fd = pty.fork()
    started = time.perf_counter()
    if pid == 0:
        env = os.environ.copy()
        env.update({
            "HOME": str(base), "XDG_CONFIG_HOME": str(base / "config"),
            "XDG_DATA_HOME": str(base / "data"), "XDG_STATE_HOME": str(base / "state"),
            "XDG_CACHE_HOME": str(base / "cache"), "VIDE_SKIP_ONBOARDING": "1",
            "TERM": "xterm-256color",
        })
        if not plugins:
            env["VIDE_DISABLE_PLUGINS"] = "1"
        os.chdir(cwd)
        os.execve(binary, [binary, *map(str, args)], env)

    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 120, 0, 0))
    os.kill(pid, signal.SIGWINCH)
    initial, first = read_until_idle(fd, timeout=8 if plugins else 4)
    if plugins:
        plugin_deadline = time.perf_counter() + 3.0
        while time.perf_counter() < plugin_deadline:
            extra, extra_first = read_until_idle(fd, timeout=0.5, idle=0.1)
            initial += extra
            if first is None and extra_first is not None:
                first = extra_first
    ready = time.perf_counter()
    redraw_bytes = 0
    redraw_ms = None
    if exercise:
        redraw_start = time.perf_counter()
        for rows, cols in ((30, 90), (50, 160), (24, 80), (40, 120)) * 3:
            fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
            os.kill(pid, signal.SIGWINCH)
            os.write(fd, b"jkjkjk")
        redraw, _ = read_until_idle(fd, timeout=4)
        redraw_ms = (time.perf_counter() - redraw_start) * 1000
        redraw_bytes = len(redraw)

    for attempt in range(200):
        if attempt % 5 == 0:
            os.write(fd, b"\x11")
        waited, status = os.waitpid(pid, os.WNOHANG)
        if waited:
            break
        time.sleep(0.05)
    else:
        os.kill(pid, signal.SIGTERM)
        _, status = os.waitpid(pid, 0)
    os.close(fd)
    exit_status = os.WEXITSTATUS(status) if os.WIFEXITED(status) else -os.WTERMSIG(status)
    return {
        "available": True,
        "first_output_ms": round(((first or ready) - started) * 1000, 2),
        "settled_ms": round((ready - started) * 1000, 2),
        "initial_output_bytes": len(initial),
        "redraw_storm_ms": round(redraw_ms, 2) if redraw_ms is not None else None,
        "redraw_output_bytes": redraw_bytes,
        "exit_status": exit_status,
    }


def profile_plugin_initialization(base):
    installed = pathlib.Path.home() / ".local/share/vide/lazy"
    if not installed.is_dir():
        return {"available": False, "reason": "no installed plugin tree"}
    data = base / "data/vide"
    data.mkdir(parents=True)
    (data / "lazy").symlink_to(installed, target_is_directory=True)
    env = os.environ.copy()
    env.update({
        "HOME": str(base), "XDG_CONFIG_HOME": str(base / "config"),
        "XDG_DATA_HOME": str(base / "data"), "XDG_STATE_HOME": str(base / "state"),
        "XDG_CACHE_HOME": str(base / "cache"), "VIDE_SKIP_ONBOARDING": "1",
        "NVIM_APPNAME": "vide",
    })
    started = time.perf_counter()
    result = subprocess.run(
        ["nvim", "--headless", "--clean", "-u", "NONE", "-c", f"luafile {ROOT / 'src/nvim/vide_init.lua'}", "-c", "qa!"],
        cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30,
    )
    return {
        "available": True,
        "elapsed_ms": round((time.perf_counter() - started) * 1000, 2),
        "output_bytes": len(result.stdout),
        "exit_status": result.returncode,
        "scope": "headless Neovim loading Vide's installed plugin configuration",
    }


def main():
    parser = argparse.ArgumentParser(description="Profile Vide application scenarios")
    parser.add_argument("--binary", default=str(ROOT / "zig-out/bin/vide"))
    parser.add_argument("--output", default=str(ROOT / "docs/performance-profile.json"))
    ns = parser.parse_args()
    binary = str(pathlib.Path(ns.binary).resolve())
    results = {"recorded_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "system": {"platform": platform.platform(), "machine": platform.machine(), "python": platform.python_version()}, "binary": binary, "scenarios": {}}
    with tempfile.TemporaryDirectory(prefix="vide-profile-") as temp:
        base = pathlib.Path(temp)
        results["scenarios"]["startup_offline"] = run_session(binary, ROOT, base / "startup", exercise=True)

        large_file = base / "large-file.txt"
        line = "0123456789 abcdefghijklmnopqrstuvwxyz 界 🙂\n"
        with large_file.open("w", encoding="utf-8") as handle:
            for _ in range(120_000):
                handle.write(line)
        results["scenarios"]["large_file"] = {"bytes": large_file.stat().st_size, **run_session(binary, ROOT, base / "file", (large_file,))}

        large_dir = base / "large-directory"
        large_dir.mkdir()
        for index in range(5_000):
            (large_dir / f"entry-{index:05d}.txt").touch()
        results["scenarios"]["large_directory"] = {"entries": 5_000, **run_session(binary, large_dir, base / "directory")}
        results["scenarios"]["plugin_initialization"] = profile_plugin_initialization(base / "plugins")

    pathlib.Path(ns.output).write_text(json.dumps(results, indent=2) + "\n", encoding="utf-8")
    failures = [name for name, data in results["scenarios"].items() if data.get("available") and data.get("exit_status") != 0]
    if failures:
        raise SystemExit("profiling scenarios did not shut down cleanly: " + ", ".join(failures))
    print(json.dumps(results, indent=2))


if __name__ == "__main__":
    main()
