#!/usr/bin/env bash
# Synchronize version from moon.mod.json to all package.json files
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
MOON_MOD="$ROOT_DIR/moon.mod.json"

VERSION="$(jq -r '.version' "$MOON_MOD")"

if [[ -z "$VERSION" || "$VERSION" == "null" ]]; then
  echo "[sync_versions] error: could not read version from $MOON_MOD" >&2
  exit 1
fi

echo "[sync_versions] source version: $VERSION"

sync_package() {
  local pkg="$1"
  if [[ ! -f "$pkg" ]]; then
    echo "[sync_versions] skip (not found): $pkg"
    return
  fi

  local current
  current="$(jq -r '.version // "none"' "$pkg")"

  if [[ "$current" == "$VERSION" ]]; then
    echo "[sync_versions] already in sync: $pkg"
    return
  fi

  jq --arg v "$VERSION" '.version = $v' "$pkg" > "$pkg.tmp"
  mv "$pkg.tmp" "$pkg"
  echo "[sync_versions] updated: $pkg ($current -> $VERSION)"
}

sync_package "$ROOT_DIR/npm/micado-wasm/package.json"
sync_package "$ROOT_DIR/packages/micado-streaming/package.json"
sync_package "$ROOT_DIR/workers/micado-edge/package.json"

echo "[sync_versions] done"
