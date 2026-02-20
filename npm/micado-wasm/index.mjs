import { createDicBinTokenizer, loadDicBin, parseDicBin } from "./dic-bin.mjs";

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

function createWasmTokenizerApi(exportsObject) {
  const encoder = new TextEncoder();
  const decoder = new TextDecoder();

  function decodeOutput(outputLen) {
    const bytes = new Uint8Array(outputLen);
    for (let i = 0; i < outputLen; i += 1) {
      bytes[i] = exportsObject.output_byte_at(i);
    }
    return decoder.decode(bytes);
  }

  function tokenizeBy(fnName, text) {
    const input = encoder.encode(text);
    exportsObject.reset_input();
    for (const byte of input) {
      exportsObject.push_input_byte(byte);
    }
    const outputLen = exportsObject[fnName]();
    return decodeOutput(outputLen);
  }

  return {
    tokenizeNanoTSV(text) {
      return tokenizeBy("tokenize_nano_tsv", text);
    },
    tokenizeMiniTSV(text) {
      return tokenizeBy("tokenize_mini_tsv", text);
    },
    tokenizeNano(text) {
      return parseTokenTSV(tokenizeBy("tokenize_nano_tsv", text));
    },
    tokenizeMini(text) {
      return parseTokenTSV(tokenizeBy("tokenize_mini_tsv", text));
    },
  };
}

export async function createMicadoWasm(options = {}) {
  const wasmBinary = await loadWasmBinary(options.wasmURL ?? DEFAULT_WASM_URL);
  const instantiated = await WebAssembly.instantiate(wasmBinary, {});
  const instance = "instance" in instantiated ? instantiated.instance : instantiated;
  return createWasmTokenizerApi(instance.exports);
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

export async function createWebSmallTokenizer(options = {}) {
  return createTokenizer({
    profile: options.profile ?? "full",
    compressed: options.compressed,
    dicURL: options.dicURL,
  });
}

export { DICTIONARY_PROFILES, parseDicBin, loadDicBin, createDicBinTokenizer };
