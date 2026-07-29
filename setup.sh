#!/usr/bin/env bash

set -euo pipefail

REPO="Rouboufy/vide"
ZIG_VERSION="0.16.0"
DRY_RUN=false
NO_PLUGINS=false
SOURCE_BUILD=false
ASSUME_YES=false
RELEASE_ASSET=""

usage() {
    cat <<'EOF'
Usage: setup.sh [options]

Options:
  --dry-run       Print the actions that would be taken without changing files.
  --no-plugins    Skip the headless Neovim plugin bootstrap.
  --source        Build from source instead of installing a release binary.
  --yes           Allow dependency installation without an interactive prompt.
  -h, --help      Show this help.

Without a terminal, missing system dependencies cause installation to stop unless
--yes is supplied. Existing Vide settings and plugin data are never removed.
EOF
}

for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=true ;;
        --no-plugins) NO_PLUGINS=true ;;
        --source) SOURCE_BUILD=true ;;
        --yes) ASSUME_YES=true ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $arg" >&2; usage >&2; exit 2 ;;
    esac
done

run() {
    printf '+ '
    printf '%q ' "$@"
    printf '\n'
    if ! $DRY_RUN; then
        "$@"
    fi
}

report_update_progress() {
    local percent=$1
    local progress_file="${VIDE_UPDATE_PROGRESS_FILE:-}"
    [ -n "$progress_file" ] || return 0
    local progress_tmp="${progress_file}.tmp.$$"
    printf '%s\n' "$percent" >"$progress_tmp"
    mv -f "$progress_tmp" "$progress_file"
}

version_at_least() {
    [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1)" = "$2" ]
}

OS_NAME="${VIDE_TEST_PLATFORM:-$(uname -s)}"
ARCH="${VIDE_TEST_ARCH:-$(uname -m)}"
IS_WSL=false
if [ "${VIDE_TEST_WSL:-0}" = 1 ] || { [ "$OS_NAME" = Linux ] && rg -qi microsoft /proc/version 2>/dev/null; }; then
    IS_WSL=true
fi

declare -a MISSING=()
if [ -n "${VIDE_TEST_MISSING:-}" ]; then
    read -r -a MISSING <<< "$VIDE_TEST_MISSING"
else
    command -v curl >/dev/null 2>&1 || MISSING+=("curl")
    if $SOURCE_BUILD && command -v nvim >/dev/null 2>&1; then
        NVIM_VERSION="$(nvim --version | head -n1 | awk '{gsub(/^v/, "", $2); print $2}')"
        version_at_least "$NVIM_VERSION" 0.10.0 || MISSING+=("neovim>=0.10.0")
    fi
    if $SOURCE_BUILD; then
        command -v nvim >/dev/null 2>&1 || MISSING+=("neovim>=0.10.0")
        command -v git >/dev/null 2>&1 || MISSING+=("git")
        if ! command -v zig >/dev/null 2>&1 || [ "$(zig version)" != "$ZIG_VERSION" ]; then
            echo "Source builds require Zig $ZIG_VERSION exactly. Install it from https://ziglang.org/download/ and retry." >&2
            exit 1
        fi
    fi
fi

install_dependencies() {
    declare -a packages=()
    for dependency in "${MISSING[@]}"; do
        case "$dependency" in
            curl) packages+=("curl") ;;
            nvim|neovim*) packages+=("neovim") ;;
            git) packages+=("git") ;;
            *) echo "No automatic package mapping for $dependency" >&2; exit 1 ;;
        esac
    done

    local manager="${VIDE_TEST_PACKAGE_MANAGER:-}"
    if [ "$OS_NAME" = Linux ]; then
        if [ "$manager" = apt ] || { [ -z "$manager" ] && command -v apt-get >/dev/null 2>&1; }; then
            run sudo apt-get update
            run sudo apt-get install -y "${packages[@]}"
        elif [ "$manager" = pacman ] || { [ -z "$manager" ] && command -v pacman >/dev/null 2>&1; }; then
            run sudo pacman -S --needed --noconfirm "${packages[@]}"
        elif [ "$manager" = dnf ] || { [ -z "$manager" ] && command -v dnf >/dev/null 2>&1; }; then
            run sudo dnf install -y "${packages[@]}"
        elif [ "$manager" = zypper ] || { [ -z "$manager" ] && command -v zypper >/dev/null 2>&1; }; then
            run sudo zypper install -y "${packages[@]}"
        else
            echo "No supported package manager found; install: ${MISSING[*]}" >&2
            exit 1
        fi
    elif [ "$OS_NAME" = Darwin ] && { [ "$manager" = brew ] || { [ -z "$manager" ] && command -v brew >/dev/null 2>&1; }; }; then
        run brew install "${packages[@]}"
    else
        echo "Automatic dependency installation is unavailable; install: ${MISSING[*]}" >&2
        exit 1
    fi
}

if [ ${#MISSING[@]} -gt 0 ]; then
    echo "Missing or unsupported dependencies: ${MISSING[*]}"
    if ! $ASSUME_YES; then
        if [ ! -r /dev/tty ]; then
            echo "Noninteractive installation will not change system packages. Re-run with --yes or install dependencies manually." >&2
            exit 1
        fi
        read -r -p "Install system dependencies now? [y/N] " reply </dev/tty
        [[ "$reply" =~ ^[Yy]$ ]] || exit 1
    fi
    install_dependencies
fi

release_asset() {
    case "$OS_NAME/$ARCH" in
        Linux/x86_64|Linux/amd64) printf '%s' "vide-linux-x86_64.tar.gz" ;;
        Linux/aarch64|Linux/arm64) printf '%s' "vide-linux-aarch64.tar.gz" ;;
        Darwin/x86_64|Darwin/amd64) printf '%s' "vide-macos-x86_64.tar.gz" ;;
        Darwin/aarch64|Darwin/arm64) printf '%s' "vide-macos-aarch64.tar.gz" ;;
        *) return 1 ;;
    esac
}

hash_file() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

if [ "${VIDE_TEST_ONLY:-0}" = release ]; then
    release_asset || { echo "unsupported: $OS_NAME/$ARCH"; exit 1; }
    exit 0
fi

if [ "${VIDE_TEST_ONLY:-0}" = 1 ]; then
    $IS_WSL && echo "WSL path detected"
    exit 0
fi

CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}/vide"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/vide"
STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}/vide"
CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}/vide"
BIN_DIR="$HOME/.local/bin"
run mkdir -p "$CONFIG_HOME" "$DATA_HOME" "$STATE_HOME" "$CACHE_HOME" "$BIN_DIR"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$SCRIPT_DIR"

if ! $SOURCE_BUILD; then
    RELEASE_ASSET="$(release_asset)" || {
        echo "No release binary is published for $OS_NAME/$ARCH. Re-run with --source." >&2
        exit 1
    }
    RELEASE_BASE="https://github.com/$REPO/releases/latest/download"
    if $DRY_RUN; then
        DOWNLOAD_DIR="${TMPDIR:-/tmp}/vide-install.dry-run"
    else
        DOWNLOAD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/vide-install.XXXXXX")"
        trap 'rm -rf "$DOWNLOAD_DIR"' EXIT
    fi
    report_update_progress 30
    run curl -fL --retry 3 -o "$DOWNLOAD_DIR/$RELEASE_ASSET" "$RELEASE_BASE/$RELEASE_ASSET"
    report_update_progress 65
    run curl -fL --retry 3 -o "$DOWNLOAD_DIR/SHA256SUMS" "$RELEASE_BASE/SHA256SUMS"
    report_update_progress 72
    if ! $DRY_RUN; then
        expected="$(awk -v asset="$RELEASE_ASSET" '$2 == asset || $2 == "./" asset { print $1; exit }' "$DOWNLOAD_DIR/SHA256SUMS")"
        [ -n "$expected" ] || { echo "Release checksum is missing for $RELEASE_ASSET." >&2; exit 1; }
        actual="$(hash_file "$DOWNLOAD_DIR/$RELEASE_ASSET")"
        [ "$actual" = "$expected" ] || { echo "Checksum verification failed for $RELEASE_ASSET." >&2; exit 1; }
        report_update_progress 80
        tar -xzf "$DOWNLOAD_DIR/$RELEASE_ASSET" -C "$DOWNLOAD_DIR"
        BUNDLE_DIR="$DOWNLOAD_DIR/${RELEASE_ASSET%.tar.gz}"
        [ -x "$BUNDLE_DIR/bin/vide" ] || { echo "Release bundle is invalid." >&2; exit 1; }
        report_update_progress 88
        INSTALL_DIR="$DATA_HOME/runtime"
        BACKUP_DIR="$DATA_HOME/runtime.previous"
        rm -rf "$BACKUP_DIR"
        if [ -e "$INSTALL_DIR" ]; then mv "$INSTALL_DIR" "$BACKUP_DIR"; fi
        mv "$BUNDLE_DIR" "$INSTALL_DIR"
        ln -sfn "$INSTALL_DIR/bin/vide" "$BIN_DIR/vide"
        report_update_progress 98
        rm -rf "$BACKUP_DIR"
    else
        echo "+ verify SHA256SUMS for $RELEASE_ASSET"
        echo "+ install bundled Neovim runtime from $RELEASE_ASSET"
        echo "+ link $BIN_DIR/vide to its private launcher"
    fi
else
    if [ ! -f "$SOURCE_DIR/build.zig" ]; then
        SOURCE_DIR="$DATA_HOME/repo"
        if [ -d "$SOURCE_DIR/.git" ]; then
            run git -C "$SOURCE_DIR" pull --ff-only
        else
            run git clone --depth 1 "https://github.com/$REPO.git" "$SOURCE_DIR"
        fi
    fi
    if ! $DRY_RUN; then
        [ "$(zig version)" = "$ZIG_VERSION" ] || {
            echo "Source builds require Zig $ZIG_VERSION exactly; found $(zig version)." >&2
            exit 1
        }
    fi
    report_update_progress 30
    run zig build --build-file "$SOURCE_DIR/build.zig" -Doptimize=ReleaseFast --prefix "$SOURCE_DIR/zig-out"
    report_update_progress 90
    run ln -sfn "$SOURCE_DIR/zig-out/bin/vide" "$BIN_DIR/vide"
    report_update_progress 98
fi

if ! $NO_PLUGINS; then
    INIT_PATH="$SOURCE_DIR/src/nvim/vide_init.lua"
    if [ -f "$INIT_PATH" ]; then
        echo "Bootstrapping optional Neovim plugins..."
        if ! $DRY_RUN; then
            NVIM_APPNAME=vide VIDE_INIT_PATH="$INIT_PATH" nvim --clean --headless \
                -c "execute 'luafile ' .. fnameescape(\$VIDE_INIT_PATH)" -c "Lazy! sync" -c qa
        fi
    else
        echo "Plugin bootstrap deferred until first launch (release install has no source checkout)."
    fi
fi

$IS_WSL && echo "WSL detected; clipboard and terminal behavior depend on Windows Terminal and WSL integration."
if $DRY_RUN; then
    echo "Dry run complete; no files or packages were changed."
else
    report_update_progress 100
    echo "Vide installed at $BIN_DIR/vide"
fi
[[ ":$PATH:" = *":$BIN_DIR:"* ]] || echo "Add $BIN_DIR to PATH."
