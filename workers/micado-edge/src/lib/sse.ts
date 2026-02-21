import type { ResponseInit } from "./http.js";
import type { SSEWriter } from "../types.js";

const encoder = new TextEncoder();

export function encodeSSEEvent(event: string, data: unknown): Uint8Array {
  return encoder.encode(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`);
}

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

export function createSSEResponse(
  readable: ReadableStream<Uint8Array>,
  init: ResponseInit = {}
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
