#!/usr/bin/env python3
import fcntl
import json
import os
import pathlib
import pty
import select
import signal
import struct
import tempfile
import termios
import time

ROOT = pathlib.Path(__file__).resolve().parents[1]
BINARY = pathlib.Path(os.environ.get("VIDE_TEST_BINARY", ROOT / "zig-out/bin/vide")).resolve()
ENTER_ALT = b"\x1b[?1049h"
LEAVE_ALT = b"\x1b[?1049l"
ENABLE_PASTE = b"\x1b[?2004h"
DISABLE_PASTE = b"\x1b[?2004l"


def read_available(fd, deadline):
    output = bytearray()
    while time.monotonic() < deadline:
        ready, _, _ = select.select([fd], [], [], 0.1)
        if not ready:
            continue
        try:
            chunk = os.read(fd, 65536)
        except BlockingIOError:
            continue
        except OSError:
            break
        if not chunk:
            break
        output.extend(chunk)
    return bytes(output)


def terminate_child(pid, grace=1.0):
    os.kill(pid, signal.SIGTERM)
    deadline = time.monotonic() + grace
    while time.monotonic() < deadline:
        waited, status = os.waitpid(pid, os.WNOHANG)
        if waited != 0:
            return status
        time.sleep(0.05)
    os.kill(pid, signal.SIGKILL)
    _, status = os.waitpid(pid, 0)
    return status


def run_mode(mode):
    with tempfile.TemporaryDirectory(prefix="vide-pty-") as temp:
        base = pathlib.Path(temp)
        data = base / "data/vide"
        data.mkdir(parents=True)
        (data / "settings.json").write_text(json.dumps({"mode": mode}), encoding="utf-8")

        pid, fd = pty.fork()
        if pid == 0:
            env = os.environ.copy()
            env.update({
                "HOME": temp,
                "XDG_CONFIG_HOME": str(base / "config"),
                "XDG_DATA_HOME": str(base / "data"),
                "XDG_STATE_HOME": str(base / "state"),
                "XDG_CACHE_HOME": str(base / "cache"),
                "VIDE_DISABLE_PLUGINS": "1",
                "VIDE_SKIP_ONBOARDING": "1",
                "TERM": "xterm-256color",
            })
            os.execve(BINARY, [str(BINARY)], env)

        os.set_blocking(fd, False)
        original = termios.tcgetattr(fd)
        fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 100, 0, 0))
        os.kill(pid, signal.SIGWINCH)
        output = bytearray(read_available(fd, time.monotonic() + 1.5))

        if mode != "zen":
            os.write(fd, "integration 界 🙂".encode("utf-8"))
            output.extend(read_available(fd, time.monotonic() + 0.3))
            os.write(fd, b"\r")
            output.extend(read_available(fd, time.monotonic() + 0.3))
            os.write(fd, b"\x1b[200~pasted text\nsecond line\x1b[201~")
            output.extend(read_available(fd, time.monotonic() + 0.3))
            os.write(fd, b"\x1b[<0;50;5M\x1b[<0;50;5m")
            output.extend(read_available(fd, time.monotonic() + 0.3))
            fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 120, 0, 0))
            os.kill(pid, signal.SIGWINCH)
        output.extend(read_available(fd, time.monotonic() + 1.0))
        waited = 0
        status = 0
        deadline = time.monotonic() + 8.0
        while time.monotonic() < deadline:
            os.write(fd, b"\x11")  # Ctrl-Q
            output.extend(read_available(fd, min(deadline, time.monotonic() + 0.4)))
            waited, status = os.waitpid(pid, os.WNOHANG)
            if waited != 0:
                break
            time.sleep(0.1)
        if waited == 0:
            status = terminate_child(pid)
            tail = bytes(output[-1000:]).decode("utf-8", errors="replace")
            log_path = data / "vide.log"
            log = log_path.read_text(encoding="utf-8", errors="replace") if log_path.exists() else "<missing>"
            os.close(fd)
            raise AssertionError(f"{mode}: Vide did not exit after Ctrl-Q; output tail: {tail!r}; log: {log}")

        output.extend(read_available(fd, time.monotonic() + 0.25))
        restored = termios.tcgetattr(fd)
        os.close(fd)

        if os.WIFEXITED(status):
            if os.WEXITSTATUS(status) != 0:
                raise AssertionError(f"{mode}: Vide exited with code {os.WEXITSTATUS(status)}")
        elif os.WIFSIGNALED(status):
            sig = os.WTERMSIG(status)
            if sig not in (signal.SIGTERM, signal.SIGHUP):
                raise AssertionError(f"{mode}: Vide died from unexpected signal {sig}")
        else:
            raise AssertionError(f"{mode}: Vide exited abnormally: {status}")

        assert restored == original, f"{mode}: terminal attributes were not restored"
        assert ENTER_ALT in output, f"{mode}: alternate screen was not enabled"
        assert ENABLE_PASTE in output, f"{mode}: bracketed paste was not enabled"
        assert DISABLE_PASTE in output, f"{mode}: bracketed paste was not disabled"
        assert LEAVE_ALT in output, f"{mode}: alternate screen was not disabled"


def run_startup_failure():
    with tempfile.TemporaryDirectory(prefix="vide-pty-failure-") as temp:
        pid, fd = pty.fork()
        if pid == 0:
            env = os.environ.copy()
            env.update({"HOME": temp, "PATH": "/nonexistent", "VIDE_DISABLE_PLUGINS": "1"})
            os.execve(BINARY, [str(BINARY)], env)
        os.set_blocking(fd, False)
        original = termios.tcgetattr(fd)
        output = read_available(fd, time.monotonic() + 3)
        _, status = os.waitpid(pid, 0)
        restored = termios.tcgetattr(fd)
        os.close(fd)
        assert status != 0, "missing Neovim should fail startup"
        assert restored == original, "startup failure left terminal attributes changed"
        assert LEAVE_ALT in output, "startup failure did not leave the alternate screen"
        assert b"Vide could not start" in output, "startup failure was not actionable"


if __name__ == "__main__":
    if not BINARY.exists():
        raise SystemExit("Build Vide before running PTY tests: zig build")
    for current_mode in ("normal", "ide", "zen"):
        run_mode(current_mode)
    if os.environ.get("VIDE_TEST_SKIP_STARTUP_FAILURE") != "1":
        run_startup_failure()
    print("Vide PTY integration tests passed")
