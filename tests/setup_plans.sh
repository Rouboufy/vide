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

echo "Installer package-manager and release-asset plans passed"
