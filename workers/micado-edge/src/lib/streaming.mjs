import { streamTokenize } from "./streaming/engine.mjs";
import { normalizeStreamOptions } from "./streaming/options.mjs";
import { createSSEResponse, createSSEWriter } from "./sse.mjs";

export { normalizeStreamOptions };

export function createTokenizeStreamResponse({ text, format, options, runtime }) {
  const { readable, writable } = new TransformStream();
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
    } catch (error) {
      await sseWriter.send("error", {
        message: String(error?.message ?? error),
      });
    } finally {
      await sseWriter.close();
    }
  })();

  return createSSEResponse(readable);
}
