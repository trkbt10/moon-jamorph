import type { Runtime, RuntimeStatus } from "../types.js";
import {
  getRuntimeStatus,
  getRuntimeSync,
  warmRuntimeInBackground,
} from "./runtime.js";
import { createSSEResponse, createSSEWriter } from "./sse.js";

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

interface StatusPayload extends RuntimeStatus {
  index: number;
  ok: boolean;
  runtime: string;
  profile?: string;
  sourceMode?: string;
  entryLimit?: number;
  targetDeflateBytes?: number;
  dictionaryCompressedBytes?: number;
  dictionaryBytes?: number;
  entryCount?: number;
  maxSurfaceLength?: number;
  connectionIdCount?: number;
}

function buildStatusPayload(index: number): StatusPayload {
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

export interface HealthzWaitSSEOptions {
  ctx?: ExecutionContext;
  intervalMs: number;
  timeoutMs: number;
}

export function createHealthzWaitSSE({
  ctx,
  intervalMs,
  timeoutMs,
}: HealthzWaitSSEOptions): Response {
  const { readable, writable } = new TransformStream<Uint8Array, Uint8Array>();
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
    .catch(async (error: unknown) => {
      const message = error instanceof Error ? error.message : String(error);
      await sseWriter.send("error", { message });
    })
    .finally(() => sseWriter.close());

  return createSSEResponse(readable);
}
