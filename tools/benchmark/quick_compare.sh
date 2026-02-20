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
    "/opt/homebrew/lib/mecab/dic/unidic"
    "/opt/homebrew/lib/mecab/dic/ipadic"
    "/usr/local/lib/mecab/dic/unidic"
    "/usr/local/lib/mecab/dic/ipadic"
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
  ( /usr/bin/time -p sh -c "$command" >/dev/null ) 2>&1 | awk '/^real / {print $2}'
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
  local case_id
  case_id="$(echo "$label" | tr ' /' '__')"

  local warm_file="${tmp_dir}/warm_${case_id}.txt"
  : > "$warm_file"
  for _ in $(seq 1 "$RUNS"); do
    measure_once "$command" >> "$warm_file"
  done
  local warm_avg
  warm_avg="$(mean_of_file "$warm_file")"

  local min_sum=0
  local avg_sum=0
  local max_sum=0
  for trial in $(seq 1 "$TRIALS"); do
    local trial_file="${tmp_dir}/trial_${case_id}_${trial}.txt"
    local sorted_file="${tmp_dir}/trial_${case_id}_${trial}_sorted.txt"
    : > "$trial_file"
    for _ in $(seq 1 "$RUNS"); do
      measure_once "$command" >> "$trial_file"
    done
    local stats
    stats="$(stats_discard_minmax "$trial_file" "$sorted_file")"
    local t_min t_avg t_max
    read -r t_min t_avg t_max <<<"$stats"
    min_sum="$(awk -v a="$min_sum" -v b="$t_min" 'BEGIN {printf "%.9f", a + b}')"
    avg_sum="$(awk -v a="$avg_sum" -v b="$t_avg" 'BEGIN {printf "%.9f", a + b}')"
    max_sum="$(awk -v a="$max_sum" -v b="$t_max" 'BEGIN {printf "%.9f", a + b}')"
  done

  local min_sec avg_sec max_sec
  min_sec="$(awk -v s="$min_sum" -v t="$TRIALS" 'BEGIN {printf "%.6f", s/t}')"
  avg_sec="$(awk -v s="$avg_sum" -v t="$TRIALS" 'BEGIN {printf "%.6f", s/t}')"
  max_sec="$(awk -v s="$max_sum" -v t="$TRIALS" 'BEGIN {printf "%.6f", s/t}')"

  local sps_min sps_avg sps_max
  sps_min="$(awk -v s="$total_sentences" -v sec="$max_sec" 'BEGIN {if (sec <= 0) print "inf"; else printf "%.2f", s/sec}')"
  sps_avg="$(awk -v s="$total_sentences" -v sec="$avg_sec" 'BEGIN {if (sec <= 0) print "inf"; else printf "%.2f", s/sec}')"
  sps_max="$(awk -v s="$total_sentences" -v sec="$min_sec" 'BEGIN {if (sec <= 0) print "inf"; else printf "%.2f", s/sec}')"

  echo
  echo "[${label}]"
  echo "Warmup: ${warm_avg}"
  echo "Number_of_sentences: ${total_sentences}"
  echo "Elapsed_seconds_to_tokenize_all_sentences: [${min_sec},${avg_sec},${max_sec}]"
  echo "Sentences_per_second: [${sps_min},${sps_avg},${sps_max}]"
  if [[ "$avg_sec" == "0.000000" ]]; then
    echo "Note: timer resolution is coarse on macOS; increase --copies for stable timing."
  fi
}

echo "[quick_compare] input=${INPUT_FILE} copies=${COPIES} total_sentences=${total_sentences}"
echo "[quick_compare] runs=${RUNS} trials=${TRIALS} (vibrato benchmark style)"
echo "[quick_compare] mecab_dicdir=${MECAB_DICDIR}"

printf -v micado_cmd '%q -e %q -Onone < %q' "$micado_bin" "$EDITION" "$corpus"
printf -v mecab_cmd 'mecab -d %q < %q > /dev/null' "$MECAB_DICDIR" "$corpus"

run_case "micado/${EDITION}" "$micado_cmd"
run_case "mecab/$(basename "$MECAB_DICDIR")" "$mecab_cmd"
