#!/usr/bin/env bash
set -euo pipefail

check_plan() {
    local platform=$1 manager=$2 expected=$3
    local output
    output=$(VIDE_TEST_PLATFORM="$platform" VIDE_TEST_PACKAGE_MANAGER="$manager" \
        VIDE_TEST_MISSING="curl nvim git" VIDE_TEST_ONLY=1 \
        bash setup.sh --dry-run --yes --no-plugins)
    grep -Fq "$expected" <<< "$output"
    grep -Fq "curl neovim git" <<< "$output"
}

check_plan Linux apt "apt-get install"
check_plan Linux pacman "pacman -S"
check_plan Linux dnf "dnf install"
check_plan Linux zypper "zypper install"
check_plan Darwin brew "brew install"

wsl_output=$(VIDE_TEST_PLATFORM=Linux VIDE_TEST_PACKAGE_MANAGER=apt VIDE_TEST_WSL=1 \
    VIDE_TEST_MISSING="curl nvim git" VIDE_TEST_ONLY=1 \
    bash setup.sh --dry-run --yes --no-plugins)
grep -Fq "WSL path detected" <<< "$wsl_output"

check_asset() {
    local platform=$1 arch=$2 expected=$3
    local output
    output=$(VIDE_TEST_PLATFORM="$platform" VIDE_TEST_ARCH="$arch" \
        VIDE_TEST_MISSING="" VIDE_TEST_ONLY=release bash setup.sh)
    [ "$output" = "$expected" ]
}

check_asset Linux x86_64 vide-linux-x86_64.tar.gz
check_asset Linux aarch64 vide-linux-aarch64.tar.gz
check_asset Darwin x86_64 vide-macos-x86_64.tar.gz
check_asset Darwin arm64 vide-macos-aarch64.tar.gz

progress_file=$(mktemp "${TMPDIR:-/tmp}/vide-setup-progress.XXXXXX")
fixture_dir=$(mktemp -d "${TMPDIR:-/tmp}/vide-setup-tests.XXXXXX")
trap 'rm -f "$progress_file"; rm -rf "$fixture_dir"' EXIT
VIDE_TEST_PLATFORM=Linux VIDE_TEST_ARCH=x86_64 VIDE_UPDATE_PROGRESS_FILE="$progress_file" \
    bash setup.sh --dry-run --no-plugins >/dev/null
grep -Fxq 72 "$progress_file"

# Simulate macOS with Homebrew installed outside PATH and a broken system Git
# shim. No host package manager or network access is used.
bash_bin=$(command -v bash)
mkdir -p "$fixture_dir/bin" "$fixture_dir/homebrew/bin"
ln -s "$(command -v uname)" "$fixture_dir/bin/uname"
printf '#!/bin/sh\nexit 0\n' > "$fixture_dir/bin/curl"
printf '#!/bin/sh\nexit 1\n' > "$fixture_dir/bin/git"
printf '#!/bin/sh\nexit 0\n' > "$fixture_dir/homebrew/bin/brew"
chmod +x "$fixture_dir/bin/curl" "$fixture_dir/bin/git" "$fixture_dir/homebrew/bin/brew"
brew_output=$(PATH="$fixture_dir/bin" HOMEBREW_PREFIX="$fixture_dir/homebrew" \
    VIDE_TEST_PLATFORM=Darwin VIDE_TEST_ARCH=arm64 VIDE_TEST_ONLY=1 \
    "$bash_bin" setup.sh --dry-run --yes)
grep -Fq 'brew install git' <<< "$brew_output"
! grep -Fq neovim <<< "$brew_output"

no_plugins_output=$(PATH="$fixture_dir/bin" HOMEBREW_PREFIX="$fixture_dir/homebrew" \
    VIDE_TEST_PLATFORM=Darwin VIDE_TEST_ARCH=arm64 VIDE_TEST_ONLY=1 \
    "$bash_bin" setup.sh --dry-run --yes --no-plugins)
[ -z "$no_plugins_output" ]

# Homebrew-provided dependencies must be visible before probing for them.
printf '#!/bin/sh\nexit 0\n' > "$fixture_dir/homebrew/bin/git"
chmod +x "$fixture_dir/homebrew/bin/git"
installed_output=$(PATH="$fixture_dir/bin" HOMEBREW_PREFIX="$fixture_dir/homebrew" \
    VIDE_TEST_PLATFORM=Darwin VIDE_TEST_ARCH=arm64 VIDE_TEST_ONLY=1 \
    "$bash_bin" setup.sh --dry-run --yes)
[ -z "$installed_output" ]

bootstrap_output=$(VIDE_TEST_PLATFORM=Darwin VIDE_TEST_ARCH=arm64 \
    XDG_DATA_HOME="$fixture_dir/data" bash setup.sh --dry-run --yes)
grep -Fq "$fixture_dir/data/vide/runtime/lib/vide/nvim/bin/nvim --clean --headless" <<< "$bootstrap_output"
grep -Fq vide-macos-aarch64.tar.gz <<< "$bootstrap_output"

echo "Installer package-manager and release-asset plans passed"
