#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"

"${ROOT_DIR}/tools/distribution/check_dict_abolished.sh"

TEXT="$(cat "${ROOT_DIR}/npm/micado-wasm/demo/smoke-sentence.txt")"

find_mecab_dicdirs() {
  local -a out=()

  if [[ -n "${MECAB_DICDIR:-}" && -d "${MECAB_DICDIR}" ]]; then
    out+=("${MECAB_DICDIR}")
  fi

  if command -v mecab-config >/dev/null 2>&1; then
    local base
    base="$(mecab-config --dicdir 2>/dev/null || true)"
    if [[ -n "${base}" ]]; then
      local name
      for name in unidic unidic-lite ipadic-utf8 ipadic; do
        if [[ -d "${base}/${name}" ]]; then
          out+=("${base}/${name}")
        fi
      done
    fi
  fi

  local p
  for p in \
    /opt/homebrew/lib/mecab/dic/unidic \
    /opt/homebrew/lib/mecab/dic/ipadic-utf8 \
    /opt/homebrew/lib/mecab/dic/ipadic \
    /usr/lib/x86_64-linux-gnu/mecab/dic/unidic \
    /usr/lib/x86_64-linux-gnu/mecab/dic/ipadic-utf8 \
    /usr/lib/x86_64-linux-gnu/mecab/dic/ipadic \
    /var/lib/mecab/dic/unidic \
    /var/lib/mecab/dic/ipadic-utf8 \
    /var/lib/mecab/dic/ipadic; do
    if [[ -d "${p}" ]]; then
      out+=("${p}")
    fi
  done

  printf '%s\n' "${out[@]}" | awk 'NF > 0 && !seen[$0]++'
}

validate_cli_json() {
  node -e '
let raw = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", (chunk) => { raw += chunk; });
process.stdin.on("end", () => {
  const payload = JSON.parse(raw);
  if (payload.backend !== "mecab") {
    throw new Error(`unexpected backend: ${payload.backend}`);
  }
  if (payload.dictionary_source !== "dicdir") {
    throw new Error(`unexpected dictionary_source: ${payload.dictionary_source}`);
  }
  if (!Array.isArray(payload.tokens) || payload.tokens.length < 7) {
    throw new Error("token list is too small");
  }
  if (payload.tokens.some((t) => typeof t.surface === "string" && t.surface.includes("�"))) {
    throw new Error("mojibake detected in token surfaces");
  }
  if (payload.tokens.some((t) => typeof t.pos === "string" && t.pos.includes("�"))) {
    throw new Error("mojibake detected in token pos");
  }
  const surfaces = payload.tokens.map((t) => t.surface);
  if (!surfaces.includes("吾輩")) {
    throw new Error(`missing expected token: 吾輩 (${JSON.stringify(surfaces)})`);
  }
  if (!surfaces.includes("猫")) {
    throw new Error(`missing expected token: 猫 (${JSON.stringify(surfaces)})`);
  }
  if (!surfaces.includes("名前")) {
    throw new Error(`missing expected token: 名前 (${JSON.stringify(surfaces)})`);
  }
  const hasNai =
    surfaces.includes("無い") ||
    surfaces.includes("ない") ||
    surfaces.includes("無") ||
    surfaces.includes("い");
  if (!hasNai) {
    throw new Error(`missing expected tail tokenization: ${JSON.stringify(surfaces)}`);
  }
});
' >/dev/null
}

echo "[verify] CLI smoke (native + mecab dicdir)"
if ! command -v mecab >/dev/null 2>&1; then
  echo "[verify] mecab command is not available"
  exit 1
fi

selected_dicdir=""
while IFS= read -r dicdir; do
  [[ -z "${dicdir}" ]] && continue
  echo "[verify] trying dicdir=${dicdir}"
  json_out="$(moon run --target native cmd/main -- -d "${dicdir}" -O json "${TEXT}" 2>/dev/null || true)"
  if [[ -z "${json_out}" ]]; then
    continue
  fi
  if printf '%s' "${json_out}" | validate_cli_json 2>/dev/null; then
    selected_dicdir="${dicdir}"
    break
  fi
done < <(find_mecab_dicdirs)

if [[ -z "${selected_dicdir}" ]]; then
  echo "[verify] failed to find a working mecab dictionary directory"
  echo "[verify] candidates:"
  find_mecab_dicdirs | sed 's/^/  - /'
  echo "[verify] required: unidic/unidic-lite/ipadic-utf8/ipadic"
  exit 1
fi

echo "[verify] selected dicdir=${selected_dicdir}"
json_out="$(moon run --target native cmd/main -- -d "${selected_dicdir}" -O json "${TEXT}")"
printf '%s' "${json_out}" | validate_cli_json
wakati_out="$(moon run --target native cmd/main -- -d "${selected_dicdir}" -O wakati "${TEXT}")"
if [[ "${wakati_out}" != *"吾輩"* || "${wakati_out}" != *"猫"* ]]; then
  echo "[verify] unexpected wakati output: ${wakati_out}"
  exit 1
fi
echo "[verify] cli=ok"

ipadic_dicdir=""
while IFS= read -r dicdir; do
  [[ -z "${dicdir}" ]] && continue
  case "${dicdir}" in
    */ipadic)
      ipadic_dicdir="${dicdir}"
      break
      ;;
  esac
done < <(find_mecab_dicdirs)

if [[ -n "${ipadic_dicdir}" ]]; then
  echo "[verify] cli smoke (ipadic charset conversion): ${ipadic_dicdir}"
  ipadic_json="$(moon run --target native cmd/main -- -d "${ipadic_dicdir}" -O json "${TEXT}")"
  printf '%s' "${ipadic_json}" | validate_cli_json
  echo "[verify] ipadic-conversion=ok"
fi

echo "[verify] wasm + dic.bin smoke"
"${ROOT_DIR}/tools/distribution/build_wasm_npm.sh"
node "${ROOT_DIR}/npm/micado-wasm/demo/node-smoke.mjs"
node "${ROOT_DIR}/npm/micado-wasm/demo/node-dic-smoke.mjs"
echo "[verify] wasm=ok"

echo "[verify] all checks passed"
