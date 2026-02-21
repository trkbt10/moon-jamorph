#!/usr/bin/env bash
set -euo pipefail

cat >&2 <<'MSG'
[deprecated] tools/dict-compiler/scripts/build_ipadic_generated.sh is retired.
Generated source dictionaries under src/dict are no longer part of the supported flow.
Use one of the following:
  - External MeCab dictionary via: moon run --target native cmd/main -- -d <dicdir> ...
  - Runtime .dic.bin generation via: tools/distribution/build_wasm_npm.sh
MSG
exit 1
