/**
 * Compact token with basic information
 */
export interface CompactToken {
  surface: string;
  pos_detail: string;
  start_pos: number;
  end_pos: number;
}

/**
 * Detailed token with full MeCab-compatible features
 */
export interface DetailedToken extends CompactToken {
  pos: string;
  mecab_feature: string;
}

export type Token = CompactToken | DetailedToken;

/**
 * Output format for tokenization
 */
export type TokenFormat = "tsv" | "compact" | "detailed";

/**
 * Reason for emitting a block
 */
export type BlockReason = "terminator" | "paragraph-break" | "forced" | "eof";

/**
 * Abstract tokenizer interface that both npm/micado-wasm and workers can implement
 */
export interface TokenizerLike {
  tokenizeTSV(text: string): string;
  readonly profile: string;
  readonly stats: TokenizerStats;
}

export interface TokenizerStats {
  entryCount: number;
  bytes: number;
  maxSurfaceLength?: number;
  connectionIdCount?: number;
}

/**
 * Input options for stream configuration (flexible types for HTTP params)
 */
export interface StreamOptionsInput {
  windowChars?: string | number;
  overlapChars?: string | number;
  forceFlushChars?: string | number;
  notifyWindow?: string | boolean;
  includeText?: string | boolean;
  format?: TokenFormat;
}

/**
 * Normalized stream options
 */
export interface StreamOptions {
  windowChars: number;
  overlapChars: number;
  forceFlushChars: number;
  notifyWindow: boolean;
  includeText: boolean;
  format: TokenFormat;
}

/**
 * Quote state for boundary detection
 */
export interface QuoteState {
  stack: string[];
  inSingleQuote: boolean;
  inDoubleQuote: boolean;
}

/**
 * Result of boundary scan
 */
export interface ScanResult {
  boundary: number | null;
  scannedTo: number;
  reason: BlockReason | null;
}

// ========================================
// Stream Events
// ========================================

export interface StreamMetaEvent {
  type: "meta";
  profile: string;
  textLength: number;
  format: TokenFormat;
  options: StreamOptions;
}

export interface StreamWindowEvent {
  type: "window";
  index: number;
  start: number;
  end: number;
  safeEnd: number;
  emitCursor: number;
  scanCursor: number;
  pendingTokenCount: number;
  tokenCount: number;
}

export interface StreamBlockEvent {
  type: "block";
  index: number;
  reason: BlockReason;
  start: number;
  end: number;
  charLength: number;
  text?: string;
  tokens?: DetailedToken[] | CompactToken[];
  tsv?: string;
  tokenCount: number;
}

export interface StreamDoneEvent {
  type: "done";
  windows: number;
  blocks: number;
  finalCursor: number;
  textLength: number;
}

export interface StreamErrorEvent {
  type: "error";
  message: string;
}

export type StreamEvent =
  | StreamMetaEvent
  | StreamWindowEvent
  | StreamBlockEvent
  | StreamDoneEvent
  | StreamErrorEvent;

// ========================================
// Writer & Response Interfaces
// ========================================

/**
 * Result of collecting all stream events
 */
export interface StreamResult {
  meta: StreamMetaEvent;
  blocks: StreamBlockEvent[];
  done: StreamDoneEvent;
  allTokens: DetailedToken[] | CompactToken[];
}

/**
 * SSE Writer interface for sending events
 */
export interface SSEWriter {
  send(event: string, payload: unknown): Promise<boolean>;
  close(): Promise<void>;
}

/**
 * Token stream writer for various output formats
 */
export interface TokenStreamWriter {
  /**
   * Synchronous generator for consuming events
   */
  write(text: string): IterableIterator<StreamEvent>;

  /**
   * Get a ReadableStream of events
   */
  stream(text: string): ReadableStream<StreamEvent>;

  /**
   * Get a Response-like object with .json(), .tokens(), .text() methods
   */
  response(text: string): TokenStreamResponse;
}

/**
 * Response-like interface similar to fetch Response
 */
export interface TokenStreamResponse {
  /**
   * Collect all events and return as StreamResult
   */
  json(): Promise<StreamResult>;

  /**
   * Collect all tokens from blocks
   */
  tokens(): Promise<DetailedToken[] | CompactToken[]>;

  /**
   * Collect all TSV output
   */
  text(): Promise<string>;

  /**
   * Get the underlying ReadableStream
   */
  readonly body: ReadableStream<StreamEvent>;

  /**
   * Convert to SSE Response for HTTP streaming
   */
  toSSEResponse(init?: ResponseInit): Response;

  /**
   * Async iterator for consuming events
   */
  [Symbol.asyncIterator](): AsyncIterableIterator<StreamEvent>;
}
