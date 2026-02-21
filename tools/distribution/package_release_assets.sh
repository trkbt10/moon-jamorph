#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
RELEASE_DIR="$ROOT_DIR/_build/release"
MOON_MOD_JSON="$ROOT_DIR/moon.mod.json"
WASM_PKG_JSON="$ROOT_DIR/npm/micado-wasm/package.json"
WASM_DIST_DIR="$ROOT_DIR/npm/micado-wasm/dist"

if ! command -v node >/dev/null 2>&1; then
  echo "[release] error: node command is required" >&2
  exit 1
fi

module_name="$(node -e 'const fs=require("fs");const j=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));process.stdout.write(j.name||"")' "$MOON_MOD_JSON")"
module_version="$(node -e 'const fs=require("fs");const j=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));process.stdout.write(j.version||"")' "$MOON_MOD_JSON")"
wasm_version="$(node -e 'const fs=require("fs");const j=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));process.stdout.write(j.version||"")' "$WASM_PKG_JSON")"

if [[ -z "$module_name" || -z "$module_version" ]]; then
  echo "[release] error: invalid moon.mod.json (name/version)" >&2
  exit 1
fi
if [[ -z "$wasm_version" ]]; then
  echo "[release] error: invalid npm/micado-wasm/package.json (version)" >&2
  exit 1
fi

mkdir -p "$RELEASE_DIR"

module_name_tag="$(printf '%s' "$module_name" | tr '/' '-')"
module_zip_src="$ROOT_DIR/_build/publish/${module_name_tag}-${module_version}.zip"
module_zip_dst="$RELEASE_DIR/${module_name_tag}-moon-module-v${module_version}.zip"

wasm_profiles_default="tiny mini medium micado_web_small full"
wasm_profiles_raw="${WASM_RELEASE_PROFILES:-$wasm_profiles_default}"
wasm_profiles="$(printf '%s' "$wasm_profiles_raw" | tr ',' ' ')"
include_raw_dic="${WASM_RELEASE_INCLUDE_RAW_DIC:-0}"

if [[ "$include_raw_dic" != "0" && "$include_raw_dic" != "1" ]]; then
  echo "[release] error: WASM_RELEASE_INCLUDE_RAW_DIC must be 0 or 1" >&2
  exit 1
fi

echo "[release] building moon package (CLI/core)"
moon package

if [[ ! -f "$module_zip_src" ]]; then
  echo "[release] error: expected moon package not found: $module_zip_src" >&2
  exit 1
fi
cp "$module_zip_src" "$module_zip_dst"

echo "[release] building wasm artifacts"
"$ROOT_DIR/tools/distribution/build_wasm_npm.sh"

if [[ ! -d "$WASM_DIST_DIR" ]]; then
  echo "[release] error: wasm dist directory not found: $WASM_DIST_DIR" >&2
  exit 1
fi

stage_dir="$(mktemp -d "${TMPDIR:-/tmp}/micado-release.XXXXXX")"
cleanup() {
  rm -rf "$stage_dir"
}
trap cleanup EXIT

mkdir -p "$stage_dir/package"
cp "$ROOT_DIR/npm/micado-wasm/package.json" "$stage_dir/package/package.json"
cp "$ROOT_DIR/npm/micado-wasm/README.md" "$stage_dir/package/README.md"
cp "$ROOT_DIR/LICENSE" "$stage_dir/package/LICENSE"
cp -R "$WASM_DIST_DIR" "$stage_dir/package/dist"

find "$stage_dir/package/dist" -maxdepth 1 -type f \
  \( -name '*.dic.bin' -o -name '*.dic.bin.deflate' \) -delete

if [[ -f "$WASM_DIST_DIR/LICENSE.dic.bin" ]]; then
  cp "$WASM_DIST_DIR/LICENSE.dic.bin" "$stage_dir/package/dist/LICENSE.dic.bin"
fi

for profile in $wasm_profiles; do
  if [[ -z "$profile" ]]; then
    continue
  fi
  src_deflate="$WASM_DIST_DIR/${profile}.dic.bin.deflate"
  if [[ ! -f "$src_deflate" ]]; then
    echo "[release] error: missing profile dictionary: $src_deflate" >&2
    exit 1
  fi
  cp "$src_deflate" "$stage_dir/package/dist/${profile}.dic.bin.deflate"

  if [[ "$include_raw_dic" == "1" ]]; then
    src_raw="$WASM_DIST_DIR/${profile}.dic.bin"
    if [[ ! -f "$src_raw" ]]; then
      echo "[release] error: missing raw profile dictionary: $src_raw" >&2
      exit 1
    fi
    cp "$src_raw" "$stage_dir/package/dist/${profile}.dic.bin"
  fi
done

manifest="$stage_dir/package/RELEASE-MANIFEST.txt"
{
  echo "module_name=${module_name}"
  echo "module_version=${module_version}"
  echo "wasm_version=${wasm_version}"
  echo "wasm_profiles=${wasm_profiles}"
  echo "include_raw_dic=${include_raw_dic}"
} > "$manifest"

wasm_archive="$RELEASE_DIR/micado-wasm-with-dic-v${wasm_version}.tar.gz"
tar -C "$stage_dir" -czf "$wasm_archive" package

echo "[release] created artifacts:"
ls -lh "$module_zip_dst" "$wasm_archive"
echo "[release] wasm dictionary files in archive:"
tar -tzf "$wasm_archive" | grep -E 'package/dist/.*\.dic\.bin(\.deflate)?$' || true
