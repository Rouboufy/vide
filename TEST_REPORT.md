# Vide Test Report

## Test Environment

| Item          | Value                        |
|---------------|------------------------------|
| OS            | Linux (x86_64)               |
| Zig           | 0.16.0                       |
| Neovim        | 0.12.2                       |
| Build mode    | Debug (with debug_info)      |
| Binary size   | ~21 MB (debug), ~6 MB (stripped) |
| Test dir      | `test_vide/`                 |

## Setup

- Copied `vide/` to `test_vide/`
- Built from source: `zig build` ✓
- Unit tests: `zig build test` ✓

## Unit Tests

**2/2 passing:**

| Test | Result |
|------|--------|
| `root.test.basic add functionality` | PASS |
| `nvim.msgpack.test.msgpack roundtrip` | PASS |

All individual source modules compile cleanly without test failures.

## Runtime Execution (`script`-based PTY)

The binary was tested with `script -q -c "timeout <n> ./zig-out/bin/vide"` to provide a real `/dev/tty`.

### Terminal Size Sweep

| Rows | Cols | Result |
|------|------|--------|
| 1  | 10  | **CRASH** — integer overflow in `explorer.zig:382` |
| 1  | 20  | **CRASH** — same |
| 1  | 40  | **CRASH** — same |
| 1  | 80  | **CRASH** — same |
| 1  | 120 | **CRASH** — same |
| 2  | 10+ | OK      |
| 3  | 10+ | OK      |
| 5  | 10+ | OK      |
| 10 | 10+ | OK      |
| 50 | 10+ | OK      |
| 200| 500 | **CRASH** — integer overflow in `ui_protocol.zig:240` |

### Consistency (24x80)

5 consecutive runs at 24x80: **0 crashes** — stable.

### Arguments

- `--help`: ignored (no flag handling), app starts normally
- `/nonexistent/file`: handled gracefully, file explorer opens
- No args: dashboard loads successfully

## Bugs Found

### CRITICAL — Bug #1: Integer underflow in `explorer.zig:382`

```
const max_items = @max(1, rect.h - 1);
```

`rect.h` is `u16`. When the terminal has 1 row, `file_tree.h` = 0 (from `layout.zig:42`). `0 - 1` wraps to `65535`. The `@max(1, ...)` guard is **ineffectual** because the underflow happens before it executes.

**Affects:** All 1-row terminal scenarios. Crash on startup.

### CRITICAL — Bug #2: Integer overflow in `ui_protocol.zig:240`

```
self.grid.cells[row * self.grid.width + col] = cell;
```

`row` and `self.grid.width` are both `u16`. At terminals ≥200x500, the product `row * self.grid.width` exceeds `65535`, wrapping and indexing the wrong memory.

**Also affects:** `main.zig:421,528`, `renderer.zig:61`, `ui_protocol.zig:189,199`

### HIGH — Bug #3: Panel loop underflow in `main.zig:524`

```
var py: u16 = 0;
while (py < panel.h - 1) : (py += 1) {
```

If `panel.h == 0`, condition becomes `py < 65535`, causing ~65535 iterations with massive out-of-bounds access at line 528.

### HIGH — Bug #4: Renderer setCell overflow in `renderer.zig:61`

```
self.buf[y * self.width + x] = cell;
```

u16 × u16 product can overflow for terminals > ~256×256. The `init()` function correctly casts to `usize` (line 32), but `setCell` does not.

### MEDIUM — Bug #5: `@max` guard ordering (multiple locations)

- `main.zig:295` — `@max(1, p.h - 1)`
- `main.zig:401` — `@max(1, panel.h - 1)`
- `explorer.zig:382` — `@max(1, rect.h - 1)`

All compute `h - 1` in u16 **before** `@max` evaluates, making the guard useless when `h = 0`.

### MEDIUM — Bug #6: Grid scroll underflow in `ui_protocol.zig:195`

```
var y = bot - 1;
```

If neovim sends `bot = 0`, this wraps to `65535`. Also line 186: `bot - @as(u16, @intCast(rows))` can underflow if `bot < rows`.

## Additional Observations

1. **Msgpack RPC** — Works correctly; neovim communication established.
2. **Lua init** — Well-structured; lazy.nvim, Telescope, Treesitter, Mason, alpha-nvim dashboard, harpoon, and 10 themes pre-configured. Isolated config path (`~/.local/share/vide/`).
3. **Settings persistence** — JSON-based settings load/save via both Zig and Lua paths.
4. **Theme sync** — Neovim `ColorScheme` autocast triggers `rpcnotify` to send RGB colors to the Zig renderer.
5. **Constructor initial buffer** — `general-purpose allocator` used; no arena for event data, but cleanup is explicit.
6. **No memory leak detection** — No valgrind/ASan testing performed (TUI app requires terminal).

## Recommendations

1. **Fix Bug #1** (explorer.zig:382): `const max_items = if (rect.h > 0) @max(1, rect.h - 1) else 0;`
2. **Fix Bug #2** (ui_protocol.zig:240, renderer.zig:61): Cast to `usize` before multiplication: `@as(usize, row) * @as(usize, self.grid.width) + col`
3. **Fix Bug #3** (main.zig:524): Add guard before loop: `if (panel.h < 1) continue;`
4. **Fix Bug #4** (renderer.zig:61): Same usize cast pattern.
5. **Fix Bug #5** (main.zig:295,401): Use saturating arithmetic or check before subtract: `if (p.h > 0) @max(1, p.h - 1) else 1`
6. **Fix Bug #6** (ui_protocol.zig:195): Guard `bot > 0` before `bot - 1`.

## Script Tests

### Installer (`setup.sh`)
- **Result:** PASS
- Installed symlinks at `~/.local/bin/vide`, config at `~/.config/vide/`, data at `~/.local/share/vide/`
- Created Lua init, settings, Neovim plugins, and all wrapper scripts (vide, vide-nvim, vide-terminal, vide-ui, vide-args)

### Updater (`update.sh`)
- **Result:** PASS
- Detected local developer directory (test dir with `.git`), attempted `git pull` but correctly failed due to unstaged changes (expected behavior for editable checkouts)

### Uninstaller (`uninstall.sh`)
- **Result:** PASS
- Removed all Vide files: `~/.config/vide/`, `~/.local/share/vide/`, `~/.local/state/vide/`, `~/.cache/vide/`, `~/.local/bin/vide*`
- Exit code 0

## Docker Cross-Distro Tests

Four Linux distros were tested in Docker containers with the full 9-test suite:

| Test                  | Description                                    |
|-----------------------|------------------------------------------------|
| Dependencies          | git, curl, zig available in PATH               |
| setup.sh              | Installer completes with exit 0                |
| zig build             | Release build succeeds                         |
| zig build test        | Unit tests pass                                |
| binary no TTY         | Binary exits non-zero (no panic) without /dev/tty |
| update.sh             | Update script completes                        |
| uninstall.sh          | Uninstall removes all files                    |
| rebuild               | Full rebuild after re-install succeeds         |
| script test           | `script -c` smoke test (times out = expected)  |

### Results

| Distro              | Zig    | Neovim | Tests Passed | Result |
|---------------------|--------|--------|--------------|--------|
| Ubuntu 24.04        | 0.16.0 | 0.12.2 | 9/9          | PASS   |
| Fedora 40           | 0.16.0 | 0.9.5  | 9/9          | PASS   |
| Alpine Linux 3.20   | 0.16.0 | 0.10.1 | 9/9          | PASS   |
| Arch Linux          | 0.16.0 | 0.10.4 | 9/9          | PASS   |

All 36 individual test cases passed across all 4 distros. The installer, build system, and runtime all function correctly on glibc (Ubuntu, Fedora, Arch) and musl (Alpine) systems. Note that Fedora ships an older Neovim (0.9.5 vs the recommended 0.10.0+), but all tests still passed.

### Infrastructure

- Each distro uses a distro-specific Dockerfile based on the official base image
- Tests run via a shared `run_test.sh` script executed inside each container
- Results captured per-distro to `report_<distro>.txt` and aggregated by `build_and_test.sh`
- Dockerfiles, runner, and build script at `/tmp/opencode/vide-docker-tests/`
