#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"

"${ROOT_DIR}/tools/distribution/check_dict_abolished.sh"

TEXT="$(cat "${ROOT_DIR}/npm/micado-wasm/demo/smoke-sentence.txt")"

is_usable_mecab_dicdir() {
  local dicdir="$1"
  [[ -d "${dicdir}" ]] || return 1
  [[ -f "${dicdir}/sys.dic" ]] || return 1
  [[ -f "${dicdir}/unk.dic" ]] || return 1
  [[ -f "${dicdir}/matrix.bin" ]] || return 1
  return 0
}

find_mecab_dicdirs() {
  local -a out=()

  if [[ -n "${MECAB_DICDIR:-}" ]]; then
    if is_usable_mecab_dicdir "${MECAB_DICDIR}"; then
      out+=("${MECAB_DICDIR}")
    fi
  fi

  if command -v mecab >/dev/null 2>&1; then
    local mecab_info dicdir_from_mecab filename_from_mecab
    mecab_info="$(mecab -D 2>/dev/null || true)"
    dicdir_from_mecab="$(
      printf '%s\n' "${mecab_info}" | sed -n 's/^dicdir:[[:space:]]*//p' | head -n 1
    )"
    if [[ -n "${dicdir_from_mecab}" ]]; then
      if is_usable_mecab_dicdir "${dicdir_from_mecab}"; then
        out+=("${dicdir_from_mecab}")
      fi
    fi
    filename_from_mecab="$(
      printf '%s\n' "${mecab_info}" | sed -n 's/^filename:[[:space:]]*//p' | head -n 1
    )"
    if [[ -n "${filename_from_mecab}" ]]; then
      local filename_dir
      filename_dir="$(dirname "${filename_from_mecab}")"
      if is_usable_mecab_dicdir "${filename_dir}"; then
        out+=("${filename_dir}")
      fi
    fi
  fi

  if command -v mecab-config >/dev/null 2>&1; then
    local base
    base="$(mecab-config --dicdir 2>/dev/null || true)"
    if [[ -n "${base}" ]]; then
      if is_usable_mecab_dicdir "${base}"; then
        out+=("${base}")
      fi
      local name
      for name in debian unidic unidic-lite ipadic-utf8 ipadic; do
        if is_usable_mecab_dicdir "${base}/${name}"; then
          out+=("${base}/${name}")
        fi
      done
    fi
  fi

  local p
  for p in \
    /opt/homebrew/lib/mecab/dic/debian \
    /opt/homebrew/lib/mecab/dic/unidic \
    /opt/homebrew/lib/mecab/dic/ipadic-utf8 \
    /opt/homebrew/lib/mecab/dic/ipadic \
    /usr/lib/mecab/dic/debian \
    /usr/lib/mecab/dic/unidic \
    /usr/lib/mecab/dic/ipadic-utf8 \
    /usr/lib/mecab/dic/ipadic \
    /usr/lib/x86_64-linux-gnu/mecab/dic/debian \
    /usr/lib/x86_64-linux-gnu/mecab/dic/unidic \
    /usr/lib/x86_64-linux-gnu/mecab/dic/ipadic-utf8 \
    /usr/lib/x86_64-linux-gnu/mecab/dic/ipadic \
    /usr/share/mecab/dic/debian \
    /usr/share/mecab/dic/unidic \
    /usr/share/mecab/dic/ipadic-utf8 \
    /usr/share/mecab/dic/ipadic \
    /var/lib/mecab/dic/debian \
    /var/lib/mecab/dic/unidic \
    /var/lib/mecab/dic/ipadic-utf8 \
    /var/lib/mecab/dic/ipadic; do
    if is_usable_mecab_dicdir "${p}"; then
      out+=("${p}")
    fi
  done

  if [[ "${#out[@]}" -eq 0 ]]; then
    return 0
  fi
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
  if (!Array.isArray(payload.tokens) || payload.tokens.length === 0) {
    throw new Error("token list is empty");
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
  echo "[verify] required (usable): debian/unidic/unidic-lite/ipadic-utf8/ipadic"
  echo "[verify] mecab -D:"
  mecab -D 2>/dev/null || true
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
ipadic_json=""
while IFS= read -r dicdir; do
  [[ -z "${dicdir}" ]] && continue
  case "${dicdir}" in
    */ipadic|*/ipadic-utf8)
      echo "[verify] trying ipadic candidate=${dicdir}"
      candidate_json="$(
        moon run --target native cmd/main -- -d "${dicdir}" -O json "${TEXT}" 2>/dev/null || true
      )"
      if [[ -z "${candidate_json}" ]]; then
        continue
      fi
      if printf '%s' "${candidate_json}" | validate_cli_json 2>/dev/null; then
        ipadic_dicdir="${dicdir}"
        ipadic_json="${candidate_json}"
        break
      fi
      ;;
  esac
done < <(find_mecab_dicdirs)

if [[ -n "${ipadic_dicdir}" ]]; then
  echo "[verify] cli smoke (ipadic charset conversion): ${ipadic_dicdir}"
  printf '%s' "${ipadic_json}" | validate_cli_json
  echo "[verify] ipadic-conversion=ok"
else
  echo "[verify] no working ipadic dicdir found; skipping ipadic-conversion check"
fi

echo "[verify] wasm + dic.bin smoke"
"${ROOT_DIR}/tools/distribution/build_wasm_npm.sh"
if ! command -v npm >/dev/null 2>&1; then
  echo "[verify] npm command is not available"
  exit 1
fi
npm --prefix "${ROOT_DIR}/npm/micado-wasm" ci
npm --prefix "${ROOT_DIR}/npm/micado-wasm" run --silent build
node --input-type=module <<'NODE'
import { createMicadoWasm, createTokenizer } from "./npm/micado-wasm/dist/index.js";

const sentence = "すもももももももものうち";
const wasm = await createMicadoWasm({
  nanoProfile: "tiny",
  miniProfile: "mini",
  compressed: true,
});
const wasmNano = wasm.tokenizeNano(sentence);
const wasmMini = wasm.tokenizeMini(sentence);
console.log(`wasm-nano=${wasmNano.map((t) => t.surface).join("|")}`);
console.log(`wasm-mini=${wasmMini.map((t) => t.surface).join("|")}`);

const tokenizer = await createTokenizer({
  profile: "tiny",
  compressed: true,
});
const dicTokens = tokenizer.tokenize(sentence);
console.log(`dic-tiny=${dicTokens.map((t) => t.surface).join("|")}`);
console.log(`profile=${tokenizer.profile} entries=${tokenizer.stats.entryCount}`);

const dicCompact = dicTokens.map((t) => ({
  surface: t.surface,
  pos_detail: t.pos_detail,
  start_pos: t.start_pos,
  end_pos: t.end_pos,
}));
if (JSON.stringify(wasmNano) !== JSON.stringify(dicCompact)) {
  throw new Error(
    "createMicadoWasm(tokenizeNano) must match createTokenizer(profile=tiny)",
  );
}
const miniTokenizer = await createTokenizer({ profile: "mini", compressed: true });
const miniCompact = miniTokenizer.tokenize(sentence).map((t) => ({
  surface: t.surface,
  pos_detail: t.pos_detail,
  start_pos: t.start_pos,
  end_pos: t.end_pos,
}));
if (JSON.stringify(wasmMini) !== JSON.stringify(miniCompact)) {
  throw new Error(
    "createMicadoWasm(tokenizeMini) must match createTokenizer(profile=mini)",
  );
}
console.log("unified=nano-ok");
console.log("unified=mini-ok");
NODE
node --input-type=module <<'NODE'
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { createTokenizer } from "./npm/micado-wasm/dist/index.js";

const medium = await createTokenizer({ profile: "medium", compressed: true });
const full = await createTokenizer({ profile: "full", compressed: true });

const sentence = (
  await readFile(resolve(process.cwd(), "npm/micado-wasm/demo/smoke-sentence.txt"), "utf8")
).trim();
const mediumTokens = medium.tokenize(sentence);
const fullTokens = full.tokenize(sentence);

if (full.stats.entryCount < 300000) {
  throw new Error(`full profile too small: ${full.stats.entryCount}`);
}
if ((full.stats.connectionIdCount ?? 0) < 100) {
  throw new Error(`connection matrix ids too small: ${full.stats.connectionIdCount}`);
}

const fullSurfaces = fullTokens.map((t) => t.surface);
for (const required of ["吾輩", "猫", "名前", "無い"]) {
  if (!fullSurfaces.includes(required)) {
    throw new Error(`missing required surface: ${required} got=${JSON.stringify(fullSurfaces)}`);
  }
}
if (fullSurfaces.some((s) => s.includes("�"))) {
  throw new Error(`mojibake detected: ${JSON.stringify(fullSurfaces)}`);
}

console.log(`medium entries=${medium.stats.entryCount} tokens=${mediumTokens.length}`);
console.log(`full entries=${full.stats.entryCount} tokens=${fullTokens.length}`);
console.log(fullTokens.map((t) => `${t.surface}:${t.pos}`).join("|"));
console.log("verification=ok");
NODE
echo "[verify] wasm=ok"

echo "[verify] all checks passed"
