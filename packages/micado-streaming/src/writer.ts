import type {
  StreamEvent,
  StreamOptions,
  StreamOptionsInput,
  TokenizerLike,
  TokenStreamResponse,
  TokenStreamWriter,
} from "./types.js";
import { generateTokenStream, streamTokenize } from "./engine.js";
import { normalizeStreamOptions } from "./options.js";
import { createTokenStreamResponse } from "./response.js";
import { createSSEWriter } from "./sse.js";

/**
 * Implementation of TokenStreamWriter
 */
class TokenStreamWriterImpl implements TokenStreamWriter {
  private tokenizer: TokenizerLike;
  private options: StreamOptions;

  constructor(tokenizer: TokenizerLike, options: StreamOptions) {
    this.tokenizer = tokenizer;
    this.options = options;
  }

  /**
   * Synchronous generator for consuming events
   */
  *write(text: string): IterableIterator<StreamEvent> {
    yield* generateTokenStream({
      text,
      format: this.options.format,
      options: this.options,
      tokenizer: this.tokenizer,
    });
  }

  /**
   * Get a ReadableStream of events
   */
  stream(text: string): ReadableStream<StreamEvent> {
    const tokenizer = this.tokenizer;
    const options = this.options;
    const format = this.options.format;

    return new ReadableStream<StreamEvent>({
      start(controller) {
        const generator = generateTokenStream({
          text,
          format,
          options,
          tokenizer,
        });

        for (const event of generator) {
          controller.enqueue(event);
        }
        controller.close();
      },
    });
  }

  /**
   * Get a Response-like object with .json(), .tokens(), .text() methods
   */
  response(text: string): TokenStreamResponse {
    return createTokenStreamResponse(this.stream(text));
  }
}

/**
 * Create a TokenStreamWriter for streaming tokenization
 */
export function createTokenStreamWriter(
  tokenizer: TokenizerLike,
  options: StreamOptionsInput = {}
): TokenStreamWriter {
  const normalizedOptions = normalizeStreamOptions(options);
  return new TokenStreamWriterImpl(tokenizer, normalizedOptions);
}

/**
 * Create an SSE streaming response for Workers
 */
export function createStreamingResponse(
  tokenizer: TokenizerLike,
  text: string,
  options: StreamOptionsInput = {}
): Response {
  const normalizedOptions = normalizeStreamOptions(options);
  const { readable, writable } = new TransformStream<Uint8Array, Uint8Array>();
  const writer = writable.getWriter();
  const sseWriter = createSSEWriter(writer);

  // Run tokenization in the background
  (async () => {
    try {
      await streamTokenize({
        text,
        format: normalizedOptions.format,
        options: normalizedOptions,
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

  return new Response(readable, {
    status: 200,
    headers: {
      "content-type": "text/event-stream; charset=utf-8",
      "cache-control": "no-cache, no-transform",
      connection: "keep-alive",
    },
  });
}
