#!/usr/bin/env bash
set -euo pipefail

appdir=${1:-Vide.AppDir}
[[ -x "$appdir/AppRun" ]]
[[ -x "$appdir/usr/bin/vide" ]]
[[ -x "$appdir/usr/bin/nvim" ]]
[[ -f "$appdir/usr/share/nvim/runtime/doc/help.txt" ]]
[[ -f "$appdir/vide.desktop" ]]
[[ -f "$appdir/vide.svg" ]]
[[ -f "$appdir/usr/share/applications/vide.desktop" ]]
[[ -f "$appdir/usr/share/metainfo/vide.appdata.xml" ]]
[[ -f "$appdir/VERSION.txt" ]]
grep -Fq 'Bundled Neovim:' "$appdir/VERSION.txt"
grep -Fq 'Icon=vide' "$appdir/vide.desktop"
grep -Fq 'Terminal=true' "$appdir/vide.desktop"

version=$("$appdir/AppRun" --version)
grep -Eq '^vide [^[:space:]]+$' <<<"$version"
PATH=/nonexistent "$appdir/usr/bin/nvim" --clean --headless +'quit' >/dev/null

VIDE_TEST_BINARY="$appdir/AppRun" VIDE_TEST_SKIP_STARTUP_FAILURE=1 python3 tests/pty_integration.py
echo "AppImage AppDir smoke tests passed"
