#!/usr/bin/env bash
# Synchronize version from moon.mod.json to npm/micado-wasm/package.json
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
MOON_MOD="$ROOT_DIR/moon.mod.json"
NPM_PKG="$ROOT_DIR/npm/micado-wasm/package.json"

VERSION="$(jq -r '.version' "$MOON_MOD")"

if [[ -z "$VERSION" || "$VERSION" == "null" ]]; then
  echo "[sync_versions] error: could not read version from $MOON_MOD" >&2
  exit 1
fi

CURRENT_NPM_VERSION="$(jq -r '.version' "$NPM_PKG")"

if [[ "$CURRENT_NPM_VERSION" == "$VERSION" ]]; then
  echo "[sync_versions] versions already in sync: $VERSION"
  exit 0
fi

jq --arg v "$VERSION" '.version = $v' "$NPM_PKG" > "$NPM_PKG.tmp"
mv "$NPM_PKG.tmp" "$NPM_PKG"

echo "[sync_versions] updated $NPM_PKG: $CURRENT_NPM_VERSION -> $VERSION"
