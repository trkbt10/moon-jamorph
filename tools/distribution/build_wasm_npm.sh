#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
PKG_DIR="$ROOT_DIR/cmd/wasm_api"
WASM_SRC="$ROOT_DIR/_build/wasm/release/build/cmd/wasm_api/wasm_api.wasm"
WASM_DST_DIR="$ROOT_DIR/npm/micado-wasm/dist"
WASM_DST="$WASM_DST_DIR/micado_wasm.wasm"
WEB_TSV="$ROOT_DIR/tools/dict-compiler/.cache/web-small/ipadic_web_small.tsv"

WEB_DIC_TINY_LIMIT="${WEB_DIC_TINY_LIMIT:-1500}"
WEB_DIC_MINI_LIMIT="${WEB_DIC_MINI_LIMIT:-5000}"
WEB_DIC_MEDIUM_LIMIT="${WEB_DIC_MEDIUM_LIMIT:-12000}"
WEB_DIC_FULL_LIMIT="${WEB_DIC_FULL_LIMIT:-999999999}"
WEB_FREQ_DEFAULT_AOZORAHACK="$ROOT_DIR/tools/dict-compiler/resources/aozorahack.freq.tsv"
WEB_FREQ_DEFAULT_EXAMPLES="$ROOT_DIR/tools/dict-compiler/resources/aozora_examples.freq.tsv"
WEB_FREQ_TSV="${WEB_FREQ_TSV:-$WEB_FREQ_DEFAULT_AOZORAHACK}"
if [[ ! -f "$WEB_FREQ_TSV" && -f "$WEB_FREQ_DEFAULT_EXAMPLES" ]]; then
  WEB_FREQ_TSV="$WEB_FREQ_DEFAULT_EXAMPLES"
fi

max_limit="$WEB_DIC_TINY_LIMIT"
for limit in "$WEB_DIC_MINI_LIMIT" "$WEB_DIC_MEDIUM_LIMIT" "$WEB_DIC_FULL_LIMIT"; do
  if (( limit > max_limit )); then
    max_limit="$limit"
  fi
done

mkdir -p "$WASM_DST_DIR"

moon build -C "$ROOT_DIR" --target wasm "$PKG_DIR"
cp "$WASM_SRC" "$WASM_DST"

"$ROOT_DIR/tools/dict-compiler/scripts/build_web_small_tsv.sh" "$max_limit"

build_profile() {
  local profile="$1"
  local limit="$2"
  local bin_path="$WASM_DST_DIR/$profile.dic.bin"
  local deflate_path="$bin_path.deflate"
  local args=(
    "$WEB_TSV"
    "$bin_path"
    --limit "$limit"
  )
  if [[ -f "$WEB_FREQ_TSV" ]]; then
    args+=(--freq-tsv "$WEB_FREQ_TSV")
  fi

  node "$ROOT_DIR/tools/dict-compiler/scripts/build_web_dic_bin.mjs" "${args[@]}"

  node "$ROOT_DIR/tools/dict-compiler/scripts/compress_dic_bin_deflate.mjs" \
    "$bin_path" \
    "$deflate_path"
}

build_profile tiny "$WEB_DIC_TINY_LIMIT"
build_profile mini "$WEB_DIC_MINI_LIMIT"
build_profile medium "$WEB_DIC_MEDIUM_LIMIT"
build_profile full "$WEB_DIC_FULL_LIMIT"

cp "$WASM_DST_DIR/medium.dic.bin" "$WASM_DST_DIR/micado_web_small.dic.bin"
cp "$WASM_DST_DIR/medium.dic.bin.deflate" "$WASM_DST_DIR/micado_web_small.dic.bin.deflate"

echo "[build_wasm_npm] copied: $WASM_DST"
ls -lh "$WASM_DST"
if [[ -f "$WEB_FREQ_TSV" ]]; then
  echo "[build_wasm_npm] frequency source: $WEB_FREQ_TSV"
fi
echo "[build_wasm_npm] generated dictionary profiles under: $WASM_DST_DIR"
ls -lh "$WASM_DST_DIR"/*.dic.bin "$WASM_DST_DIR"/*.dic.bin.deflate
