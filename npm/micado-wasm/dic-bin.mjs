// dic-bin.mjs is intentionally loader-only.
// Tokenization/parsing runtime lives in MoonBit wasm (`createTokenizer` / `createMicadoWasm`).

function normalizeBytes(source) {
  if (source instanceof Uint8Array) {
    return source;
  }
  if (source instanceof ArrayBuffer) {
    return new Uint8Array(source);
  }
  throw new Error("dic.bin source must be Uint8Array or ArrayBuffer");
}

function sourceLooksCompressed(source) {
  if (source instanceof URL) {
    return source.pathname.toLowerCase().endsWith(".deflate");
  }
  if (typeof source === "string") {
    return source.toLowerCase().endsWith(".deflate");
  }
  return false;
}

async function inflateDeflate(bytes) {
  if (typeof DecompressionStream !== "undefined") {
    const stream = new Blob([bytes]).stream().pipeThrough(new DecompressionStream("deflate"));
    const arrayBuffer = await new Response(stream).arrayBuffer();
    return new Uint8Array(arrayBuffer);
  }

  if (typeof process !== "undefined" && process.versions?.node) {
    const { inflateSync } = await import("node:zlib");
    const out = inflateSync(bytes);
    return new Uint8Array(out.buffer, out.byteOffset, out.byteLength);
  }

  throw new Error("No deflate decompressor available in this runtime");
}

async function readSourceBytes(source) {
  if (source instanceof Uint8Array || source instanceof ArrayBuffer) {
    return normalizeBytes(source);
  }

  const url = source instanceof URL ? source : new URL(source, import.meta.url);
  if (url.protocol === "file:") {
    const fs = await import("node:fs/promises");
    const file = await fs.readFile(url);
    return new Uint8Array(file.buffer, file.byteOffset, file.byteLength);
  }

  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`Failed to fetch dic.bin: ${response.status} ${response.statusText}`);
  }
  return new Uint8Array(await response.arrayBuffer());
}

export async function loadDicBin(source, options = {}) {
  const bytes = await readSourceBytes(source);
  const compressed =
    options.compressed === undefined ? sourceLooksCompressed(source) : !!options.compressed;
  return compressed ? inflateDeflate(bytes) : bytes;
}

function removedApiError(apiName) {
  throw new Error(
    `${apiName} was removed from JS runtime; use createTokenizer/createMicadoWasm (wasm runtime) instead`,
  );
}

export function parseDicBin() {
  removedApiError("parseDicBin");
}

export function createDicBinTokenizer() {
  removedApiError("createDicBinTokenizer");
}
