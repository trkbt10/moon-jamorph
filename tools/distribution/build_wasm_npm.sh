#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
PKG_DIR="$ROOT_DIR/cmd/wasm_api"
WASM_SRC="$ROOT_DIR/_build/wasm/release/build/cmd/wasm_api/wasm_api.wasm"
WASM_DST_DIR="$ROOT_DIR/npm/micado-wasm/dist"
WASM_DST="$WASM_DST_DIR/micado_wasm.wasm"

moon build -C "$ROOT_DIR" --target wasm "$PKG_DIR"
mkdir -p "$WASM_DST_DIR"
cp "$WASM_SRC" "$WASM_DST"

echo "[build_wasm_npm] copied: $WASM_DST"
ls -lh "$WASM_DST"
