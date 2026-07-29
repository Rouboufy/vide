#!/bin/sh
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/vide-launcher.XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT HUP INT TERM

mkdir -p "$TEST_DIR/runtime/bin" "$TEST_DIR/runtime/lib/vide/nvim/bin"
cp "$ROOT/packaging/vide-launcher" "$TEST_DIR/runtime/bin/vide"
chmod 755 "$TEST_DIR/runtime/bin/vide"
ln -s "$(command -v env)" "$TEST_DIR/runtime/lib/vide/vide"
ln -s "$TEST_DIR/runtime/bin/vide" "$TEST_DIR/vide"

OUTPUT=$("$TEST_DIR/vide")
EXPECTED_RUNTIME=$TEST_DIR/runtime/bin/../lib/vide

printf '%s\n' "$OUTPUT" | grep -Fqx "VIMRUNTIME=$EXPECTED_RUNTIME/nvim/share/nvim/runtime"
printf '%s\n' "$OUTPUT" | grep -Fqx "PATH=$EXPECTED_RUNTIME/nvim/bin:$PATH"

echo "Launcher symlink smoke test passed."
