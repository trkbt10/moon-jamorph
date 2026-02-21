/**
 * Compact token representation for minimal output.
 */
export interface CompactToken {
  /** Surface form (the actual text) */
  surface: string;
  /** Full part-of-speech detail string (comma-separated) */
  pos_detail: string;
  /** Start position in input text (byte offset) */
  start_pos: number;
  /** End position in input text (byte offset, exclusive) */
  end_pos: number;
}

/**
 * Full token with MeCab-compatible features.
 */
export interface DetailedToken extends CompactToken {
  /** Short POS tag: "品詞,品詞細分類1" */
  pos: string;
  /** MeCab feature string */
  mecab_feature: string;
}

/**
 * Union type for any token format.
 */
export type Token = CompactToken | DetailedToken;

/**
 * Dictionary profile identifiers.
 */
export type DictionaryProfile = "tiny" | "mini" | "medium" | "full";

/**
 * All available dictionary profiles.
 */
export const DICTIONARY_PROFILES: readonly DictionaryProfile[] = [
  "tiny",
  "mini",
  "medium",
  "full",
] as const;

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
 * Options for createTokenizer().
 */
export interface TokenizerOptions {
  /** Dictionary profile (default: "full") */
  profile?: DictionaryProfile;
  /** Whether dictionary is deflate-compressed (default: true) */
  compressed?: boolean;
  /** Custom dictionary URL */
  dicURL?: URL | string;
  /** Custom WASM URL */
  wasmURL?: URL | string;
}

/**
 * Options for createMicadoWasm() dual-tokenizer.
 */
export interface MicadoWasmOptions extends TokenizerOptions {
  /** Profile for nano tokenizer */
  nanoProfile?: DictionaryProfile;
  /** Profile for mini tokenizer */
  miniProfile?: DictionaryProfile;
  /** Custom dictionary URL for nano */
  nanoDicURL?: URL | string;
  /** Custom dictionary URL for mini */
  miniDicURL?: URL | string;
}

/**
 * Tokenizer instance returned by createTokenizer().
 */
export interface Tokenizer {
  readonly profile: DictionaryProfile;
  readonly entries: readonly unknown[];
  readonly stats: DictionaryStats;
  readonly backend: "wasm";
  /** Tokenize text to detailed tokens */
  tokenize(text: string): DetailedToken[];
  /** Tokenize text to TSV string */
  tokenizeTSV(text: string): string;
}

/**
 * Dual tokenizer returned by createMicadoWasm().
 */
export interface MicadoWasm {
  readonly nanoProfile: DictionaryProfile;
  readonly miniProfile: DictionaryProfile;
  readonly backend: "wasm";
  tokenizeNano(text: string): CompactToken[];
  tokenizeMini(text: string): CompactToken[];
  tokenizeNanoTSV(text: string): string;
  tokenizeMiniTSV(text: string): string;
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

/**
 * Source types that can be loaded as binary data.
 */
export type BinarySource = Uint8Array | ArrayBuffer | URL | string;

/**
 * Options for loadDicBin().
 */
export interface LoadDicBinOptions {
  /** Whether the source is deflate-compressed */
  compressed?: boolean;
}
