// Types
export type {
  BlockReason,
  CompactToken,
  DetailedToken,
  QuoteState,
  ScanResult,
  SSEWriter,
  StreamBlockEvent,
  StreamDoneEvent,
  StreamErrorEvent,
  StreamEvent,
  StreamMetaEvent,
  StreamOptions,
  StreamOptionsInput,
  StreamResult,
  StreamWindowEvent,
  Token,
  TokenFormat,
  TokenizerLike,
  TokenizerStats,
  TokenStreamResponse,
  TokenStreamWriter,
} from "./types.js";

// Options
export { normalizeFormat, normalizeStreamOptions, parseBoolean, normalizeInt } from "./options.js";

// Parser
export {
  normalizeBlockPayload,
  parseTokensFromTSV,
  toCompactToken,
  tokensToTSV,
  type BlockPayload,
} from "./parser.js";

// Quote boundary detection
export { createQuoteState, scanForBoundary } from "./quote-boundary.js";

// Pending tokens management
export {
  consumeBlockTokens,
  dropConsumedTokens,
  findForcedBoundary,
  mergePendingTokens,
  tokenKey,
} from "./pending-tokens.js";

// Engine
export {
  generateTokenStream,
  streamTokenize,
  type GenerateTokenStreamParams,
  type StreamTokenizeParams,
} from "./engine.js";

// SSE utilities
export {
  createSSEResponse,
  createSSEWriter,
  encodeSSEEvent,
  type SSEResponseInit,
} from "./sse.js";

// Response
export { createTokenStreamResponse } from "./response.js";

// Writer (main API)
export { createStreamingResponse, createTokenStreamWriter } from "./writer.js";
