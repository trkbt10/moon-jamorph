const encoder = new TextEncoder();

export function encodeSSEEvent(event, data) {
  return encoder.encode(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`);
}

export function createSSEWriter(writer) {
  let writerClosed = false;

  return {
    async send(event, payload) {
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

    async close() {
      if (writerClosed) {
        return;
      }
      try {
        await writer.close();
      } catch {}
      writerClosed = true;
    },
  };
}

export function createSSEResponse(readable, init = {}) {
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
