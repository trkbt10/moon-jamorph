#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
CACHE_DIR="$ROOT_DIR/tools/dict-compiler/.cache/web-small"
IPADIC_CACHE="$ROOT_DIR/tools/dict-compiler/.cache/ipadic"
ARCHIVE_PATH="$IPADIC_CACHE/mecab-ipadic-2.7.0-20070801.tar.xz"
SRC_DIR="$IPADIC_CACHE/mecab-ipadic-2.7.0-20070801"
TSV_PATH="$CACHE_DIR/ipadic_web_small.tsv"
LIMIT="${1:-8000}"
TMP_TSV="$CACHE_DIR/ipadic_web_small.tmp.tsv"

mkdir -p "$CACHE_DIR" "$IPADIC_CACHE"

if [[ ! -f "$ARCHIVE_PATH" ]]; then
  echo "[web-small] downloading ipadic archive..."
  curl -fsSL \
    "https://raw.githubusercontent.com/takuyaa/mecab-ipadic-seed/master/dict/mecab-ipadic-2.7.0-20070801.tar.xz" \
    -o "$ARCHIVE_PATH"
fi

if [[ ! -d "$SRC_DIR" ]]; then
  echo "[web-small] extracting ipadic archive..."
  tar -xf "$ARCHIVE_PATH" -C "$IPADIC_CACHE"
fi

echo "[web-small] extracting rows (limit=$LIMIT)..."
files=("$SRC_DIR"/*.csv)
if [[ ${#files[@]} -eq 0 ]]; then
  echo "[web-small] csv files not found under: $SRC_DIR" >&2
  exit 1
fi
per_file=$(( (LIMIT + ${#files[@]} - 1) / ${#files[@]} ))
: > "$TMP_TSV"

for csv in "${files[@]}"; do
awk -F',' -v limit="$per_file" '
BEGIN {
  OFS = "\t";
  count = 0;
}
{
  if (count >= limit) next;
  surface = $1;
  if (surface == "") next;
  left_id = $2;
  right_id = $3;
  word_cost = $4;
  pos1 = $5;
  pos2 = $6;
  pos3 = $7;
  pos4 = $8;
  ctype = ($9 == "" ? "*" : $9);
  cform = ($10 == "" ? "*" : $10);
  base = ($11 == "" ? surface : $11);
  read = ($12 == "" ? "*" : $12);
  pron = ($13 == "" ? "*" : $13);
  print surface, left_id, right_id, word_cost, pos1, pos2, pos3, pos4, ctype, cform, base, read, pron;
  count++;
}
END {
}
' "$csv" >> "$TMP_TSV"
done

head -n "$LIMIT" "$TMP_TSV" > "$TSV_PATH"
accepted="$(wc -l < "$TSV_PATH" | tr -d ' ')"
echo "[web-small] accepted rows: $accepted"

echo "[web-small] generated: $TSV_PATH"
