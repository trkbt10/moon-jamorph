import type { BinarySource, LoadDicBinOptions } from "./types.js";
import { loadBinary, sourceLooksCompressed } from "./platform/loader.js";
import { inflateDeflate } from "./platform/inflate.js";

/**
 * Load dictionary binary from various sources.
 * Automatically decompresses if the source ends with .deflate or compressed option is set.
 */
export async function loadDicBin(
  source: BinarySource,
  options: LoadDicBinOptions = {}
): Promise<Uint8Array> {
  const bytes = await loadBinary(source);
  const compressed =
    options.compressed === undefined
      ? sourceLooksCompressed(source)
      : options.compressed;
  return compressed ? inflateDeflate(bytes) : bytes;
}

function removedApiError(apiName: string): never {
  throw new Error(
    `${apiName} was removed from JS runtime; use createTokenizer/createMicadoWasm (wasm runtime) instead`
  );
}

/**
 * @deprecated Use createTokenizer/createMicadoWasm instead.
 */
export function parseDicBin(): never {
  removedApiError("parseDicBin");
}

/**
 * @deprecated Use createTokenizer/createMicadoWasm instead.
 */
export function createDicBinTokenizer(): never {
  removedApiError("createDicBinTokenizer");
}
