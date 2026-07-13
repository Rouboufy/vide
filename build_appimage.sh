#!/usr/bin/env bash
set -euo pipefail

VERSION="${VERSION:-$(git describe --tags --always --dirty 2>/dev/null || echo unknown)}"
COMMIT_SHA="${COMMIT_SHA:-$(git rev-parse --short HEAD 2>/dev/null || echo unknown)}"
NEOVIM_VERSION="${NEOVIM_VERSION:-v0.11.6}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"
APP_DIR="${APP_DIR:-$ROOT/Vide.AppDir}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/vide-appimage.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/usr/bin" "$APP_DIR/usr/share/applications" "$APP_DIR/usr/share/metainfo" "$APP_DIR/usr/share/icons/hicolor/scalable/apps" "$OUTPUT_DIR"

echo "Building Vide $VERSION ($COMMIT_SHA) for x86_64-linux-musl..."
ZIG_GLOBAL_CACHE_DIR="${ZIG_GLOBAL_CACHE_DIR:-$WORK_DIR/zig-global}" \
ZIG_LOCAL_CACHE_DIR="${ZIG_LOCAL_CACHE_DIR:-$WORK_DIR/zig-local}" \
zig build -Doptimize=ReleaseFast -Dtarget=x86_64-linux-musl -Dversion="$VERSION" --prefix "$WORK_DIR/vide"
cp "$WORK_DIR/vide/bin/vide" "$APP_DIR/usr/bin/vide"

if [[ -n "${NEOVIM_SOURCE_DIR:-}" ]]; then
    echo "Using Neovim from $NEOVIM_SOURCE_DIR"
    cp "$NEOVIM_SOURCE_DIR/bin/nvim" "$APP_DIR/usr/bin/nvim"
    cp -R "$NEOVIM_SOURCE_DIR/share/nvim" "$APP_DIR/usr/share/"
else
    echo "Downloading bundled Neovim $NEOVIM_VERSION..."
    archive="$WORK_DIR/nvim-linux-x86_64.tar.gz"
    curl -fL --retry 3 -o "$archive" \
        "https://github.com/neovim/neovim/releases/download/$NEOVIM_VERSION/nvim-linux-x86_64.tar.gz"
    tar -xzf "$archive" -C "$WORK_DIR"
    cp "$WORK_DIR/nvim-linux-x86_64/bin/nvim" "$APP_DIR/usr/bin/nvim"
    cp -R "$WORK_DIR/nvim-linux-x86_64/share/nvim" "$APP_DIR/usr/share/"
fi

cp "$ROOT/packaging/AppRun" "$APP_DIR/AppRun"
cp "$ROOT/packaging/vide.desktop" "$APP_DIR/vide.desktop"
cp "$ROOT/packaging/vide.desktop" "$APP_DIR/usr/share/applications/vide.desktop"
cp "$ROOT/packaging/vide.svg" "$APP_DIR/vide.svg"
cp "$ROOT/packaging/vide.svg" "$APP_DIR/usr/share/icons/hicolor/scalable/apps/vide.svg"
cp "$ROOT/packaging/vide.appdata.xml" "$APP_DIR/usr/share/metainfo/io.github.rouboufy.vide.metainfo.xml"
chmod 755 "$APP_DIR/AppRun" "$APP_DIR/usr/bin/vide" "$APP_DIR/usr/bin/nvim"

cat >"$APP_DIR/VERSION.txt" <<EOF
Vide version: $VERSION
Git commit: $COMMIT_SHA
Bundled Neovim: $NEOVIM_VERSION
Architecture: x86_64-linux-musl
EOF

if [[ "${APPIMAGE_APPDIR_ONLY:-0}" == 1 ]]; then
    echo "Prepared AppDir at $APP_DIR"
    exit 0
fi

linuxdeploy="$WORK_DIR/linuxdeploy-x86_64.AppImage"
curl -fL --retry 3 -o "$linuxdeploy" \
    "https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage"
chmod 755 "$linuxdeploy"

echo "Packaging AppImage without requiring FUSE..."
rm -f "$ROOT/Vide-$VERSION-x86_64.AppImage"
ARCH=x86_64 LINUXDEPLOY_OUTPUT_VERSION="$VERSION" "$linuxdeploy" --appimage-extract-and-run --appdir "$APP_DIR" --output appimage
generated="$ROOT/Vide-$VERSION-x86_64.AppImage"
[[ -f "$generated" ]] || { echo "linuxdeploy did not create $generated" >&2; exit 1; }
output="$OUTPUT_DIR/Vide-$VERSION-x86_64.AppImage"
if [[ "$generated" != "$output" ]]; then mv "$generated" "$output"; fi
chmod 755 "$output"
sha256sum "$output" >"$output.sha256"
echo "Created $output and $output.sha256"
