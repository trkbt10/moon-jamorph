#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

if [[ -d "${ROOT_DIR}/src/dict" ]]; then
  echo "[guard] src/dict has been reintroduced: ${ROOT_DIR}/src/dict"
  echo "[guard] This repository uses external MeCab dictionaries and .dic.bin at runtime."
  echo "[guard] Remove src/dict before merging."
  exit 1
fi

find_dict_imports() {
  local pattern='@[^"[:space:]]+/dict/'
  if command -v rg >/dev/null 2>&1; then
    rg -n "${pattern}" \
      "${ROOT_DIR}/src" \
      "${ROOT_DIR}/cmd" \
      --glob 'moon.pkg.json' \
      --glob '*.mbt' || true
  else
    grep -R -n -E "${pattern}" \
      --include='moon.pkg.json' \
      --include='*.mbt' \
      "${ROOT_DIR}/src" \
      "${ROOT_DIR}/cmd" || true
  fi
}

# Guard against re-introducing compile-time dependencies to removed dict packages.
dict_import_hits="$(find_dict_imports)"
if [[ -n "${dict_import_hits}" ]]; then
  echo "[guard] compile-time dict package dependency found in src/ or cmd/."
  echo "[guard] Remove @.../dict/... imports to keep src/dict abolished."
  printf '%s\n' "${dict_import_hits}"
  exit 1
fi

echo "[guard] src/dict abolished checks passed"
