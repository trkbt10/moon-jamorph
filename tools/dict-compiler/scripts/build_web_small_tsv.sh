#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
LIMIT="${1:-8000}"

node "$ROOT_DIR/tools/dict-compiler/scripts/build_web_dic_artifacts.mjs" \
  --only-tsv \
  --limit "$LIMIT"
