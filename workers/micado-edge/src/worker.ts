import type { Runtime, TokenFormat } from "./types.js";
import type { StreamOptions } from "./lib/streaming.js";
import {
  htmlResponse,
  jsonResponse,
  normalizeInt,
  parseBoolean,
} from "./lib/http.js";
import { createHealthzWaitSSE } from "./lib/healthz-stream.js";
import {
  ServiceUnavailableError,
  getRuntime,
  getRuntimeStatus,
  getRuntimeSync,
  warmRuntimeInBackground,
} from "./lib/runtime.js";
import {
  normalizeStreamOptions,
  createTokenizeStreamResponse,
} from "./lib/streaming.js";
import { parseTokensFromTSV } from "./lib/tokenize.js";
import { SSE_CHECK_UI } from "./ui/sse-check-ui.mjs";

function normalizeFormat(format: string | null | undefined): TokenFormat {
  const value = String(format ?? "detailed").toLowerCase();
  if (value === "tsv" || value === "detailed" || value === "compact") {
    return value;
  }
  return "detailed";
}

interface TokenizeInput {
  text: string;
  format: TokenFormat;
}

async function readTokenizeInput(request: Request): Promise<TokenizeInput> {
  if (request.method === "GET") {
    const url = new URL(request.url);
    return {
      text: url.searchParams.get("text") ?? "",
      format: normalizeFormat(url.searchParams.get("format") ?? "detailed"),
    };
  }
  if (request.method === "POST") {
    const contentType = request.headers.get("content-type") ?? "";
    if (!contentType.includes("application/json")) {
      throw new Error("POST /tokenize requires application/json");
    }
    const body = (await request.json()) as { text?: string; format?: string };
    return {
      text: String(body?.text ?? ""),
      format: normalizeFormat(body?.format ?? "detailed"),
    };
  }
  throw new Error("Only GET/POST are supported for /tokenize");
}

interface TokenizeStreamInput {
  text: string;
  format: TokenFormat;
  options: StreamOptions;
}

async function readTokenizeStreamInput(
  request: Request
): Promise<TokenizeStreamInput> {
  if (request.method === "GET") {
    const url = new URL(request.url);
    const format = normalizeFormat(url.searchParams.get("format") ?? "compact");
    return {
      text: url.searchParams.get("text") ?? "",
      format,
      options: normalizeStreamOptions({
        format,
        windowChars: url.searchParams.get("windowChars") ?? undefined,
        overlapChars: url.searchParams.get("overlapChars") ?? undefined,
        forceFlushChars: url.searchParams.get("forceFlushChars") ?? undefined,
        notifyWindow: url.searchParams.get("notifyWindow") ?? undefined,
        includeText: url.searchParams.get("includeText") ?? undefined,
      }),
    };
  }
  if (request.method === "POST") {
    const contentType = request.headers.get("content-type") ?? "";
    if (!contentType.includes("application/json")) {
      throw new Error("POST /tokenize/stream requires application/json");
    }
    const body = (await request.json()) as {
      text?: string;
      format?: string;
      windowChars?: string | number;
      overlapChars?: string | number;
      forceFlushChars?: string | number;
      notifyWindow?: string | boolean;
      includeText?: string | boolean;
    };
    const format = normalizeFormat(body?.format ?? "compact");
    return {
      text: String(body?.text ?? ""),
      format,
      options: normalizeStreamOptions({ ...body, format }),
    };
  }
  throw new Error("Only GET/POST are supported for /tokenize/stream");
}

async function handleTokenize(request: Request): Promise<Response> {
  const { text, format } = await readTokenizeInput(request);
  if (!text) {
    return jsonResponse({ error: "text is required" }, { status: 400 });
  }

  let runtime: Runtime;
  try {
    runtime = await getRuntime();
  } catch (error) {
    throw new ServiceUnavailableError("runtime initialization failed", error);
  }

  const tsv = runtime.tokenizeTSV(text);
  if (format === "tsv") {
    return new Response(tsv, {
      status: 200,
      headers: { "content-type": "text/plain; charset=utf-8" },
    });
  }
  const tokens =
    format === "detailed"
      ? parseTokensFromTSV(tsv, true)
      : parseTokensFromTSV(tsv, false);
  return jsonResponse({
    profile: runtime.stats.profile,
    format,
    count: tokens.length,
    tokens,
  });
}

async function handleTokenizeStream(request: Request): Promise<Response> {
  const { text, format, options } = await readTokenizeStreamInput(request);
  if (!text) {
    return jsonResponse({ error: "text is required" }, { status: 400 });
  }

  let runtime: Runtime;
  try {
    runtime = await getRuntime();
  } catch (error) {
    throw new ServiceUnavailableError("runtime initialization failed", error);
  }

  return createTokenizeStreamResponse({
    text,
    format,
    options,
    runtime,
  });
}

function serviceUnavailable(error: ServiceUnavailableError): Response {
  return jsonResponse(
    {
      error: error.message,
      cause: String(
        error.cause instanceof Error
          ? error.cause.message
          : error.cause ?? ""
      ),
      ...getRuntimeStatus(),
    },
    { status: 503, headers: { "retry-after": "1" } }
  );
}

function warmRuntime(ctx?: ExecutionContext): void {
  const warmPromise = warmRuntimeInBackground();
  if (warmPromise && typeof ctx?.waitUntil === "function") {
    ctx.waitUntil(warmPromise);
  }
}

export default {
  async fetch(
    request: Request,
    _env: unknown,
    ctx: ExecutionContext
  ): Promise<Response> {
    const url = new URL(request.url);

    if (url.pathname === "/healthz") {
      const wait = parseBoolean(url.searchParams.get("wait"), false);
      const wantsSSE =
        parseBoolean(url.searchParams.get("sse"), false) ||
        (request.headers.get("accept") ?? "").includes("text/event-stream");
      if (wait && wantsSSE) {
        const intervalMs = normalizeInt(
          url.searchParams.get("intervalMs"),
          250,
          50,
          5000
        );
        const timeoutMs = normalizeInt(
          url.searchParams.get("timeoutMs"),
          120000,
          1000,
          600000
        );
        return createHealthzWaitSSE({
          ctx,
          intervalMs,
          timeoutMs,
        });
      }
      if (wait) {
        try {
          const runtime = await getRuntime();
          return jsonResponse({
            ok: true,
            runtime: "micado-wasm",
            ...runtime.stats,
            ...getRuntimeStatus(),
          });
        } catch (error: unknown) {
          const message = error instanceof Error ? error.message : String(error);
          return jsonResponse(
            {
              ok: false,
              runtime: "micado-wasm",
              error: message,
              ...getRuntimeStatus(),
            },
            { status: 503 }
          );
        }
      }

      if (!getRuntimeSync()) {
        warmRuntime(ctx);
      }
      const runtime = getRuntimeSync();
      if (runtime) {
        return jsonResponse({
          ok: true,
          runtime: "micado-wasm",
          ...runtime.stats,
          ...getRuntimeStatus(),
        });
      }
      const status = getRuntimeStatus();
      const statusCode = status.state === "error" ? 503 : 200;
      return jsonResponse(
        {
          ok: statusCode < 500,
          runtime: "micado-wasm",
          ...status,
        },
        { status: statusCode }
      );
    }

    if (url.pathname === "/tokenize") {
      try {
        return await handleTokenize(request);
      } catch (error) {
        if (error instanceof ServiceUnavailableError) {
          return serviceUnavailable(error);
        }
        const message = error instanceof Error ? error.message : String(error);
        return jsonResponse({ error: message }, { status: 400 });
      }
    }

    if (url.pathname === "/tokenize/stream") {
      try {
        return await handleTokenizeStream(request);
      } catch (error) {
        if (error instanceof ServiceUnavailableError) {
          return serviceUnavailable(error);
        }
        const message = error instanceof Error ? error.message : String(error);
        return jsonResponse({ error: message }, { status: 400 });
      }
    }

    if (url.pathname === "/_sse-check") {
      warmRuntime(ctx);
      return htmlResponse(SSE_CHECK_UI);
    }

    return jsonResponse(
      {
        service: "micado-edge",
        routes: [
          "/healthz",
          "/healthz?wait=1",
          "/healthz?wait=1&sse=1",
          "/tokenize?text=...",
          "POST /tokenize",
          "/tokenize/stream",
          "/_sse-check",
        ],
      },
      { status: 200 }
    );
  },
};
