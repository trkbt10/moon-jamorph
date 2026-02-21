#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
PKG_DIR="cmd/wasm_api"
MOON_TARGET_DIR="$ROOT_DIR/_build"
WASM_DST_DIR="$ROOT_DIR/npm/micado-wasm/dist"
WASM_DST="$WASM_DST_DIR/micado_wasm.wasm"

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

mkdir -p "$WASM_DST_DIR"

if moon build --help | grep -q -- '--manifest-path'; then
  moon build \
    --manifest-path "$ROOT_DIR/moon.mod.json" \
    --target-dir "$MOON_TARGET_DIR" \
    --target wasm \
    "$PKG_DIR"
else
  moon build -C "$ROOT_DIR" --target wasm "$PKG_DIR"
fi

WASM_SRC=""
if [[ -d "$MOON_TARGET_DIR" ]]; then
  wasm_candidates="$(find "$MOON_TARGET_DIR" -type f -name 'wasm_api.wasm' 2>/dev/null || true)"
  if [[ -n "$wasm_candidates" ]]; then
    WASM_SRC="$(
      printf '%s\n' "$wasm_candidates" | grep '/wasm/' | head -n 1 || true
    )"
    if [[ -z "$WASM_SRC" ]]; then
      WASM_SRC="$(printf '%s\n' "$wasm_candidates" | head -n 1)"
    fi
  fi
fi
if [[ -z "$WASM_SRC" || ! -f "$WASM_SRC" ]]; then
  echo "[build_wasm_npm] error: wasm output not found under $MOON_TARGET_DIR" >&2
  if [[ -d "$MOON_TARGET_DIR" ]]; then
    find "$MOON_TARGET_DIR" -maxdepth 8 -type f -name '*.wasm' -print || true
  fi
  exit 1
fi
cp "$WASM_SRC" "$WASM_DST"

args=(
  --out-dir "$WASM_DST_DIR"
  --tiny-limit "$WEB_DIC_TINY_LIMIT"
  --mini-limit "$WEB_DIC_MINI_LIMIT"
  --medium-limit "$WEB_DIC_MEDIUM_LIMIT"
  --full-limit "$WEB_DIC_FULL_LIMIT"
)
if [[ -f "$WEB_FREQ_TSV" ]]; then
  args+=(--freq-tsv "$WEB_FREQ_TSV")
fi
node "$ROOT_DIR/tools/dict-compiler/scripts/build_web_dic_artifacts.mjs" "${args[@]}"

echo "[build_wasm_npm] copied: $WASM_DST"
ls -lh "$WASM_DST"
if [[ -f "$WEB_FREQ_TSV" ]]; then
  echo "[build_wasm_npm] frequency source: $WEB_FREQ_TSV"
fi
echo "[build_wasm_npm] generated dictionary profiles under: $WASM_DST_DIR"
ls -lh "$WASM_DST_DIR"/*.dic.bin "$WASM_DST_DIR"/*.dic.bin.deflate
