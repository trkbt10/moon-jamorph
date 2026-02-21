import { loadDicBin } from "./dic-bin.js";
import { loadBinary } from "./platform/loader.js";
import type {
  BinarySource,
  CompactToken,
  DetailedToken,
  DictionaryProfile,
  DictionaryStats,
  MicadoWasm,
  MicadoWasmExports,
  MicadoWasmOptions,
  Tokenizer,
  TokenizerOptions,
} from "./types.js";
import { DICTIONARY_PROFILES } from "./types.js";

const DEFAULT_WASM_URL = new URL("../dist/micado_wasm.wasm", import.meta.url);

async function loadWasmBinary(source?: BinarySource): Promise<Uint8Array> {
  return loadBinary(source ?? DEFAULT_WASM_URL);
}

function normalizeProfile(profile?: string | DictionaryProfile): DictionaryProfile {
  const value = String(profile ?? "full").toLowerCase();
  if (!DICTIONARY_PROFILES.includes(value as DictionaryProfile)) {
    throw new Error(
      `unknown dictionary profile: ${profile} (expected ${DICTIONARY_PROFILES.join("|")})`
    );
  }
  return value as DictionaryProfile;
}

function defaultDicURL(profile: DictionaryProfile, compressed: boolean): URL {
  const ext = compressed ? ".dic.bin.deflate" : ".dic.bin";
  return new URL(`../dist/${profile}${ext}`, import.meta.url);
}

function posFromDetail(posDetail: string): string {
  const cols = posDetail.split(",");
  const c0 = cols[0] || "未知語";
  const c1 = cols[1] || "*";
  return `${c0},${c1}`;
}

function parseTokensFromTSV(tsv: string, detailed: true): DetailedToken[];
function parseTokensFromTSV(tsv: string, detailed: false): CompactToken[];
function parseTokensFromTSV(
  tsv: string,
  detailed: boolean
): CompactToken[] | DetailedToken[] {
  if (!tsv) {
    return [];
  }
  const tokens: (CompactToken | DetailedToken)[] = [];
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
    const startPos = Number.parseInt(parts[hasFeature ? 3 : 2] ?? "", 10);
    const endPos = Number.parseInt(parts[hasFeature ? 4 : 3] ?? "", 10);
    if (!Number.isFinite(startPos) || !Number.isFinite(endPos)) {
      continue;
    }
    if (detailed) {
      const mecabFeature = hasFeature ? (parts[2] ?? posDetail) : posDetail;
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

export function parseTokenTSV(tsv: string): CompactToken[] {
  return parseTokensFromTSV(tsv, false);
}

function parseDetailedTokenTSV(tsv: string): DetailedToken[] {
  return parseTokensFromTSV(tsv, true);
}

interface WasmBridge {
  runTokenize(fnName: "tokenize_nano_tsv", text: string): string;
  loadDictionary(bytes: Uint8Array): {
    entryCount: number;
    maxSurfaceLength: number;
    connectionIdCount: number;
  };
}

function createWasmBridge(exportsObject: MicadoWasmExports): WasmBridge {
  const encoder = new TextEncoder();
  const decoder = new TextDecoder();

  function decodeOutput(outputLen: number): string {
    const bytes = new Uint8Array(outputLen);
    for (let i = 0; i < outputLen; i += 1) {
      bytes[i] = exportsObject.output_byte_at(i);
    }
    return decoder.decode(bytes);
  }

  function writeBytesByPush(
    resetFn: "reset_input" | "reset_dic_input",
    pushFn: "push_input_byte" | "push_dic_input_byte",
    bytes: Uint8Array
  ): void {
    exportsObject[resetFn]();
    for (const byte of bytes) {
      exportsObject[pushFn](byte);
    }
  }

  function runTokenize(fnName: "tokenize_nano_tsv", text: string): string {
    const input = encoder.encode(text);
    writeBytesByPush("reset_input", "push_input_byte", input);
    const outputLen = exportsObject[fnName]();
    return decodeOutput(outputLen);
  }

  function loadDictionary(bytes: Uint8Array): {
    entryCount: number;
    maxSurfaceLength: number;
    connectionIdCount: number;
  } {
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

interface RuntimeTokenizer {
  profile: DictionaryProfile;
  tokenizeTSV(text: string): string;
  tokenizeCompact(text: string): CompactToken[];
  tokenizeDetailed(text: string): DetailedToken[];
  stats: DictionaryStats;
  backend: "wasm";
}

async function createRuntimeTokenizer(
  options: TokenizerOptions = {}
): Promise<RuntimeTokenizer> {
  const profile = normalizeProfile(options.profile ?? "full");
  const compressed = options.compressed === undefined ? true : !!options.compressed;
  const dicURL = options.dicURL ?? defaultDicURL(profile, compressed);

  const wasmBinary = await loadWasmBinary(options.wasmURL);
  const result = await WebAssembly.instantiate(wasmBinary, {});
  const instance =
    "instance" in result
      ? (result as unknown as WebAssembly.WebAssemblyInstantiatedSource).instance
      : (result as unknown as WebAssembly.Instance);
  const bridge = createWasmBridge(instance.exports as unknown as MicadoWasmExports);

  const dicBytes = await loadDicBin(dicURL, {
    compressed: options.compressed,
  });
  const stats = bridge.loadDictionary(dicBytes);

  return {
    profile,
    tokenizeTSV(text: string): string {
      return bridge.runTokenize("tokenize_nano_tsv", text);
    },
    tokenizeCompact(text: string): CompactToken[] {
      return parseTokenTSV(bridge.runTokenize("tokenize_nano_tsv", text));
    },
    tokenizeDetailed(text: string): DetailedToken[] {
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

export async function createTokenizer(
  options: TokenizerOptions = {}
): Promise<Tokenizer> {
  const tokenizer = await createRuntimeTokenizer(options);
  return {
    profile: tokenizer.profile,
    entries: [],
    stats: tokenizer.stats,
    backend: tokenizer.backend,
    tokenize(text: string): DetailedToken[] {
      return tokenizer.tokenizeDetailed(text);
    },
    tokenizeTSV(text: string): string {
      return tokenizer.tokenizeTSV(text);
    },
  };
}

function toCompactToken(token: DetailedToken): CompactToken {
  return {
    surface: token.surface,
    pos_detail: token.pos_detail,
    start_pos: token.start_pos,
    end_pos: token.end_pos,
  };
}

function toCompactTSV(tokens: CompactToken[]): string {
  return tokens
    .map(
      (token) =>
        `${token.surface}\t${token.pos_detail}\t${token.start_pos}\t${token.end_pos}`
    )
    .join("\n");
}

export async function createMicadoWasm(
  options: MicadoWasmOptions = {}
): Promise<MicadoWasm> {
  const sharedProfile = options.profile;
  const nanoProfile = normalizeProfile(
    options.nanoProfile ?? sharedProfile ?? "tiny"
  );
  const miniProfile = normalizeProfile(
    options.miniProfile ?? sharedProfile ?? "mini"
  );

  const nanoKey = `${nanoProfile}|${String(options.nanoDicURL ?? options.dicURL ?? "")}|${String(options.compressed ?? true)}|${String(options.wasmURL ?? "")}`;
  const miniKey = `${miniProfile}|${String(options.miniDicURL ?? options.dicURL ?? "")}|${String(options.compressed ?? true)}|${String(options.wasmURL ?? "")}`;

  let nanoTokenizer: RuntimeTokenizer;
  let miniTokenizer: RuntimeTokenizer;
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
    tokenizeNanoTSV(text: string): string {
      return toCompactTSV(nanoTokenizer.tokenizeCompact(text));
    },
    tokenizeMiniTSV(text: string): string {
      return toCompactTSV(miniTokenizer.tokenizeCompact(text));
    },
    tokenizeNano(text: string): CompactToken[] {
      return nanoTokenizer.tokenizeDetailed(text).map(toCompactToken);
    },
    tokenizeMini(text: string): CompactToken[] {
      return miniTokenizer.tokenizeDetailed(text).map(toCompactToken);
    },
    backend: "wasm",
    nanoProfile,
    miniProfile,
  };
}

export async function createWebSmallTokenizer(
  options: TokenizerOptions = {}
): Promise<Tokenizer> {
  return createTokenizer({
    profile: options.profile ?? "full",
    compressed: options.compressed,
    dicURL: options.dicURL,
    wasmURL: options.wasmURL,
  });
}

export { DICTIONARY_PROFILES, loadDicBin };
export type {
  BinarySource,
  CompactToken,
  DetailedToken,
  DictionaryProfile,
  DictionaryStats,
  LoadDicBinOptions,
  MicadoWasm,
  MicadoWasmExports,
  MicadoWasmOptions,
  Token,
  Tokenizer,
  TokenizerOptions,
} from "./types.js";
export { AOZORA_EXAMPLES, type AozoraExample } from "./examples.js";
