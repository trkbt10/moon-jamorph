#!/usr/bin/env node

import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = dirname(fileURLToPath(import.meta.url));
const workerDir = resolve(scriptDir, "..");

function pickPort() {
  const envPort = Number.parseInt(process.env.SSE_HEALTH_TEST_PORT ?? "", 10);
  if (Number.isFinite(envPort) && envPort > 0) {
    return envPort;
  }
  return 41000 + Math.floor(Math.random() * 1500);
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
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

async function withTimeout(promise, timeoutMs, label) {
  let timer = null;
  try {
    return await Promise.race([
      promise,
      new Promise((_, reject) => {
        timer = setTimeout(() => reject(new Error(`${label} timed out after ${timeoutMs}ms`)), timeoutMs);
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
  const data = dataLines.length > 0 ? JSON.parse(dataLines.join("\n")) : null;
  return { event, data };
}

async function waitWorkerBoot(baseURL, wranglerState) {
  const deadline = Date.now() + 120_000;
  while (Date.now() < deadline) {
    if (wranglerState.exited) {
      throw new Error(
        `wrangler exited before boot: code=${wranglerState.exited.code} signal=${wranglerState.exited.signal}\n${wranglerState.logs.join("\n")}`,
      );
    }
    try {
      const response = await fetchWithTimeout(`${baseURL}/healthz`, { method: "GET" }, 2500);
      if (response.ok) {
        return;
      }
    } catch {}
    await sleep(200);
  }
  throw new Error("timeout waiting worker boot");
}

async function readHealthzWaitSSE(baseURL) {
  const response = await fetchWithTimeout(
    `${baseURL}/healthz?wait=1&sse=1&intervalMs=100&timeoutMs=180000`,
    {
      method: "GET",
      headers: { accept: "text/event-stream" },
    },
    10000,
  );
  if (!response.ok || !response.body) {
    throw new Error(`healthz sse failed: status=${response.status} body=${await response.text()}`);
  }

  const events = [];
  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let buffer = "";
  while (true) {
    const { value, done } = await reader.read();
    if (done) {
      break;
    }
    buffer += decoder.decode(value, { stream: true });
    while (true) {
      const idx = buffer.indexOf("\n\n");
      if (idx < 0) {
        break;
      }
      const raw = buffer.slice(0, idx);
      buffer = buffer.slice(idx + 2);
      if (!raw.trim()) {
        continue;
      }
      events.push(parseSSEEvent(raw));
    }
  }
  if (buffer.trim()) {
    events.push(parseSSEEvent(buffer));
  }
  return events;
}

function validate(events) {
  const meta = events.filter((x) => x.event === "meta");
  const status = events.filter((x) => x.event === "status");
  const done = events.filter((x) => x.event === "done");
  const error = events.filter((x) => x.event === "error");
  const timeout = events.filter((x) => x.event === "timeout");

  assert.equal(meta.length, 1, "meta must be exactly one");
  assert.ok(status.length >= 1, "status must be at least one");
  assert.equal(error.length, 0, "error must be zero");
  assert.equal(timeout.length, 0, "timeout must be zero");
  assert.equal(done.length, 1, "done must be exactly one");
  assert.equal(done[0].data?.state, "ready", "done.state must be ready");

  return {
    eventCount: events.length,
    statusCount: status.length,
    firstStatus: status[0]?.data ?? null,
    done: done[0]?.data ?? null,
  };
}

async function main() {
  const port = pickPort();
  const workerBaseURL = `http://127.0.0.1:${port}`;
  console.log(`[test-healthz-sse] boot worker=${workerBaseURL}`);

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
  const wranglerState = { exited: null, logs: [] };
  const pushLog = (line) => {
    wranglerState.logs.push(line);
    if (wranglerState.logs.length > 80) {
      wranglerState.logs.shift();
    }
  };
  wrangler.stdout?.on("data", (chunk) => {
    const text = String(chunk ?? "").trim();
    if (text) {
      pushLog(`[stdout] ${text}`);
    }
  });
  wrangler.stderr?.on("data", (chunk) => {
    const text = String(chunk ?? "").trim();
    if (text) {
      pushLog(`[stderr] ${text}`);
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

  try {
    await withTimeout(waitWorkerBoot(workerBaseURL, wranglerState), 140_000, "worker boot");
    const events = await withTimeout(readHealthzWaitSSE(workerBaseURL), 200_000, "healthz wait sse");
    const summary = validate(events);
    console.log("[test-healthz-sse] ok");
    console.log(JSON.stringify(summary, null, 2));
  } finally {
    terminate();
    await sleep(500);
  }
}

main().catch((error) => {
  console.error(`[test-healthz-sse] ${error?.stack ?? error}`);
  process.exit(1);
});
