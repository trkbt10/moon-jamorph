import type { Runtime, TokenFormat } from "../types.js";
import {
  streamTokenize,
  normalizeStreamOptions,
  createSSEResponse,
  createSSEWriter,
  type StreamOptions,
  type StreamOptionsInput,
  type TokenizerLike,
} from "@trkbt10/micado-streaming";

export { normalizeStreamOptions };
export type { StreamOptions, StreamOptionsInput };

export interface TokenizeStreamParams {
  text: string;
  format: TokenFormat;
  options: StreamOptions;
  runtime: Runtime;
}

/**
 * Adapt Runtime to TokenizerLike interface
 */
function runtimeToTokenizerLike(runtime: Runtime): TokenizerLike {
  return {
    tokenizeTSV: (text: string) => runtime.tokenizeTSV(text),
    profile: runtime.stats.profile,
    stats: {
      entryCount: runtime.stats.entryCount,
      bytes: runtime.stats.dictionaryBytes,
      maxSurfaceLength: runtime.stats.maxSurfaceLength,
      connectionIdCount: runtime.stats.connectionIdCount,
    },
  };
}

export function createTokenizeStreamResponse({
  text,
  format,
  options,
  runtime,
}: TokenizeStreamParams): Response {
  const { readable, writable } = new TransformStream<Uint8Array, Uint8Array>();
  const writer = writable.getWriter();
  const sseWriter = createSSEWriter(writer);

  const tokenizer = runtimeToTokenizerLike(runtime);

  (async () => {
    try {
      await streamTokenize({
        text,
        format,
        options,
        tokenizer,
        send: sseWriter.send,
      });
    } catch (error: unknown) {
      const message = error instanceof Error ? error.message : String(error);
      await sseWriter.send("error", { type: "error", message });
    } finally {
      await sseWriter.close();
    }
  })();

  return createSSEResponse(readable);
}
