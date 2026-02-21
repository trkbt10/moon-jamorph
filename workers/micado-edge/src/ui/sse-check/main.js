const runBtn = document.getElementById("run");
const clearBtn = document.getElementById("clear");
const statusEl = document.getElementById("status");
const summaryEl = document.getElementById("summary");
const logEl = document.getElementById("log");
const endpointEl = document.getElementById("endpoint");
const fixtureFileEl = document.getElementById("fixtureFile");
const textEl = document.getElementById("text");
const formatEl = document.getElementById("format");
const windowCharsEl = document.getElementById("windowChars");
const overlapCharsEl = document.getElementById("overlapChars");
const forceFlushCharsEl = document.getElementById("forceFlushChars");

let currentAbort = null;
let isRunning = false;
const logLines = [];

function setStatus(text) {
  statusEl.textContent = text;
}

function pushLog(line) {
  logLines.push(line);
  if (logLines.length > 250) {
    logLines.shift();
  }
  logEl.textContent = logLines.join("\n");
}

function resetUI() {
  logLines.length = 0;
  logEl.textContent = "";
  summaryEl.textContent = "";
}

async function loadFixtureFile(file) {
  if (!file) {
    return;
  }
  const text = await file.text();
  textEl.value = text;
  setStatus(`loaded: ${file.name} (${text.length} chars)`);
}

function createTimeoutSignal(timeoutMs, outerSignal) {
  const controller = new AbortController();
  const timer = setTimeout(() => {
    controller.abort("timeout");
  }, timeoutMs);

  if (outerSignal) {
    if (outerSignal.aborted) {
      controller.abort(outerSignal.reason || "outer-abort");
    } else {
      outerSignal.addEventListener(
        "abort",
        () => {
          controller.abort(outerSignal.reason || "outer-abort");
        },
        { once: true },
      );
    }
  }

  return {
    signal: controller.signal,
    clear() {
      clearTimeout(timer);
    },
  };
}

async function fetchWithTimeout(url, init, timeoutMs, outerSignal) {
  const timed = createTimeoutSignal(timeoutMs, outerSignal);
  try {
    return await fetch(url, {
      ...init,
      signal: timed.signal,
    });
  } finally {
    timed.clear();
  }
}

function parseSSEChunk(raw) {
  const lines = raw.split(/\r?\n/);
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

function roundMs(value) {
  return Number(value.toFixed(1));
}

async function waitRuntimeReady(healthUrl, outerSignal) {
  const sseURL = new URL(healthUrl.toString());
  sseURL.searchParams.set("sse", "1");
  sseURL.searchParams.set("intervalMs", "250");
  sseURL.searchParams.set("timeoutMs", "120000");

  setStatus("warming runtime... (sse)");
  const response = await fetchWithTimeout(
    sseURL.toString(),
    {
      method: "GET",
      headers: { accept: "text/event-stream" },
    },
    10000,
    outerSignal,
  );
  if (!response.ok || !response.body) {
    const body = await response.text();
    throw new Error(`health SSE failed: HTTP ${response.status} ${body}`);
  }

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
      const event = parseSSEChunk(raw);
      if (event.event === "status") {
        const state = event.data?.state ?? "unknown";
        const elapsedMs = event.data?.elapsedMs ?? "-";
        const attempts = event.data?.attempts ?? "-";
        setStatus(`warming runtime... state=${state} elapsed=${elapsedMs}ms attempts=${attempts}`);
        continue;
      }
      if (event.event === "done") {
        return event.data;
      }
      if (event.event === "error") {
        throw new Error(`runtime error: ${JSON.stringify(event.data)}`);
      }
      if (event.event === "timeout") {
        throw new Error(`runtime warmup timeout: ${JSON.stringify(event.data)}`);
      }
    }
  }

  throw new Error("runtime warmup stream closed before done");
}

function validate(events, sourceText) {
  const grouped = {
    meta: events.filter((x) => x.event === "meta"),
    window: events.filter((x) => x.event === "window"),
    block: events.filter((x) => x.event === "block"),
    done: events.filter((x) => x.event === "done"),
    error: events.filter((x) => x.event === "error"),
  };
  const checks = [];
  checks.push({ name: "meta count == 1", ok: grouped.meta.length === 1 });
  checks.push({ name: "done count == 1", ok: grouped.done.length === 1 });
  checks.push({ name: "error count == 0", ok: grouped.error.length === 0 });
  checks.push({ name: "block count >= 1", ok: grouped.block.length >= 1 });
  checks.push({ name: "first event is meta", ok: events[0] && events[0].event === "meta" });
  checks.push({
    name: "last event is done",
    ok: events.length > 0 && events[events.length - 1].event === "done",
  });
  let cursor = 0;
  let joined = "";
  for (const item of grouped.block.map((x) => x.data).sort((a, b) => a.index - b.index)) {
    if (item.start !== cursor) {
      checks.push({ name: "contiguous blocks", ok: false });
      break;
    }
    cursor = item.end;
    if (typeof item.text === "string") {
      joined += item.text;
    }
  }
  checks.push({ name: "contiguous blocks", ok: cursor === sourceText.length });
  checks.push({ name: "missing check (joined block.text == input)", ok: joined === sourceText });
  const done = grouped.done[0] ? grouped.done[0].data : null;
  checks.push({
    name: "done.finalCursor == text.length",
    ok: done && done.finalCursor === sourceText.length && done.textLength === sourceText.length,
  });
  const reasons = {};
  for (const b of grouped.block) {
    const reason = String(b.data && b.data.reason ? b.data.reason : "unknown");
    reasons[reason] = (reasons[reason] || 0) + 1;
  }
  return {
    checks,
    ok: checks.every((c) => c.ok),
    counts: {
      events: events.length,
      windows: grouped.window.length,
      blocks: grouped.block.length,
    },
    sample: {
      meta: grouped.meta[0] ? grouped.meta[0].data : null,
      firstBlock: grouped.block[0] ? grouped.block[0].data : null,
      done,
    },
    reasons,
  };
}

async function run() {
  if (isRunning && currentAbort) {
    currentAbort.abort("superseded");
  }
  const controller = new AbortController();
  const previousAbort = currentAbort;
  currentAbort = controller;
  if (previousAbort && previousAbort !== controller) {
    previousAbort.abort("superseded");
  }
  isRunning = true;
  runBtn.disabled = true;
  resetUI();

  const text = textEl.value || "";
  if (!text) {
    setStatus("text is empty");
    isRunning = false;
    runBtn.disabled = false;
    return;
  }

  const endpoint = endpointEl.value || "/tokenize/stream";
  const endpointUrl = new URL(endpoint, location.href);
  const healthUrl = new URL("/healthz?wait=1", endpointUrl.origin);

  const body = {
    text,
    format: formatEl.value || "compact",
    windowChars: Number.parseInt(windowCharsEl.value || "1024", 10),
    overlapChars: Number.parseInt(overlapCharsEl.value || "256", 10),
    forceFlushChars: Number.parseInt(forceFlushCharsEl.value || "4096", 10),
    notifyWindow: true,
    includeText: true,
  };

  const runStartedAt = performance.now();
  let warmupDoneAt = null;
  let streamStartedAt = null;
  let streamDoneAt = null;
  let firstEventAt = null;
  let firstBlockAt = null;

  try {
    await waitRuntimeReady(healthUrl, controller.signal);
    warmupDoneAt = performance.now();
    setStatus("streaming...");

    streamStartedAt = performance.now();
    const response = await fetch(endpointUrl.toString(), {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(body),
      signal: controller.signal,
    });
    if (!response.ok || !response.body) {
      throw new Error(`HTTP ${response.status} ${await response.text()}`);
    }
    const reader = response.body.getReader();
    const decoder = new TextDecoder();
    const events = [];
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
        const event = parseSSEChunk(raw);
        if (firstEventAt == null) {
          firstEventAt = performance.now();
        }
        if (firstBlockAt == null && event.event === "block") {
          firstBlockAt = performance.now();
        }
        events.push(event);
        pushLog(`${event.event} ${JSON.stringify(event.data)}`);
      }
    }
    if (buffer.trim()) {
      const event = parseSSEChunk(buffer);
      if (firstEventAt == null) {
        firstEventAt = performance.now();
      }
      if (firstBlockAt == null && event.event === "block") {
        firstBlockAt = performance.now();
      }
      events.push(event);
      pushLog(`${event.event} ${JSON.stringify(event.data)}`);
    }
    streamDoneAt = performance.now();
    const result = validate(events, text);
    const timing = {
      warmupMs: warmupDoneAt == null ? null : roundMs(warmupDoneAt - runStartedAt),
      streamMs:
        streamStartedAt == null || streamDoneAt == null ? null : roundMs(streamDoneAt - streamStartedAt),
      totalMs: streamDoneAt == null ? null : roundMs(streamDoneAt - runStartedAt),
      firstEventMs:
        streamStartedAt == null || firstEventAt == null ? null : roundMs(firstEventAt - streamStartedAt),
      firstBlockMs:
        streamStartedAt == null || firstBlockAt == null ? null : roundMs(firstBlockAt - streamStartedAt),
    };
    if (timing.streamMs != null && timing.streamMs > 0) {
      timing.eventsPerSec = roundMs((events.length * 1000) / timing.streamMs);
      timing.blocksPerSec = roundMs((result.counts.blocks * 1000) / timing.streamMs);
    } else {
      timing.eventsPerSec = null;
      timing.blocksPerSec = null;
    }
    result.timing = timing;
    summaryEl.textContent = JSON.stringify(result, null, 2);
    if (result.ok) {
      setStatus(`ok (total ${timing.totalMs ?? "?"} ms, stream ${timing.streamMs ?? "?"} ms)`);
    } else {
      setStatus(`validation failed (total ${timing.totalMs ?? "?"} ms)`);
    }
  } catch (error) {
    if (controller.signal.aborted || error?.name === "AbortError") {
      setStatus("aborted (superseded)");
      return;
    }
    summaryEl.textContent = String(error && error.message ? error.message : error);
    setStatus("error");
  } finally {
    if (currentAbort === controller) {
      currentAbort = null;
    }
    isRunning = false;
    runBtn.disabled = false;
  }
}

runBtn.addEventListener("click", () => {
  run();
});
clearBtn.addEventListener("click", () => {
  if (currentAbort) {
    currentAbort.abort("clear");
  }
  resetUI();
  setStatus("idle");
});
fixtureFileEl?.addEventListener("change", async () => {
  const file = fixtureFileEl.files && fixtureFileEl.files.length > 0 ? fixtureFileEl.files[0] : null;
  try {
    await loadFixtureFile(file);
  } catch (error) {
    setStatus("failed to load file");
    summaryEl.textContent = String(error?.message ?? error);
  }
});
run();
