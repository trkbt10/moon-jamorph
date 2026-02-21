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
PNG_MAX_WIDTH=960
CHART_LAYOUT="auto"
DATE_TAG="$(date +%F)"

OUT_DIR="${ROOT_DIR}/bench/benchmark"
VIBRATO_WORK_DIR="${ROOT_DIR}/tmp/benchmark/vibrato"
VIBRATO_REPO_DIR="${VIBRATO_WORK_DIR}/repo"
VIBRATO_CACHE_DIR="${VIBRATO_WORK_DIR}/cache"
VIBRATO_SYSDIC="${VIBRATO_SYSDIC:-}"

usage() {
  cat <<'EOF'
Usage: tools/benchmark/run_all.sh [options]

Runs benchmark for micado + MeCab (+ Vibrato) and renders SVG + PNG charts.

Options:
  -i, --input <file>       Input corpus file (default: bench/corpus/aozora_openings.txt)
  -d, --dicdir <path>      MeCab dictionary directory (default: auto detect, ipadic preferred)
  -e, --edition <name>     micado edition: nano|mini|standard|full (default: full)
      --runs <n>           RUNS for each benchmark case (default: 10)
      --trials <n>         TRIALS for each benchmark case (default: 10)
  -c, --copies <n>         Duplicate input corpus N times (default: 2000)
      --chart-layout <m>   Chart layout: auto|horizontal|vertical (default: auto)
      --png-max-width <n>  Max PNG/SVG width in px, 0 disables resize (default: 960)
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

parse_non_negative_int() {
  local value="$1"
  if [[ ! "$value" =~ ^[0-9]+$ ]]; then
    return 1
  fi
  printf '%s\n' "$value"
}

convert_svg_to_png() {
  local src_svg="$1"
  local dst_png="$2"

  if command -v rsvg-convert >/dev/null 2>&1; then
    rsvg-convert "$src_svg" -o "$dst_png"
    return 0
  fi
  if command -v magick >/dev/null 2>&1; then
    magick "$src_svg" "$dst_png"
    return 0
  fi
  if command -v convert >/dev/null 2>&1; then
    convert "$src_svg" "$dst_png"
    return 0
  fi

  echo "error: no SVG->PNG converter found (need rsvg-convert or ImageMagick)." >&2
  exit 1
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

emit_subprocess_benchmark_block() {
  local label="$1"
  local command="$2"
  local startup_command="$3"
  local runs="$4"
  local trials="$5"
  local total_sentences="$6"

  python3 - "$label" "$command" "$startup_command" "$runs" "$trials" "$total_sentences" <<'PY'
import subprocess
import sys
import time

label = sys.argv[1]
command = sys.argv[2]
startup_command = sys.argv[3]
runs = int(sys.argv[4])
trials = int(sys.argv[5])
total_sentences = int(sys.argv[6])


def measure_once(cmd: str) -> float:
    t0 = time.perf_counter()
    subprocess.run(
        cmd,
        shell=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=True,
    )
    t1 = time.perf_counter()
    return t1 - t0


def trimmed_stats(values):
    xs = sorted(values)
    if len(xs) >= 3:
        xs = xs[1:-1]
    if not xs:
        return 0.0, 0.0, 0.0
    return min(xs), sum(xs) / len(xs), max(xs)


def clamp_non_negative(v: float) -> float:
    return v if v > 0.0 else 0.0


def to_sps(sec: float) -> str:
    if sec <= 0:
        return "inf"
    return f"{total_sentences / sec:.2f}"


warm_values = [measure_once(command) for _ in range(runs)]
warm_startup_values = [measure_once(startup_command) for _ in range(runs)]
warm_avg = sum(warm_values) / runs if runs > 0 else 0.0
warm_startup_avg = sum(warm_startup_values) / runs if runs > 0 else 0.0
warm_wo_startup = clamp_non_negative(warm_avg - warm_startup_avg)

full_min_sum = 0.0
full_avg_sum = 0.0
full_max_sum = 0.0
startup_min_sum = 0.0
startup_avg_sum = 0.0
startup_max_sum = 0.0
for _ in range(trials):
    full_values = [measure_once(command) for _ in range(runs)]
    startup_values = [measure_once(startup_command) for _ in range(runs)]
    f_min, f_avg, f_max = trimmed_stats(full_values)
    s_min, s_avg, s_max = trimmed_stats(startup_values)
    full_min_sum += f_min
    full_avg_sum += f_avg
    full_max_sum += f_max
    startup_min_sum += s_min
    startup_avg_sum += s_avg
    startup_max_sum += s_max

full_min = full_min_sum / trials if trials > 0 else 0.0
full_avg = full_avg_sum / trials if trials > 0 else 0.0
full_max = full_max_sum / trials if trials > 0 else 0.0
startup_min = startup_min_sum / trials if trials > 0 else 0.0
startup_avg = startup_avg_sum / trials if trials > 0 else 0.0
startup_max = startup_max_sum / trials if trials > 0 else 0.0
tok_min = clamp_non_negative(full_min - startup_min)
tok_avg = clamp_non_negative(full_avg - startup_avg)
tok_max = clamp_non_negative(full_max - startup_max)

print(f"[{label}]")
print(f"Warmup: {warm_avg:.6f}")
print(f"Warmup_startup_overhead_estimate: {warm_startup_avg:.6f}")
print(f"Warmup_without_startup_estimate: {warm_wo_startup:.6f}")
print(f"Number_of_sentences: {total_sentences}")
print(
    "Elapsed_seconds_to_tokenize_all_sentences: "
    f"[{full_min:.6f},{full_avg:.6f},{full_max:.6f}]"
)
print(
    "Sentences_per_second: "
    f"[{to_sps(full_max)},{to_sps(full_avg)},{to_sps(full_min)}]"
)
print(
    "Startup_overhead_seconds_estimate: "
    f"[{startup_min:.6f},{startup_avg:.6f},{startup_max:.6f}]"
)
print(
    "Elapsed_seconds_without_startup_estimate: "
    f"[{tok_min:.6f},{tok_avg:.6f},{tok_max:.6f}]"
)
print(
    "Sentences_per_second_without_startup_estimate: "
    f"[{to_sps(tok_max)},{to_sps(tok_avg)},{to_sps(tok_min)}]"
)
PY
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
    --chart-layout)
      CHART_LAYOUT="$2"
      if [[ "$CHART_LAYOUT" != "auto" && "$CHART_LAYOUT" != "horizontal" && "$CHART_LAYOUT" != "vertical" ]]; then
        echo "error: --chart-layout must be one of: auto, horizontal, vertical" >&2
        exit 1
      fi
      shift 2
      ;;
    --png-max-width)
      PNG_MAX_WIDTH="$(parse_non_negative_int "$2")" || {
        echo "error: --png-max-width must be a non-negative integer" >&2
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
OUT_PNG="${OUT_DIR}/quick_compare_${DATE_TAG}.png"
LATEST_TXT="${OUT_DIR}/quick_compare_latest.txt"
LATEST_SVG="${OUT_DIR}/quick_compare_latest.svg"
LATEST_PNG="${OUT_DIR}/quick_compare_latest.png"
README_FILE="${ROOT_DIR}/README.mbt.md"
base_sentences="$(awk 'NF>0 {c++} END {print c+0}' "$INPUT_FILE")"
total_sentences=$((base_sentences * COPIES))

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
  empty_input="${tmp_dir}/empty.txt"
  : > "$empty_input"
  (
    cd "$VIBRATO_REPO_DIR"
    cargo build --release -p tokenize >/dev/null
  )
  vib_bin="${VIBRATO_REPO_DIR}/target/release/tokenize"
  if [[ ! -x "$vib_bin" ]]; then
    echo "error: vibrato binary not found: $vib_bin" >&2
    exit 1
  fi
  printf -v vib_cmd '%q -i %q -O wakati < %q > /dev/null' "$vib_bin" "$VIBRATO_SYSDIC" "$expanded_input"
  printf -v vib_startup_cmd '%q -i %q -O wakati < %q > /dev/null' "$vib_bin" "$VIBRATO_SYSDIC" "$empty_input"
  vib_block="$(
    emit_subprocess_benchmark_block \
      "vibrato/ipadic-mecab-2_7_0" \
      "$vib_cmd" \
      "$vib_startup_cmd" \
      "$RUNS" \
      "$TRIALS" \
      "$total_sentences"
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
  --layout "$CHART_LAYOUT" \
  --max-width "$PNG_MAX_WIDTH" \
  --title "micado vs MeCab vs Vibrato benchmark (${DATE_TAG})"
convert_svg_to_png "$OUT_SVG" "$OUT_PNG"

cp "$OUT_TXT" "$LATEST_TXT"
cp "$OUT_SVG" "$LATEST_SVG"
cp "$OUT_PNG" "$LATEST_PNG"
python3 "${ROOT_DIR}/tools/benchmark/update_readme_benchmark.py" \
  --readme "$README_FILE" \
  --benchmark-text "$LATEST_TXT"

echo "[run_all] done"
echo "  benchmark text: $OUT_TXT"
echo "  benchmark svg : $OUT_SVG"
echo "  benchmark png : $OUT_PNG"
echo "  latest text   : $LATEST_TXT"
echo "  latest svg    : $LATEST_SVG"
echo "  latest png    : $LATEST_PNG"
echo "  readme        : $README_FILE"
