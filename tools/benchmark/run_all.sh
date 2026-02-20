#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
INPUT_FILE="${ROOT_DIR}/bench/corpus/aozora_openings.txt"
MECAB_DICDIR="${MECAB_DICDIR:-}"
EDITION="full"
RUNS=10
TRIALS=10
COPIES=2000
WITH_VIBRATO=1
DATE_TAG="$(date +%F)"

OUT_DIR="${ROOT_DIR}/bench/benchmark"
VIBRATO_WORK_DIR="${ROOT_DIR}/tmp/benchmark/vibrato"
VIBRATO_REPO_DIR="${VIBRATO_WORK_DIR}/repo"
VIBRATO_CACHE_DIR="${VIBRATO_WORK_DIR}/cache"
VIBRATO_SYSDIC="${VIBRATO_SYSDIC:-}"

usage() {
  cat <<'EOF'
Usage: tools/benchmark/run_all.sh [options]

Runs benchmark for micado + MeCab (+ Vibrato) and renders an SVG chart.

Options:
  -i, --input <file>       Input corpus file (default: bench/corpus/aozora_openings.txt)
  -d, --dicdir <path>      MeCab dictionary directory (default: auto detect, ipadic preferred)
  -e, --edition <name>     micado edition: nano|mini|standard|full (default: full)
      --runs <n>           RUNS for micado/MeCab benchmark (default: 10)
      --trials <n>         TRIALS for micado/MeCab benchmark (default: 10)
  -c, --copies <n>         Duplicate input corpus N times (default: 2000)
      --date-tag <tag>     Output suffix tag (default: YYYY-MM-DD)
      --no-vibrato         Skip Vibrato benchmark
  -h, --help               Show help
EOF
}

parse_int() {
  local value="$1"
  if [[ ! "$value" =~ ^[0-9]+$ ]] || [[ "$value" -le 0 ]]; then
    return 1
  fi
  printf '%s\n' "$value"
}

auto_detect_dicdir() {
  local candidates=(
    "/opt/homebrew/lib/mecab/dic/ipadic"
    "/opt/homebrew/lib/mecab/dic/unidic"
    "/usr/local/lib/mecab/dic/ipadic"
    "/usr/local/lib/mecab/dic/unidic"
    "/var/lib/mecab/dic/ipadic"
    "/var/lib/mecab/dic/unidic"
  )
  local path
  for path in "${candidates[@]}"; do
    if [[ -d "$path" ]]; then
      printf '%s\n' "$path"
      return 0
    fi
  done
  return 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -i|--input)
      INPUT_FILE="$2"
      shift 2
      ;;
    -d|--dicdir)
      MECAB_DICDIR="$2"
      shift 2
      ;;
    -e|--edition)
      EDITION="$2"
      shift 2
      ;;
    --runs)
      RUNS="$(parse_int "$2")" || {
        echo "error: --runs must be a positive integer" >&2
        exit 1
      }
      shift 2
      ;;
    --trials)
      TRIALS="$(parse_int "$2")" || {
        echo "error: --trials must be a positive integer" >&2
        exit 1
      }
      shift 2
      ;;
    -c|--copies)
      COPIES="$(parse_int "$2")" || {
        echo "error: --copies must be a positive integer" >&2
        exit 1
      }
      shift 2
      ;;
    --date-tag)
      DATE_TAG="$2"
      shift 2
      ;;
    --no-vibrato)
      WITH_VIBRATO=0
      shift 1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ ! -f "$INPUT_FILE" ]]; then
  echo "error: input file not found: $INPUT_FILE" >&2
  exit 1
fi
if ! command -v moon >/dev/null 2>&1; then
  echo "error: moon command not found" >&2
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "error: python3 command not found" >&2
  exit 1
fi
if ! command -v mecab >/dev/null 2>&1; then
  echo "error: mecab command not found" >&2
  exit 1
fi

if [[ -z "$MECAB_DICDIR" ]]; then
  MECAB_DICDIR="$(auto_detect_dicdir || true)"
fi
if [[ -z "$MECAB_DICDIR" ]]; then
  echo "error: MeCab dicdir not found. Pass --dicdir <path>." >&2
  exit 1
fi
if [[ ! -d "$MECAB_DICDIR" ]]; then
  echo "error: MeCab dicdir does not exist: $MECAB_DICDIR" >&2
  exit 1
fi

mkdir -p "$OUT_DIR" "$VIBRATO_CACHE_DIR"
OUT_TXT="${OUT_DIR}/quick_compare_${DATE_TAG}.txt"
OUT_SVG="${OUT_DIR}/quick_compare_${DATE_TAG}.svg"
LATEST_TXT="${OUT_DIR}/quick_compare_latest.txt"
LATEST_SVG="${OUT_DIR}/quick_compare_latest.svg"

echo "[run_all] running micado + mecab benchmark..."
"${ROOT_DIR}/tools/benchmark/quick_compare.sh" \
  --input "$INPUT_FILE" \
  --dicdir "$MECAB_DICDIR" \
  --edition "$EDITION" \
  --runs "$RUNS" \
  --trials "$TRIALS" \
  --copies "$COPIES" | tee "$OUT_TXT"

if [[ "$WITH_VIBRATO" -eq 1 ]]; then
  if ! command -v cargo >/dev/null 2>&1; then
    echo "error: cargo command not found (required for vibrato benchmark)" >&2
    exit 1
  fi
  if ! command -v curl >/dev/null 2>&1; then
    echo "error: curl command not found (required for vibrato dictionary download)" >&2
    exit 1
  fi

  echo "[run_all] preparing corpus copy for vibrato..."
  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "$tmp_dir"' EXIT
  expanded_input="${tmp_dir}/corpus.txt"
  for _ in $(seq 1 "$COPIES"); do
    cat "$INPUT_FILE" >> "$expanded_input"
  done

  if [[ -z "$VIBRATO_SYSDIC" ]]; then
    echo "[run_all] preparing vibrato dictionary..."
    if [[ ! -d "$VIBRATO_REPO_DIR/.git" ]]; then
      rm -rf "$VIBRATO_REPO_DIR"
      git clone --depth 1 https://github.com/daac-tools/vibrato.git "$VIBRATO_REPO_DIR" >/dev/null
    else
      git -C "$VIBRATO_REPO_DIR" pull --ff-only >/dev/null
    fi

    vib_tar_url="$(
      python3 - <<'PY'
import json
import sys
import urllib.request

url = "https://api.github.com/repos/daac-tools/vibrato/releases?per_page=30"
with urllib.request.urlopen(url) as resp:
    releases = json.load(resp)
for rel in releases:
    for asset in rel.get("assets", []):
        if asset.get("name") == "ipadic-mecab-2_7_0.tar.xz":
            print(asset["browser_download_url"])
            sys.exit(0)
print("")
PY
    )"
    if [[ -z "$vib_tar_url" ]]; then
      echo "error: failed to locate vibrato ipadic-mecab-2_7_0.tar.xz asset" >&2
      exit 1
    fi
    vib_tar_path="${VIBRATO_CACHE_DIR}/ipadic-mecab-2_7_0.tar.xz"
    vib_extract_dir="${VIBRATO_CACHE_DIR}/ipadic-mecab-2_7_0"
    if [[ ! -f "$vib_tar_path" ]]; then
      curl -L "$vib_tar_url" -o "$vib_tar_path"
    fi
    if [[ ! -f "${vib_extract_dir}/system.dic.zst" ]]; then
      rm -rf "$vib_extract_dir"
      mkdir -p "$vib_extract_dir"
      tar -xJf "$vib_tar_path" -C "$VIBRATO_CACHE_DIR"
    fi
    VIBRATO_SYSDIC="${vib_extract_dir}/system.dic.zst"
  fi

  if [[ ! -f "$VIBRATO_SYSDIC" ]]; then
    echo "error: vibrato dictionary not found: $VIBRATO_SYSDIC" >&2
    exit 1
  fi
  if [[ ! -d "$VIBRATO_REPO_DIR/.git" ]]; then
    rm -rf "$VIBRATO_REPO_DIR"
    git clone --depth 1 https://github.com/daac-tools/vibrato.git "$VIBRATO_REPO_DIR" >/dev/null
  fi

  echo "[run_all] running vibrato benchmark..."
  vib_raw="${tmp_dir}/vibrato_raw.txt"
  (
    cd "$VIBRATO_REPO_DIR"
    cargo run --release -p benchmark -- -i "$VIBRATO_SYSDIC" < "$expanded_input"
  ) 2>&1 | tee "$vib_raw" >/dev/null

  vib_block="$(
    python3 - "$vib_raw" <<'PY'
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace")
warm = re.search(r"^Warmup:\s*([0-9.]+)\s*$", text, re.MULTILINE)
sent = re.search(r"^Number_of_sentences:\s*([0-9]+)\s*$", text, re.MULTILINE)
ela = re.search(
    r"^Elapsed_seconds_to_tokenize_all_sentences:\s*\[([0-9.]+),([0-9.]+),([0-9.]+)\]\s*$",
    text,
    re.MULTILINE,
)
if warm is None or sent is None or ela is None:
    raise SystemExit("failed to parse vibrato benchmark output")
warmup = float(warm.group(1))
num = int(sent.group(1))
mn = float(ela.group(1))
av = float(ela.group(2))
mx = float(ela.group(3))
sps_min = num / mx
sps_avg = num / av
sps_max = num / mn
print("[vibrato/ipadic-mecab-2_7_0]")
print(f"Warmup: {warmup:.6f}")
print(f"Number_of_sentences: {num}")
print(f"Elapsed_seconds_to_tokenize_all_sentences: [{mn:.6f},{av:.6f},{mx:.6f}]")
print(f"Sentences_per_second: [{sps_min:.2f},{sps_avg:.2f},{sps_max:.2f}]")
PY
  )"

  {
    echo
    echo "$vib_block"
  } | tee -a "$OUT_TXT"
fi

echo "[run_all] rendering chart..."
python3 "${ROOT_DIR}/tools/benchmark/render_compare_chart.py" \
  --input "$OUT_TXT" \
  --output "$OUT_SVG" \
  --title "micado vs MeCab vs Vibrato benchmark (${DATE_TAG})"

cp "$OUT_TXT" "$LATEST_TXT"
cp "$OUT_SVG" "$LATEST_SVG"

echo "[run_all] done"
echo "  benchmark text: $OUT_TXT"
echo "  benchmark svg : $OUT_SVG"
echo "  latest text   : $LATEST_TXT"
echo "  latest svg    : $LATEST_SVG"
