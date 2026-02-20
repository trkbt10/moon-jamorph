#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_DIR="$ROOT_DIR/tmp"

if [ ! -d "$TMP_DIR" ]; then
  exit 0
fi

FOUND=""
while IFS= read -r path; do
  if [ -z "$FOUND" ]; then
    FOUND="$path"
  else
    FOUND="$FOUND
$path"
  fi
done <<EOF
$(find "$TMP_DIR" -type f -name "moon.pkg.json" | sort)
EOF

if [ -z "$FOUND" ]; then
  exit 0
fi

echo "[guard] Detected temporary MoonBit package(s) under tmp/:"
printf '%s\n' "$FOUND" | while IFS= read -r path; do
  echo "  - ${path#$ROOT_DIR/}"
done
echo
echo "These files are picked up by 'moon info' / 'moon test' and can break whole-module checks."
echo "Remove them before running full checks:"
echo "  git clean -fd tmp"
echo "or:"
echo "  rm -rf tmp/<scratch-dir>"
exit 1
