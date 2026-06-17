#!/usr/bin/env bash
set -euo pipefail

APP_DIR="Vide.AppDir"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/usr/bin"

# Build Vide targeting x86_64-v3 (AVX2, no AVX-512) for compatibility
echo "Building Vide (x86_64-v3)..."
zig build -Doptimize=ReleaseFast -Dtarget=x86_64-linux-gnu -Dcpu=x86_64_v3

# Copy compiled vide binary
cp zig-out/bin/vide "$APP_DIR/usr/bin/vide"

# Download precompiled Neovim stable release
echo "Downloading bundled Neovim..."
curl -LO https://github.com/neovim/neovim/releases/download/stable/nvim-linux-x86_64.tar.gz
tar -xzf nvim-linux-x86_64.tar.gz
cp nvim-linux-x86_64/bin/nvim "$APP_DIR/usr/bin/nvim"
mkdir -p "$APP_DIR/usr/share"
cp -r nvim-linux-x86_64/share/nvim "$APP_DIR/usr/share/"
rm -rf nvim-linux-x86_64 nvim-linux-x86_64.tar.gz

# Create desktop entry file
cat << 'EOF' > "$APP_DIR/vide.desktop"
[Desktop Entry]
Type=Application
Name=Vide
Comment=Vibrant TUI Neovim Frontend and IDE
Exec=vide %F
Icon=vide
Terminal=true
Categories=Development;TextEditor;ConsoleOnly;
MimeType=text/plain;
EOF

# Create AppRun launcher
cat << 'EOF' > "$APP_DIR/AppRun"
#!/bin/bash
SELF=$(readlink -f "$0")
HERE=${SELF%/*}
export PATH="$HERE/usr/bin:$PATH"
export VIMRUNTIME="$HERE/usr/share/nvim/runtime"
exec "$HERE/usr/bin/vide" "$@"
EOF
chmod +x "$APP_DIR/AppRun"

# Create a placeholder icon
touch "$APP_DIR/vide.png"

# Download linuxdeploy if not present
if [ ! -f linuxdeploy-x86_64.AppImage ]; then
  echo "Downloading linuxdeploy..."
  curl -LO https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage
  chmod +x linuxdeploy-x86_64.AppImage
fi

# Run linuxdeploy to package it
echo "Packaging AppImage..."
export ARCH=x86_64
./linuxdeploy-x86_64.AppImage --appdir "$APP_DIR" --output appimage
