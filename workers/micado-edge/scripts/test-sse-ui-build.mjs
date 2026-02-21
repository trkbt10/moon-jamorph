#!/usr/bin/env node

import { readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = dirname(fileURLToPath(import.meta.url));
const workerDir = resolve(scriptDir, "..");

const sourceHtmlPath = resolve(workerDir, "src", "ui", "sse-check", "index.html");
const sourceJsPath = resolve(workerDir, "src", "ui", "sse-check", "main.js");
const generatedPath = resolve(workerDir, "src", "ui", "generated", "sse-check-ui.mjs");

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

async function main() {
  const [sourceHtml, sourceJs] = await Promise.all([
    readFile(sourceHtmlPath, "utf8"),
    readFile(sourceJsPath, "utf8"),
  ]);
  const generated = await import(`file://${generatedPath}?t=${Date.now()}`);
  const html = generated.SSE_CHECK_UI;

  assert(typeof html === "string", "generated SSE_CHECK_UI must be string");
  assert(sourceHtml.includes('src="./main.js"'), "source HTML should keep external main.js script tag");
  assert(sourceJs.includes("waitRuntimeReady"), "source JS should define waitRuntimeReady");
  assert(html.includes("<script type=\"module\">"), "generated HTML should inline module script");
  assert(!html.includes('src="./main.js"'), "generated HTML should not keep external script tag");
  assert(html.includes("warming runtime..."), "generated HTML should include runtime warmup text");
  assert(html.includes("missing check"), "generated HTML should include missing-check logic");
  assert(html.includes("Run SSE check"), "generated HTML should include UI controls");

  console.log("[test-sse-ui-build] ok");
}

main().catch((error) => {
  console.error(`[test-sse-ui-build] ${error?.stack ?? error}`);
  process.exit(1);
});
