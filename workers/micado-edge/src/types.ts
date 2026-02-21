export interface CompactToken {
  surface: string;
  pos_detail: string;
  start_pos: number;
  end_pos: number;
}

export interface DetailedToken extends CompactToken {
  pos: string;
  mecab_feature: string;
}

export type Token = CompactToken | DetailedToken;

export type TokenFormat = "tsv" | "compact" | "detailed";

export interface RuntimeStats {
  profile: string;
  sourceMode: string;
  entryLimit: number;
  targetDeflateBytes: number;
  dictionaryCompressedBytes: number;
  dictionaryBytes: number;
  entryCount: number;
  maxSurfaceLength: number;
  connectionIdCount: number;
}

export interface Runtime {
  stats: RuntimeStats;
  tokenizeTSV(text: string): string;
}

export type RuntimeState = "idle" | "initializing" | "ready" | "error";

export interface RuntimeStatus {
  state: RuntimeState;
  attempts: number;
  initStartedAt: string | null;
  readyAt: string | null;
  elapsedMs: number | null;
  initError: string | null;
}

export interface StreamOptions {
  windowChars: number;
  overlapChars: number;
  forceFlushChars: number;
  notifyWindow: boolean;
  includeText: boolean;
}

export interface StreamOptionsInput {
  windowChars?: string | number;
  overlapChars?: string | number;
  forceFlushChars?: string | number;
  notifyWindow?: string | boolean;
  includeText?: string | boolean;
}

export type BlockReason = "terminator" | "paragraph-break" | "forced" | "eof";

export interface QuoteState {
  stack: string[];
  inSingleQuote: boolean;
  inDoubleQuote: boolean;
}

export interface ScanResult {
  boundary: number | null;
  scannedTo: number;
  reason: BlockReason | null;
}

export interface SSEWriter {
  send(event: string, payload: unknown): Promise<boolean>;
  close(): Promise<void>;
}

export interface MicadoWasmExports {
  memory: WebAssembly.Memory;
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
