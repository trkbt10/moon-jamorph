import { loadBinary, sourceLooksCompressed } from "./platform/loader.js";
import { inflateDeflate } from "./platform/inflate.js";
import type {
  DetailedToken,
  DictionarySource,
  DictionaryStats,
  MicadoWasmExports,
  StreamOptionsInput,
  Tokenizer,
  TokenStreamWriter,
} from "./types.js";
import {
  createTokenStreamWriter,
  parseTokensFromTSV,
} from "@trkbt10/micado-streaming";

// ============================================================================
// Dictionary Loading
// ============================================================================

/**
 * Load dictionary from various sources.
 * Supports: file path, URL, Response, Uint8Array, ArrayBuffer
 * Automatically decompresses deflate-compressed dictionaries.
 */
export async function loadDictionary(
  source: DictionarySource
): Promise<Uint8Array> {
  // Uint8Array passthrough
  if (source instanceof Uint8Array) {
    return source;
  }

  // ArrayBuffer -> Uint8Array
  if (source instanceof ArrayBuffer) {
    return new Uint8Array(source);
  }

  // Response -> read body and try decompress
  if (source instanceof Response) {
    const buffer = await source.arrayBuffer();
    const bytes = new Uint8Array(buffer);
    return tryDecompress(bytes);
  }

  // URL or string -> load binary and decompress if needed
  const bytes = await loadBinary(source);
  const isCompressed = sourceLooksCompressed(source);
  return isCompressed ? inflateDeflate(bytes) : bytes;
}

async function tryDecompress(bytes: Uint8Array): Promise<Uint8Array> {
  try {
    return await inflateDeflate(bytes);
  } catch {
    // Not compressed or decompression failed, return as-is
    return bytes;
  }
}

// ============================================================================
// WASM Bridge
// ============================================================================

const DEFAULT_WASM_URL = new URL("../dist/micado_wasm.wasm", import.meta.url);

interface WasmBridge {
  tokenizeTSV(text: string): string;
  loadDictionary(bytes: Uint8Array): {
    entryCount: number;
    maxSurfaceLength: number;
    connectionIdCount: number;
  };
}

function createWasmBridge(exports: MicadoWasmExports): WasmBridge {
  const encoder = new TextEncoder();
  const decoder = new TextDecoder();

  function decodeOutput(length: number): string {
    const bytes = new Uint8Array(length);
    for (let i = 0; i < length; i++) {
      bytes[i] = exports.output_byte_at(i);
    }
    return decoder.decode(bytes);
  }

  function pushBytes(
    resetFn: "reset_input" | "reset_dic_input",
    pushFn: "push_input_byte" | "push_dic_input_byte",
    bytes: Uint8Array
  ): void {
    exports[resetFn]();
    for (const byte of bytes) {
      exports[pushFn](byte);
    }
  }

  return {
    tokenizeTSV(text: string): string {
      pushBytes("reset_input", "push_input_byte", encoder.encode(text));
      return decodeOutput(exports.tokenize_nano_tsv());
    },
    loadDictionary(bytes: Uint8Array) {
      pushBytes("reset_dic_input", "push_dic_input_byte", bytes);
      if (exports.load_dic_bin() < 0) {
        throw new Error("Failed to load dictionary in WASM runtime");
      }
      return {
        entryCount: exports.dictionary_entry_count(),
        maxSurfaceLength: exports.dictionary_max_surface_length(),
        connectionIdCount: exports.dictionary_connection_id_count(),
      };
    },
  };
}

// ============================================================================
// Tokenizer
// ============================================================================

/**
 * Create a tokenizer with the given dictionary.
 * @param dictionary - Dictionary binary from loadDictionary()
 */
export async function createTokenizer(
  dictionary: Uint8Array
): Promise<Tokenizer> {
  // Load and instantiate WASM
  const wasmBinary = await loadBinary(DEFAULT_WASM_URL);
  const result = await WebAssembly.instantiate(wasmBinary, {});
  const instance = (
    "instance" in result ? result.instance : result
  ) as WebAssembly.Instance;
  const bridge = createWasmBridge(instance.exports as unknown as MicadoWasmExports);

  // Load dictionary into WASM
  const dicStats = bridge.loadDictionary(dictionary);
  const stats: DictionaryStats = {
    ...dicStats,
    bytes: dictionary.byteLength,
  };

  return {
    stats,
    backend: "wasm",
    tokenize(text: string): DetailedToken[] {
      return parseTokensFromTSV(bridge.tokenizeTSV(text), true);
    },
    tokenizeTSV(text: string): string {
      return bridge.tokenizeTSV(text);
    },
    createWriter(options?: StreamOptionsInput): TokenStreamWriter {
      return createTokenStreamWriter(
        {
          tokenizeTSV: (text: string) => bridge.tokenizeTSV(text),
          profile: "custom",
          stats: {
            entryCount: stats.entryCount,
            bytes: stats.bytes,
            maxSurfaceLength: stats.maxSurfaceLength,
            connectionIdCount: stats.connectionIdCount,
          },
        },
        options
      );
    },
  };
}

// ============================================================================
// Exports
// ============================================================================

// Types
export type {
  CompactToken,
  DetailedToken,
  DictionarySource,
  DictionaryStats,
  Token,
  TokenFormat,
  Tokenizer,
  BlockReason,
  StreamOptionsInput,
  StreamOptions,
  StreamEvent,
  StreamMetaEvent,
  StreamBlockEvent,
  StreamDoneEvent,
  StreamErrorEvent,
  StreamWindowEvent,
  StreamResult,
  TokenStreamWriter,
  TokenStreamResponse,
} from "./types.js";

// Examples
export { AOZORA_EXAMPLES, type AozoraExample } from "./examples.js";

// Streaming utilities (for advanced use cases)
export { createTokenStreamWriter, createStreamingResponse } from "@trkbt10/micado-streaming";
