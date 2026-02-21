#!/usr/bin/env node

import { spawn } from "node:child_process";
import { readdir, readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = dirname(fileURLToPath(import.meta.url));
const workerDir = resolve(scriptDir, "..");
const repoRoot = resolve(workerDir, "..", "..");
const fixturesDir = resolve(repoRoot, "fixtures", "long_texts");

function pickPort() {
  const envPort = Number.parseInt(process.env.SSE_TEST_PORT ?? "", 10);
  if (Number.isFinite(envPort) && envPort > 0) {
    return envPort;
  }
  return 38000 + Math.floor(Math.random() * 2000);
}

async function fetchWithTimeout(url, options = {}, timeoutMs = 3000) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(new Error("timeout")), timeoutMs);
  try {
    return await fetch(url, {
      ...options,
      signal: controller.signal,
    });
  } finally {
    clearTimeout(timer);
  }
}

function sleep(ms) {
  return new Promise((resolvePromise) => setTimeout(resolvePromise, ms));
}

async function withTimeout(promise, timeoutMs, label) {
  let timer = null;
  try {
    return await Promise.race([
      promise,
      new Promise((_, rejectPromise) => {
        timer = setTimeout(() => {
          rejectPromise(new Error(`${label} timed out after ${timeoutMs}ms`));
        }, timeoutMs);
      }),
    ]);
  } finally {
    if (timer) {
      clearTimeout(timer);
    }
  }
}

function parseSSEEvent(rawChunk) {
  const lines = rawChunk.split(/\r?\n/);
  let event = "message";
  const dataLines = [];
  for (const line of lines) {
    if (line.startsWith("event:")) {
      event = line.slice("event:".length).trim();
      continue;
    }
    if (line.startsWith("data:")) {
      dataLines.push(line.slice("data:".length).trim());
    }
  }
  let data = null;
  if (dataLines.length > 0) {
    data = JSON.parse(dataLines.join("\n"));
  }
  return { event, data };
}

async function readSSEStream(response) {
  if (!response.ok) {
    const text = await response.text();
    throw new Error(`HTTP ${response.status}: ${text}`);
  }
  if (!response.body) {
    throw new Error("response body is empty");
  }

  const decoder = new TextDecoder();
  const reader = response.body.getReader();
  let buffer = "";
  const events = [];

  while (true) {
    const { value, done } = await reader.read();
    if (done) {
      break;
    }
    buffer += decoder.decode(value, { stream: true });
    while (true) {
      const boundary = buffer.indexOf("\n\n");
      if (boundary < 0) {
        break;
      }
      const chunk = buffer.slice(0, boundary);
      buffer = buffer.slice(boundary + 2);
      if (!chunk.trim()) {
        continue;
      }
      events.push(parseSSEEvent(chunk));
    }
  }

  if (buffer.trim()) {
    events.push(parseSSEEvent(buffer));
  }
  return events;
}

function validateEvents({ fileName, textLength, events }) {
  const grouped = {
    meta: events.filter((item) => item.event === "meta"),
    window: events.filter((item) => item.event === "window"),
    block: events.filter((item) => item.event === "block"),
    done: events.filter((item) => item.event === "done"),
    error: events.filter((item) => item.event === "error"),
  };

  if (grouped.error.length > 0) {
    throw new Error(
      `${fileName}: error event received: ${JSON.stringify(grouped.error[grouped.error.length - 1].data)}`,
    );
  }
  if (grouped.meta.length !== 1) {
    throw new Error(`${fileName}: meta event count must be 1 (actual=${grouped.meta.length})`);
  }
  if (grouped.done.length !== 1) {
    throw new Error(`${fileName}: done event count must be 1 (actual=${grouped.done.length})`);
  }
  if (grouped.block.length === 0) {
    throw new Error(`${fileName}: block event must be at least 1`);
  }
  if (events[0]?.event !== "meta") {
    throw new Error(`${fileName}: first event must be meta (actual=${events[0]?.event ?? "none"})`);
  }
  if (events[events.length - 1]?.event !== "done") {
    throw new Error(
      `${fileName}: last event must be done (actual=${events[events.length - 1]?.event ?? "none"})`,
    );
  }

  const done = grouped.done[0].data;
  if (done.finalCursor !== textLength || done.textLength !== textLength) {
    throw new Error(
      `${fileName}: done mismatch finalCursor=${done.finalCursor}, textLength=${done.textLength}, expected=${textLength}`,
    );
  }

  const blocks = grouped.block.map((item) => item.data);
  blocks.sort((a, b) => a.index - b.index);

  let cursor = 0;
  let joinedText = "";
  for (const block of blocks) {
    if (block.start !== cursor) {
      throw new Error(
        `${fileName}: non-contiguous block index=${block.index}, start=${block.start}, expected=${cursor}`,
      );
    }
    if (block.end < block.start) {
      throw new Error(
        `${fileName}: invalid block range index=${block.index}, start=${block.start}, end=${block.end}`,
      );
    }
    if (typeof block.text !== "string") {
      throw new Error(`${fileName}: block.text is missing at index=${block.index}`);
    }
    if (block.text.length !== block.charLength) {
      throw new Error(
        `${fileName}: block.charLength mismatch at index=${block.index}, text.length=${block.text.length}, charLength=${block.charLength}`,
      );
    }
    joinedText += block.text;
    cursor = block.end;
  }
  if (cursor !== textLength) {
    throw new Error(`${fileName}: final block end=${cursor}, expected=${textLength}`);
  }
  if (joinedText.length !== textLength) {
    throw new Error(
      `${fileName}: joined block text length mismatch joined=${joinedText.length}, expected=${textLength}`,
    );
  }

  const reasonCounts = new Map();
  for (const block of blocks) {
    reasonCounts.set(block.reason, (reasonCounts.get(block.reason) ?? 0) + 1);
  }

  return {
    fileName,
    textLength,
    firstEvent: events[0].event,
    lastEvent: events[events.length - 1].event,
    eventCount: events.length,
    windows: grouped.window.length,
    blocks: blocks.length,
    done,
    meta: grouped.meta[0].data,
    firstBlock: blocks[0],
    reasons: Object.fromEntries(reasonCounts),
  };
}

async function waitForHealth(workerBaseURL, wranglerState) {
  const deadline = Date.now() + 180_000;
  let attempts = 0;
  while (Date.now() < deadline) {
    attempts += 1;
    if (wranglerState.exited) {
      throw new Error(
        `wrangler dev exited before health check: code=${wranglerState.exited.code} signal=${wranglerState.exited.signal}\n${wranglerState.logs.join("\n")}`,
      );
    }
    try {
      const response = await fetchWithTimeout(`${workerBaseURL}/healthz?wait=1`, {}, 30_000);
      if (response.ok) {
        const payload = await response.json();
        if (payload?.state === "ready") {
          console.log(`[sse-long-texts] health ready after ${attempts} probes`);
          return;
        }
      } else if (attempts % 3 === 0) {
        const text = await response.text();
        console.log(`[sse-long-texts] health not ready: status=${response.status} body=${text}`);
      }
    } catch (error) {
      if (attempts % 10 === 0) {
        console.log(`[sse-long-texts] waiting health... attempts=${attempts} err=${error?.message ?? error}`);
      }
    }
    if (attempts % 10 === 0) {
      console.log(`[sse-long-texts] waiting health... attempts=${attempts}`);
    }
    await sleep(200);
  }
  throw new Error("timeout waiting for wrangler dev health endpoint");
}

async function runTestCase(filePath, workerBaseURL) {
  const fileName = filePath.split("/").pop();
  const text = await readFile(filePath, "utf8");
  console.log(`[sse-long-texts] start case=${fileName}`);
  const response = await fetchWithTimeout(
    `${workerBaseURL}/tokenize/stream`,
    {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        text,
        format: "compact",
        windowChars: 1024,
        overlapChars: 256,
        forceFlushChars: 4096,
        notifyWindow: true,
        includeText: true,
      }),
    },
    60_000,
  );
  const events = await withTimeout(
    readSSEStream(response),
    120_000,
    `SSE stream read (${fileName})`,
  );
  const result = validateEvents({
    fileName,
    textLength: text.length,
    events,
  });
  if (result.firstBlock?.text) {
    const exact = result.firstBlock.text === text.slice(result.firstBlock.start, result.firstBlock.end);
    if (!exact) {
      throw new Error(`${fileName}: first block text mismatch with original slice`);
    }
  }
  return result;
}

async function main() {
  const files = (await readdir(fixturesDir))
    .filter((name) => name.endsWith(".txt"))
    .sort()
    .map((name) => resolve(fixturesDir, name));
  if (files.length === 0) {
    throw new Error(`no .txt files found under ${fixturesDir}`);
  }

  const port = pickPort();
  const workerBaseURL = `http://127.0.0.1:${port}`;
  console.log(`[sse-long-texts] boot worker=${workerBaseURL}`);
  const wrangler = spawn(
    "wrangler",
    ["dev", "--port", String(port), "--host", "127.0.0.1", "--local", "--inspector-port", "0"],
    {
      cwd: workerDir,
      stdio: ["ignore", "pipe", "pipe"],
      env: {
        ...process.env,
        CI: "1",
        WRANGLER_LOG: process.env.WRANGLER_LOG ?? "none",
        WRANGLER_LOG_PATH: process.env.WRANGLER_LOG_PATH ?? resolve(workerDir, ".wrangler/logs"),
      },
    },
  );
  const wranglerState = {
    exited: null,
    logs: [],
  };
  const pushWranglerLog = (line) => {
    wranglerState.logs.push(line);
    if (wranglerState.logs.length > 80) {
      wranglerState.logs.shift();
    }
  };
  wrangler.stdout?.on("data", (chunk) => {
    const text = String(chunk ?? "").trim();
    if (text) {
      pushWranglerLog(`[stdout] ${text}`);
    }
  });
  wrangler.stderr?.on("data", (chunk) => {
    const text = String(chunk ?? "").trim();
    if (text) {
      pushWranglerLog(`[stderr] ${text}`);
    }
  });
  wrangler.on("exit", (code, signal) => {
    wranglerState.exited = { code, signal };
  });

  const terminate = () => {
    if (!wrangler.killed) {
      wrangler.kill("SIGTERM");
    }
  };

  process.on("SIGINT", () => {
    terminate();
    process.exit(130);
  });
  process.on("SIGTERM", () => {
    terminate();
    process.exit(143);
  });

  try {
    await withTimeout(
      waitForHealth(workerBaseURL, wranglerState),
      200_000,
      "health check",
    );
    const results = [];
    for (const filePath of files) {
      const result = await runTestCase(filePath, workerBaseURL);
      results.push(result);
      console.log(
        `[sse-long-texts] ${result.fileName}: chars=${result.textLength} windows=${result.windows} blocks=${result.blocks} reasons=${JSON.stringify(result.reasons)}`,
      );
    }
    console.log(`[sse-long-texts] worker=${workerBaseURL}`);
    console.log("[sse-long-texts] all cases passed");
    console.log(JSON.stringify(results, null, 2));
  } finally {
    terminate();
    await sleep(500);
  }
}

main().catch((error) => {
  console.error(`[sse-long-texts] ${error?.stack ?? error}`);
  process.exit(1);
});
