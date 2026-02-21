import { getRuntimeStatus, getRuntimeSync, warmRuntimeInBackground } from "./runtime.mjs";
import { createSSEResponse, createSSEWriter } from "./sse.mjs";

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function buildStatusPayload(index) {
  const runtime = getRuntimeSync();
  const status = getRuntimeStatus();
  return {
    index,
    ok: status.state === "ready",
    runtime: "micado-wasm",
    ...status,
    ...(runtime ? runtime.stats : {}),
  };
}

export function createHealthzWaitSSE({ ctx, intervalMs, timeoutMs }) {
  const { readable, writable } = new TransformStream();
  const writer = writable.getWriter();
  const sseWriter = createSSEWriter(writer);

  (async () => {
    const startedAt = Date.now();
    const warmPromise = warmRuntimeInBackground();
    if (warmPromise && typeof ctx?.waitUntil === "function") {
      ctx.waitUntil(warmPromise);
    }

    let index = 0;
    const sentMeta = await sseWriter.send("meta", {
      runtime: "micado-wasm",
      intervalMs,
      timeoutMs,
      startedAt: new Date(startedAt).toISOString(),
    });
    if (!sentMeta) {
      return;
    }

    while (true) {
      const payload = buildStatusPayload(index);
      const sentStatus = await sseWriter.send("status", payload);
      if (!sentStatus) {
        return;
      }

      if (payload.state === "ready") {
        await sseWriter.send("done", payload);
        return;
      }
      if (payload.state === "error") {
        await sseWriter.send("error", payload);
        return;
      }

      if (Date.now() - startedAt >= timeoutMs) {
        await sseWriter.send("timeout", {
          ...payload,
          message: `timeout after ${timeoutMs}ms`,
        });
        return;
      }

      index += 1;
      await sleep(intervalMs);
    }
  })()
    .catch(async (error) => {
      await sseWriter.send("error", {
        message: String(error?.message ?? error),
      });
    })
    .finally(() => sseWriter.close());

  return createSSEResponse(readable);
}
