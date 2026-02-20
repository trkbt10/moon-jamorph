#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
WASM_DST_DIR="$ROOT_DIR/npm/micado-wasm/dist"
WEB_SMALL_TSV="$ROOT_DIR/tools/dict-compiler/.cache/web-small/ipadic_web_small.tsv"
WEB_SMALL_BIN="$WASM_DST_DIR/micado_web_small.dic.bin"
WEB_SMALL_LIMIT="${WEB_SMALL_LIMIT:-8000}"

mkdir -p "$WASM_DST_DIR"

if [[ ! -f "$WEB_SMALL_TSV" ]]; then
  "$ROOT_DIR/tools/dict-compiler/scripts/build_web_small_tsv.sh" "$WEB_SMALL_LIMIT"
fi

node "$ROOT_DIR/tools/dict-compiler/scripts/build_web_dic_bin.mjs" \
  "$WEB_SMALL_TSV" \
  "$WEB_SMALL_BIN" \
  --limit "$WEB_SMALL_LIMIT"

echo "[build_wasm_npm] built: $WEB_SMALL_BIN"
ls -lh "$WEB_SMALL_BIN"
