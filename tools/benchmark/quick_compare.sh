#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
INPUT_FILE="${ROOT_DIR}/bench/corpus/aozora_openings.txt"
MECAB_DICDIR="${MECAB_DICDIR:-}"
EDITION="full"
RUNS=10
TRIALS=10
COPIES=2000

usage() {
  cat <<'EOF'
Usage: tools/benchmark/quick_compare.sh [options]

Options:
  -i, --input <file>       Input corpus file (default: bench/corpus/aozora_openings.txt)
  -d, --dicdir <path>      MeCab dictionary directory (default: auto detect)
  -e, --edition <name>     micado edition: nano|mini|standard|full (default: full)
      --runs <n>           RUNS in vibrato benchmark style (default: 10)
      --trials <n>         TRIALS in vibrato benchmark style (default: 10)
  -c, --copies <n>         Duplicate input corpus N times (default: 2000)
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
    "/var/lib/mecab/dic/unidic"
    "/var/lib/mecab/dic/ipadic"
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
if ! command -v python3 >/dev/null 2>&1; then
  echo "error: python3 is required for high-resolution timing" >&2
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

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
corpus="${tmp_dir}/corpus.txt"
empty_corpus="${tmp_dir}/empty.txt"
: > "$empty_corpus"
for _ in $(seq 1 "$COPIES"); do
  cat "$INPUT_FILE" >> "$corpus"
done

base_sentences="$(awk 'NF>0 {c++} END {print c+0}' "$INPUT_FILE")"
total_sentences=$((base_sentences * COPIES))

echo "[quick_compare] building native binaries..."
moon build --target native cmd/tokenize >/dev/null

micado_bin="${ROOT_DIR}/_build/native/release/build/cmd/tokenize/tokenize.exe"
if [[ ! -x "$micado_bin" ]]; then
  echo "error: micado binary not found: $micado_bin" >&2
  exit 1
fi

measure_once() {
  local command="$1"
  python3 - "$command" <<'PY'
import subprocess
import sys
import time

command = sys.argv[1]
t0 = time.perf_counter()
subprocess.run(
    command,
    shell=True,
    stdout=subprocess.DEVNULL,
    stderr=subprocess.DEVNULL,
    check=True,
)
t1 = time.perf_counter()
print(f"{t1 - t0:.6f}")
PY
}

mean_of_file() {
  local file="$1"
  awk '{sum+=$1} END {if (NR==0) print "0.000000"; else printf "%.6f", sum/NR}' "$file"
}

stats_discard_minmax() {
  local file="$1"
  local sorted_file="$2"
  sort -n "$file" > "$sorted_file"
  awk '
    {
      a[NR] = $1
    }
    END {
      if (NR == 0) {
        printf "0.000000 0.000000 0.000000"
        exit
      }
      start = 1
      end = NR
      if (NR >= 3) {
        start = 2
        end = NR - 1
      }
      min = a[start]
      max = a[start]
      sum = 0
      cnt = 0
      for (i = start; i <= end; i++) {
        if (a[i] < min) min = a[i]
        if (a[i] > max) max = a[i]
        sum += a[i]
        cnt++
      }
      printf "%.6f %.6f %.6f", min, sum/cnt, max
    }
  ' "$sorted_file"
}

run_case() {
  local label="$1"
  local command="$2"
  local startup_command="$3"
  local case_id
  case_id="$(echo "$label" | tr ' /' '__')"

  local warm_file="${tmp_dir}/warm_${case_id}.txt"
  local warm_startup_file="${tmp_dir}/warm_startup_${case_id}.txt"
  : > "$warm_file"
  : > "$warm_startup_file"
  for _ in $(seq 1 "$RUNS"); do
    measure_once "$command" >> "$warm_file"
    measure_once "$startup_command" >> "$warm_startup_file"
  done
  local warm_avg warm_startup_avg warm_without_startup
  warm_avg="$(mean_of_file "$warm_file")"
  warm_startup_avg="$(mean_of_file "$warm_startup_file")"
  warm_without_startup="$(
    awk -v full="$warm_avg" -v startup="$warm_startup_avg" \
      'BEGIN {v=full-startup; if (v < 0) v=0; printf "%.6f", v}'
  )"

  local min_sum=0 avg_sum=0 max_sum=0
  local startup_min_sum=0 startup_avg_sum=0 startup_max_sum=0
  for trial in $(seq 1 "$TRIALS"); do
    local trial_file="${tmp_dir}/trial_${case_id}_${trial}.txt"
    local sorted_file="${tmp_dir}/trial_${case_id}_${trial}_sorted.txt"
    local startup_trial_file="${tmp_dir}/startup_trial_${case_id}_${trial}.txt"
    local startup_sorted_file="${tmp_dir}/startup_trial_${case_id}_${trial}_sorted.txt"
    : > "$trial_file"
    : > "$startup_trial_file"
    for _ in $(seq 1 "$RUNS"); do
      measure_once "$command" >> "$trial_file"
      measure_once "$startup_command" >> "$startup_trial_file"
    done
    local stats startup_stats
    stats="$(stats_discard_minmax "$trial_file" "$sorted_file")"
    startup_stats="$(
      stats_discard_minmax "$startup_trial_file" "$startup_sorted_file"
    )"
    local t_min t_avg t_max st_min st_avg st_max
    read -r t_min t_avg t_max <<<"$stats"
    read -r st_min st_avg st_max <<<"$startup_stats"
    min_sum="$(awk -v a="$min_sum" -v b="$t_min" 'BEGIN {printf "%.9f", a + b}')"
    avg_sum="$(awk -v a="$avg_sum" -v b="$t_avg" 'BEGIN {printf "%.9f", a + b}')"
    max_sum="$(awk -v a="$max_sum" -v b="$t_max" 'BEGIN {printf "%.9f", a + b}')"
    startup_min_sum="$(awk -v a="$startup_min_sum" -v b="$st_min" 'BEGIN {printf "%.9f", a + b}')"
    startup_avg_sum="$(awk -v a="$startup_avg_sum" -v b="$st_avg" 'BEGIN {printf "%.9f", a + b}')"
    startup_max_sum="$(awk -v a="$startup_max_sum" -v b="$st_max" 'BEGIN {printf "%.9f", a + b}')"
  done

  local min_sec avg_sec max_sec startup_min_sec startup_avg_sec startup_max_sec
  min_sec="$(awk -v s="$min_sum" -v t="$TRIALS" 'BEGIN {printf "%.6f", s/t}')"
  avg_sec="$(awk -v s="$avg_sum" -v t="$TRIALS" 'BEGIN {printf "%.6f", s/t}')"
  max_sec="$(awk -v s="$max_sum" -v t="$TRIALS" 'BEGIN {printf "%.6f", s/t}')"
  startup_min_sec="$(awk -v s="$startup_min_sum" -v t="$TRIALS" 'BEGIN {printf "%.6f", s/t}')"
  startup_avg_sec="$(awk -v s="$startup_avg_sum" -v t="$TRIALS" 'BEGIN {printf "%.6f", s/t}')"
  startup_max_sec="$(awk -v s="$startup_max_sum" -v t="$TRIALS" 'BEGIN {printf "%.6f", s/t}')"

  local tokenize_min_sec tokenize_avg_sec tokenize_max_sec
  tokenize_min_sec="$(
    awk -v full="$min_sec" -v startup="$startup_min_sec" \
      'BEGIN {v=full-startup; if (v < 0) v=0; printf "%.6f", v}'
  )"
  tokenize_avg_sec="$(
    awk -v full="$avg_sec" -v startup="$startup_avg_sec" \
      'BEGIN {v=full-startup; if (v < 0) v=0; printf "%.6f", v}'
  )"
  tokenize_max_sec="$(
    awk -v full="$max_sec" -v startup="$startup_max_sec" \
      'BEGIN {v=full-startup; if (v < 0) v=0; printf "%.6f", v}'
  )"

  local sps_min sps_avg sps_max
  sps_min="$(awk -v s="$total_sentences" -v sec="$max_sec" 'BEGIN {if (sec <= 0) print "inf"; else printf "%.2f", s/sec}')"
  sps_avg="$(awk -v s="$total_sentences" -v sec="$avg_sec" 'BEGIN {if (sec <= 0) print "inf"; else printf "%.2f", s/sec}')"
  sps_max="$(awk -v s="$total_sentences" -v sec="$min_sec" 'BEGIN {if (sec <= 0) print "inf"; else printf "%.2f", s/sec}')"
  local sps_wo_startup_min sps_wo_startup_avg sps_wo_startup_max
  sps_wo_startup_min="$(awk -v s="$total_sentences" -v sec="$tokenize_max_sec" 'BEGIN {if (sec <= 0) print "inf"; else printf "%.2f", s/sec}')"
  sps_wo_startup_avg="$(awk -v s="$total_sentences" -v sec="$tokenize_avg_sec" 'BEGIN {if (sec <= 0) print "inf"; else printf "%.2f", s/sec}')"
  sps_wo_startup_max="$(awk -v s="$total_sentences" -v sec="$tokenize_min_sec" 'BEGIN {if (sec <= 0) print "inf"; else printf "%.2f", s/sec}')"

  echo
  echo "[${label}]"
  echo "Warmup: ${warm_avg}"
  echo "Warmup_startup_overhead_estimate: ${warm_startup_avg}"
  echo "Warmup_without_startup_estimate: ${warm_without_startup}"
  echo "Number_of_sentences: ${total_sentences}"
  echo "Elapsed_seconds_to_tokenize_all_sentences: [${min_sec},${avg_sec},${max_sec}]"
  echo "Sentences_per_second: [${sps_min},${sps_avg},${sps_max}]"
  echo "Startup_overhead_seconds_estimate: [${startup_min_sec},${startup_avg_sec},${startup_max_sec}]"
  echo "Elapsed_seconds_without_startup_estimate: [${tokenize_min_sec},${tokenize_avg_sec},${tokenize_max_sec}]"
  echo "Sentences_per_second_without_startup_estimate: [${sps_wo_startup_min},${sps_wo_startup_avg},${sps_wo_startup_max}]"
}

echo "[quick_compare] input=${INPUT_FILE} copies=${COPIES} total_sentences=${total_sentences}"
echo "[quick_compare] runs=${RUNS} trials=${TRIALS} (vibrato benchmark style)"
echo "[quick_compare] mecab_dicdir=${MECAB_DICDIR}"
echo "[quick_compare] reporting startup-inclusive and startup-subtracted estimates"

printf -v micado_cmd '%q -e %q -Onone < %q' "$micado_bin" "$EDITION" "$corpus"
printf -v mecab_cmd 'mecab -d %q < %q > /dev/null' "$MECAB_DICDIR" "$corpus"
printf -v micado_startup_cmd '%q -e %q -Onone < %q' "$micado_bin" "$EDITION" "$empty_corpus"
printf -v mecab_startup_cmd 'mecab -d %q < %q > /dev/null' "$MECAB_DICDIR" "$empty_corpus"

run_case "micado/${EDITION}" "$micado_cmd" "$micado_startup_cmd"
run_case "mecab/$(basename "$MECAB_DICDIR")" "$mecab_cmd" "$mecab_startup_cmd"
