# AppImage packaging and verification

Vide's x86-64 AppImage contains Vide, Neovim 0.11.6, Neovim's runtime,
desktop metadata, an SVG icon, and AppStream metadata. It does not require host
Neovim. User data still uses Vide's isolated XDG directories outside the
read-only image.

Tagged releases publish `Vide-<version>-x86_64.AppImage`, its neighboring
`.sha256`, and the release-wide `SHA256SUMS`. `VERSION.txt` records the Vide
version, Git commit, architecture, and bundled Neovim version.

## Reproduce and verify

```bash
VERSION=1.2.3 COMMIT_SHA=$(git rev-parse HEAD) bash build_appimage.sh
sha256sum -c Vide-1.2.3-x86_64.AppImage.sha256
./Vide-1.2.3-x86_64.AppImage --appimage-extract-and-run --version
tests/appimage_smoke.sh Vide.AppDir
```

The extraction flag works without FUSE. The smoke test checks bundled assets,
Neovim discovery without `PATH`, version metadata, all editing modes, paste,
mouse input, resize, terminal cleanup, and temporary isolated XDG paths.

## Recorded smoke tests

| Distribution | Date | Result |
| --- | --- | --- |
| Arch Linux x86-64 | 2026-07-13 | Full AppDir PTY suite and final checksum/version passed |
| Ubuntu 24.04 x86-64 | 2026-07-13 | Final image started without FUSE or host Neovim |
| Debian 12 slim x86-64 | 2026-07-13 | Final image started without FUSE or host Neovim |
