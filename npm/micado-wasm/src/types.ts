// Re-export token types from streaming package (single source of truth)
import type {
  CompactToken,
  DetailedToken,
  Token,
  TokenFormat,
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
} from "@trkbt10/micado-streaming";

export type {
  CompactToken,
  DetailedToken,
  Token,
  TokenFormat,
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
};

/**
 * Dictionary statistics from loaded WASM runtime.
 */
export interface DictionaryStats {
  /** Number of dictionary entries */
  entryCount: number;
  /** Maximum surface form length in bytes */
  maxSurfaceLength: number;
  /** Number of connection IDs in cost matrix */
  connectionIdCount: number;
  /** Total bytes of loaded dictionary */
  bytes: number;
}

/**
 * Source types for loadDictionary().
 */
export type DictionarySource =
  | string
  | URL
  | Response
  | Uint8Array
  | ArrayBuffer;

/**
 * Tokenizer instance returned by createTokenizer().
 */
export interface Tokenizer {
  readonly stats: DictionaryStats;
  readonly backend: "wasm";
  /** Tokenize text to detailed tokens */
  tokenize(text: string): DetailedToken[];
  /** Tokenize text to TSV string */
  tokenizeTSV(text: string): string;
  /** Create a streaming writer for tokenization */
  createWriter(options?: StreamOptionsInput): TokenStreamWriter;
}

/**
 * Expected exports from the MoonBit-compiled WASM module.
 */
export interface MicadoWasmExports {
  readonly memory: WebAssembly.Memory;
  reset_input(): void;
  push_input_byte(byte: number): void;
  output_byte_at(index: number): number;
  reset_dic_input(): void;
  push_dic_input_byte(byte: number): void;
  load_dic_bin(): number;
  dictionary_entry_count(): number;
  dictionary_max_surface_length(): number;
  dictionary_connection_id_count(): number;
  tokenize_nano_tsv(): number;
}
