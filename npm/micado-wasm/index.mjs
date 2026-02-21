import { loadDicBin } from "./dic-bin.mjs";

const DEFAULT_WASM_URL = new URL("./dist/micado_wasm.wasm", import.meta.url);
const DICTIONARY_PROFILES = ["tiny", "mini", "medium", "full"];

async function loadWasmBinary(source) {
  if (source instanceof Uint8Array) {
    return source;
  }
  if (source instanceof ArrayBuffer) {
    return new Uint8Array(source);
  }

  const url = source instanceof URL ? source : new URL(source ?? DEFAULT_WASM_URL, import.meta.url);
  if (url.protocol === "file:") {
    const fs = await import("node:fs/promises");
    const bytes = await fs.readFile(url);
    return new Uint8Array(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  }

  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`Failed to fetch wasm: ${response.status} ${response.statusText}`);
  }
  return new Uint8Array(await response.arrayBuffer());
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

function posFromDetail(posDetail) {
  const cols = posDetail.split(",");
  const c0 = cols[0] || "未知語";
  const c1 = cols[1] || "*";
  return `${c0},${c1}`;
}

function parseTokensFromTSV(tsv, detailed) {
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
    const surface = parts[0];
    const posDetail = parts[1];
    if (!surface || !posDetail) {
      continue;
    }
    const hasFeature = parts.length >= 5;
    const startPos = Number.parseInt(parts[hasFeature ? 3 : 2], 10);
    const endPos = Number.parseInt(parts[hasFeature ? 4 : 3], 10);
    if (!Number.isFinite(startPos) || !Number.isFinite(endPos)) {
      continue;
    }
    if (detailed) {
      const mecabFeature = hasFeature ? parts[2] : posDetail;
      tokens.push({
        surface,
        pos: posFromDetail(posDetail),
        pos_detail: posDetail,
        mecab_feature: mecabFeature,
        start_pos: startPos,
        end_pos: endPos,
      });
    } else {
      tokens.push({
        surface,
        pos_detail: posDetail,
        start_pos: startPos,
        end_pos: endPos,
      });
    }
  }
  return tokens;
}

export function parseTokenTSV(tsv) {
  return parseTokensFromTSV(tsv, false);
}

function parseDetailedTokenTSV(tsv) {
  return parseTokensFromTSV(tsv, true);
}

function createWasmBridge(exportsObject) {
  const encoder = new TextEncoder();
  const decoder = new TextDecoder();

  function decodeOutput(outputLen) {
    const bytes = new Uint8Array(outputLen);
    for (let i = 0; i < outputLen; i += 1) {
      bytes[i] = exportsObject.output_byte_at(i);
    }
    return decoder.decode(bytes);
  }

  function writeBytesByPush(resetFn, pushFn, bytes) {
    exportsObject[resetFn]();
    for (const byte of bytes) {
      exportsObject[pushFn](byte);
    }
  }

  function runTokenize(fnName, text) {
    const input = encoder.encode(text);
    writeBytesByPush("reset_input", "push_input_byte", input);
    const outputLen = exportsObject[fnName]();
    return decodeOutput(outputLen);
  }

  function loadDictionary(bytes) {
    writeBytesByPush("reset_dic_input", "push_dic_input_byte", bytes);
    const loaded = exportsObject.load_dic_bin();
    if (loaded < 0) {
      throw new Error("Failed to load dic.bin in wasm runtime");
    }
    return {
      entryCount: exportsObject.dictionary_entry_count(),
      maxSurfaceLength: exportsObject.dictionary_max_surface_length(),
      connectionIdCount: exportsObject.dictionary_connection_id_count(),
    };
  }

  return {
    runTokenize,
    loadDictionary,
  };
}

async function createRuntimeTokenizer(options = {}) {
  const profile = normalizeProfile(options.profile ?? "full");
  const compressed = options.compressed === undefined ? true : !!options.compressed;
  const dicURL = options.dicURL ?? defaultDicURL(profile, compressed);

  const wasmBinary = await loadWasmBinary(options.wasmURL ?? DEFAULT_WASM_URL);
  const instantiated = await WebAssembly.instantiate(wasmBinary, {});
  const instance = "instance" in instantiated ? instantiated.instance : instantiated;
  const bridge = createWasmBridge(instance.exports);

  const dicBytes = await loadDicBin(dicURL, {
    compressed: options.compressed,
  });
  const stats = bridge.loadDictionary(dicBytes);

  return {
    profile,
    tokenizeTSV(text) {
      return bridge.runTokenize("tokenize_nano_tsv", text);
    },
    tokenizeCompact(text) {
      return parseTokenTSV(bridge.runTokenize("tokenize_nano_tsv", text));
    },
    tokenizeDetailed(text) {
      return parseDetailedTokenTSV(bridge.runTokenize("tokenize_nano_tsv", text));
    },
    stats: {
      entryCount: stats.entryCount,
      maxSurfaceLength: stats.maxSurfaceLength,
      connectionIdCount: stats.connectionIdCount,
      bytes: dicBytes.byteLength,
    },
    backend: "wasm",
  };
}

export async function createTokenizer(options = {}) {
  const tokenizer = await createRuntimeTokenizer(options);
  return {
    profile: tokenizer.profile,
    entries: [],
    stats: tokenizer.stats,
    backend: tokenizer.backend,
    tokenize(text) {
      return tokenizer.tokenizeDetailed(text);
    },
    tokenizeTSV(text) {
      return tokenizer.tokenizeTSV(text);
    },
  };
}

function toCompactToken(token) {
  return {
    surface: token.surface,
    pos_detail: token.pos_detail,
    start_pos: token.start_pos,
    end_pos: token.end_pos,
  };
}

function toCompactTSV(tokens) {
  return tokens
    .map((token) => `${token.surface}\t${token.pos_detail}\t${token.start_pos}\t${token.end_pos}`)
    .join("\n");
}

export async function createMicadoWasm(options = {}) {
  const sharedProfile = options.profile;
  const nanoProfile = normalizeProfile(options.nanoProfile ?? sharedProfile ?? "tiny");
  const miniProfile = normalizeProfile(options.miniProfile ?? sharedProfile ?? "mini");

  const nanoKey = `${nanoProfile}|${String(options.nanoDicURL ?? options.dicURL ?? "")}|${String(options.compressed ?? true)}|${String(options.wasmURL ?? "")}`;
  const miniKey = `${miniProfile}|${String(options.miniDicURL ?? options.dicURL ?? "")}|${String(options.compressed ?? true)}|${String(options.wasmURL ?? "")}`;

  let nanoTokenizer;
  let miniTokenizer;
  if (nanoKey === miniKey) {
    nanoTokenizer = await createRuntimeTokenizer({
      profile: nanoProfile,
      compressed: options.compressed,
      dicURL: options.nanoDicURL ?? options.dicURL,
      wasmURL: options.wasmURL,
    });
    miniTokenizer = nanoTokenizer;
  } else {
    [nanoTokenizer, miniTokenizer] = await Promise.all([
      createRuntimeTokenizer({
        profile: nanoProfile,
        compressed: options.compressed,
        dicURL: options.nanoDicURL ?? options.dicURL,
        wasmURL: options.wasmURL,
      }),
      createRuntimeTokenizer({
        profile: miniProfile,
        compressed: options.compressed,
        dicURL: options.miniDicURL ?? options.dicURL,
        wasmURL: options.wasmURL,
      }),
    ]);
  }

  return {
    tokenizeNanoTSV(text) {
      return toCompactTSV(nanoTokenizer.tokenizeCompact(text));
    },
    tokenizeMiniTSV(text) {
      return toCompactTSV(miniTokenizer.tokenizeCompact(text));
    },
    tokenizeNano(text) {
      return nanoTokenizer.tokenizeDetailed(text).map(toCompactToken);
    },
    tokenizeMini(text) {
      return miniTokenizer.tokenizeDetailed(text).map(toCompactToken);
    },
    backend: "wasm",
    nanoProfile,
    miniProfile,
  };
}

export async function createWebSmallTokenizer(options = {}) {
  return createTokenizer({
    profile: options.profile ?? "full",
    compressed: options.compressed,
    dicURL: options.dicURL,
    wasmURL: options.wasmURL,
  });
}

export { DICTIONARY_PROFILES, loadDicBin };
