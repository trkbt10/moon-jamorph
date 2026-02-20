#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
PKG_DIR="$ROOT_DIR/cmd/wasm_api"
WASM_SRC="$ROOT_DIR/_build/wasm/release/build/cmd/wasm_api/wasm_api.wasm"
WASM_DST_DIR="$ROOT_DIR/npm/micado-wasm/dist"
WASM_DST="$WASM_DST_DIR/micado_wasm.wasm"
WEB_SMALL_TSV="$ROOT_DIR/tools/dict-compiler/.cache/web-small/ipadic_web_small.tsv"
WEB_SMALL_BIN="$WASM_DST_DIR/micado_web_small.dic.bin"
WEB_SMALL_LIMIT="${WEB_SMALL_LIMIT:-8000}"

moon build -C "$ROOT_DIR" --target wasm "$PKG_DIR"
mkdir -p "$WASM_DST_DIR"
cp "$WASM_SRC" "$WASM_DST"

if [[ ! -f "$WEB_SMALL_TSV" ]]; then
  "$ROOT_DIR/tools/dict-compiler/scripts/build_web_small_tsv.sh" "$WEB_SMALL_LIMIT"
fi

node "$ROOT_DIR/tools/dict-compiler/scripts/build_web_dic_bin.mjs" \
  "$WEB_SMALL_TSV" \
  "$WEB_SMALL_BIN" \
  --limit "$WEB_SMALL_LIMIT"

echo "[build_wasm_npm] copied: $WASM_DST"
ls -lh "$WASM_DST"
echo "[build_wasm_npm] built:  $WEB_SMALL_BIN"
ls -lh "$WEB_SMALL_BIN"
