import { createDicBinTokenizer, loadDicBin, parseDicBin } from "./dic-bin.mjs";

const DICTIONARY_PROFILES = ["tiny", "mini", "medium", "full"];

export function parseTokenTSV(tsv) {
  if (!tsv) {
    return [];
  }
  const tokens = [];
  const lines = tsv.split("\n");
  for (const line of lines) {
    if (!line) {
      continue;
    }
    const parts = line.split("\t");
    if (parts.length < 4) {
      continue;
    }
    tokens.push({
      surface: parts[0],
      pos_detail: parts[1],
      start_pos: Number.parseInt(parts[2], 10),
      end_pos: Number.parseInt(parts[3], 10),
    });
  }
  return tokens;
}

function normalizeProfile(profile) {
  const value = String(profile ?? "full").toLowerCase();
  if (!DICTIONARY_PROFILES.includes(value)) {
    throw new Error(
      `unknown dictionary profile: ${profile} (expected ${DICTIONARY_PROFILES.join("|")})`,
    );
  }
  return value;
}

function defaultDicURL(profile, compressed) {
  const ext = compressed ? ".dic.bin.deflate" : ".dic.bin";
  return new URL(`./dist/${profile}${ext}`, import.meta.url);
}

function toCompactToken(token) {
  return {
    surface: token.surface,
    pos_detail: token.pos_detail,
    start_pos: token.start_pos,
    end_pos: token.end_pos,
  };
}

function toTSV(tokens) {
  return tokens
    .map((token) => `${token.surface}\t${token.pos_detail}\t${token.start_pos}\t${token.end_pos}`)
    .join("\n");
}

export async function createTokenizer(options = {}) {
  const profile = normalizeProfile(options.profile ?? "full");
  const compressed = options.compressed === undefined ? true : !!options.compressed;
  const dicURL = options.dicURL ?? defaultDicURL(profile, compressed);
  const dic = await loadDicBin(dicURL, {
    compressed: options.compressed,
  });
  const tokenizer = createDicBinTokenizer(dic);
  return {
    ...tokenizer,
    profile,
  };
}

export async function createMicadoWasm(options = {}) {
  const compressed = options.compressed === undefined ? true : !!options.compressed;
  const sharedProfile = options.profile;
  const nanoProfile = normalizeProfile(options.nanoProfile ?? sharedProfile ?? "tiny");
  const miniProfile = normalizeProfile(options.miniProfile ?? sharedProfile ?? "mini");
  const nanoDicURL = options.nanoDicURL ?? options.dicURL;
  const miniDicURL = options.miniDicURL ?? options.dicURL;

  const nanoKey = `${nanoProfile}|${String(nanoDicURL ?? "")}|${compressed}`;
  const miniKey = `${miniProfile}|${String(miniDicURL ?? "")}|${compressed}`;
  let nanoTokenizer;
  let miniTokenizer;

  if (nanoKey === miniKey) {
    nanoTokenizer = await createTokenizer({
      profile: nanoProfile,
      compressed,
      dicURL: nanoDicURL,
    });
    miniTokenizer = nanoTokenizer;
  } else {
    [nanoTokenizer, miniTokenizer] = await Promise.all([
      createTokenizer({
        profile: nanoProfile,
        compressed,
        dicURL: nanoDicURL,
      }),
      createTokenizer({
        profile: miniProfile,
        compressed,
        dicURL: miniDicURL,
      }),
    ]);
  }

  return {
    tokenizeNanoTSV(text) {
      return toTSV(nanoTokenizer.tokenize(text));
    },
    tokenizeMiniTSV(text) {
      return toTSV(miniTokenizer.tokenize(text));
    },
    tokenizeNano(text) {
      return nanoTokenizer.tokenize(text).map(toCompactToken);
    },
    tokenizeMini(text) {
      return miniTokenizer.tokenize(text).map(toCompactToken);
    },
    backend: "dic.bin",
    nanoProfile,
    miniProfile,
  };
}

export async function createWebSmallTokenizer(options = {}) {
  return createTokenizer({
    profile: options.profile ?? "full",
    compressed: options.compressed,
    dicURL: options.dicURL,
  });
}

export { DICTIONARY_PROFILES, parseDicBin, loadDicBin, createDicBinTokenizer };
