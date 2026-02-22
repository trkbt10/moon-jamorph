import type {
  CompactToken,
  DetailedToken,
  StreamBlockEvent,
  StreamDoneEvent,
  StreamEvent,
  StreamMetaEvent,
  StreamResult,
  TokenStreamResponse,
} from "./types.js";
import { createSSEResponse, encodeSSEEvent, type SSEResponseInit } from "./sse.js";

/**
 * Implementation of TokenStreamResponse
 */
export class TokenStreamResponseImpl implements TokenStreamResponse {
  private _body: ReadableStream<StreamEvent>;
  private _consumed = false;

  constructor(body: ReadableStream<StreamEvent>) {
    this._body = body;
  }

  get body(): ReadableStream<StreamEvent> {
    return this._body;
  }

  private async collectEvents(): Promise<StreamEvent[]> {
    if (this._consumed) {
      throw new Error("Response body already consumed");
    }
    this._consumed = true;

    const events: StreamEvent[] = [];
    const reader = this._body.getReader();
    try {
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        events.push(value);
      }
    } finally {
      reader.releaseLock();
    }
    return events;
  }

  async json(): Promise<StreamResult> {
    const events = await this.collectEvents();

    let meta: StreamMetaEvent | undefined;
    const blocks: StreamBlockEvent[] = [];
    let done: StreamDoneEvent | undefined;
    const allTokens: (DetailedToken | CompactToken)[] = [];

    for (const event of events) {
      switch (event.type) {
        case "meta":
          meta = event;
          break;
        case "block":
          blocks.push(event);
          if (event.tokens) {
            allTokens.push(...event.tokens);
          }
          break;
        case "done":
          done = event;
          break;
        case "error":
          throw new Error(event.message);
      }
    }

    if (!meta) {
      throw new Error("Missing meta event");
    }
    if (!done) {
      throw new Error("Missing done event");
    }

    return { meta, blocks, done, allTokens };
  }

  async tokens(): Promise<DetailedToken[] | CompactToken[]> {
    const result = await this.json();
    return result.allTokens;
  }

  async text(): Promise<string> {
    const events = await this.collectEvents();
    const tsvParts: string[] = [];

    for (const event of events) {
      if (event.type === "block" && event.tsv) {
        tsvParts.push(event.tsv);
      } else if (event.type === "block" && event.tokens) {
        // Convert tokens to TSV if not already in TSV format
        for (const token of event.tokens) {
          const mecabFeature =
            "mecab_feature" in token ? token.mecab_feature : token.pos_detail;
          tsvParts.push(
            `${token.surface}\t${token.pos_detail}\t${mecabFeature}\t${token.start_pos}\t${token.end_pos}`
          );
        }
      } else if (event.type === "error") {
        throw new Error(event.message);
      }
    }

    return tsvParts.join("\n");
  }

  toSSEResponse(init?: SSEResponseInit): Response {
    if (this._consumed) {
      throw new Error("Response body already consumed");
    }
    this._consumed = true;

    // Transform StreamEvent to SSE bytes
    const sseStream = this._body.pipeThrough(
      new TransformStream<StreamEvent, Uint8Array>({
        transform(event, controller) {
          controller.enqueue(encodeSSEEvent(event.type, event));
        },
      })
    );

    return createSSEResponse(sseStream, init);
  }

  async *[Symbol.asyncIterator](): AsyncIterableIterator<StreamEvent> {
    if (this._consumed) {
      throw new Error("Response body already consumed");
    }
    this._consumed = true;

    const reader = this._body.getReader();
    try {
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        yield value;
      }
    } finally {
      reader.releaseLock();
    }
  }
}

/**
 * Create a TokenStreamResponse from a ReadableStream of events
 */
export function createTokenStreamResponse(
  body: ReadableStream<StreamEvent>
): TokenStreamResponse {
  return new TokenStreamResponseImpl(body);
}
