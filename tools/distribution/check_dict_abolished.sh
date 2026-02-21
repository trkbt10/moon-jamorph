#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

if [[ -d "${ROOT_DIR}/src/dict" ]]; then
  echo "[guard] src/dict has been reintroduced: ${ROOT_DIR}/src/dict"
  echo "[guard] This repository uses external MeCab dictionaries and .dic.bin at runtime."
  echo "[guard] Remove src/dict before merging."
  exit 1
fi

# Guard against re-introducing compile-time dependencies to removed dict packages.
if rg -n '@[^"[:space:]]+/dict/' \
  "${ROOT_DIR}/src" \
  "${ROOT_DIR}/cmd" \
  --glob 'moon.pkg.json' \
  --glob '*.mbt' >/dev/null; then
  echo "[guard] compile-time dict package dependency found in src/ or cmd/."
  echo "[guard] Remove @.../dict/... imports to keep src/dict abolished."
  rg -n '@[^"[:space:]]+/dict/' \
    "${ROOT_DIR}/src" \
    "${ROOT_DIR}/cmd" \
    --glob 'moon.pkg.json' \
    --glob '*.mbt'
  exit 1
fi

echo "[guard] src/dict abolished checks passed"
