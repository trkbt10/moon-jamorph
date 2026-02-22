import type { SSEWriter } from "./types.js";

const encoder = new TextEncoder();

/**
 * Encode an SSE event to bytes
 */
export function encodeSSEEvent(event: string, data: unknown): Uint8Array {
  return encoder.encode(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`);
}

/**
 * Create an SSE writer that wraps a WritableStreamDefaultWriter
 */
export function createSSEWriter(
  writer: WritableStreamDefaultWriter<Uint8Array>
): SSEWriter {
  let writerClosed = false;

  return {
    async send(event: string, payload: unknown): Promise<boolean> {
      if (writerClosed) {
        return false;
      }
      try {
        await writer.write(encodeSSEEvent(event, payload));
        return true;
      } catch {
        writerClosed = true;
        return false;
      }
    },

    async close(): Promise<void> {
      if (writerClosed) {
        return;
      }
      try {
        await writer.close();
      } catch {
        // Ignore close errors
      }
      writerClosed = true;
    },
  };
}

export interface SSEResponseInit {
  status?: number;
  headers?: Record<string, string>;
}

/**
 * Create an SSE Response from a ReadableStream
 */
export function createSSEResponse(
  readable: ReadableStream<Uint8Array>,
  init: SSEResponseInit = {}
): Response {
  return new Response(readable, {
    status: init.status ?? 200,
    headers: {
      "content-type": "text/event-stream; charset=utf-8",
      "cache-control": "no-cache, no-transform",
      connection: "keep-alive",
      ...(init.headers ?? {}),
    },
  });
}
