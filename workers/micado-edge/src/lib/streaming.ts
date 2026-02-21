import type { Runtime, StreamOptions, TokenFormat } from "../types.js";
import { streamTokenize } from "./streaming/engine.js";
import { normalizeStreamOptions } from "./streaming/options.js";
import { createSSEResponse, createSSEWriter } from "./sse.js";

export { normalizeStreamOptions };

export interface TokenizeStreamParams {
  text: string;
  format: TokenFormat;
  options: StreamOptions;
  runtime: Runtime;
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

  (async () => {
    try {
      await streamTokenize({
        text,
        format,
        options,
        runtime,
        send: sseWriter.send,
      });
    } catch (error: unknown) {
      const message = error instanceof Error ? error.message : String(error);
      await sseWriter.send("error", { message });
    } finally {
      await sseWriter.close();
    }
  })();

  return createSSEResponse(readable);
}
