#!/usr/bin/env node

import { mkdir, readdir, readFile, rm, stat } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";
import { gzipSync } from "node:zlib";

function parseByteBudget(raw) {
  const value = String(raw ?? "").trim();
  const m = value.match(/^(\d+(?:\.\d+)?)\s*([kmgt]?i?b)?$/i);
  if (!m) {
    throw new Error(`invalid byte budget: ${raw}`);
  }
  const amount = Number.parseFloat(m[1]);
  const unit = (m[2] ?? "b").toLowerCase();
  const unitMap = {
    b: 1,
    kb: 1000,
    mb: 1000 * 1000,
    gb: 1000 * 1000 * 1000,
    kib: 1024,
    mib: 1024 * 1024,
    gib: 1024 * 1024 * 1024,
  };
  const scale = unitMap[unit];
  if (!scale) {
    throw new Error(`unsupported byte unit: ${unit}`);
  }
  return Math.round(amount * scale);
}

function unitToBytes(value, unit) {
  return parseByteBudget(`${value}${unit}`);
}

function bytesToMiB(bytes) {
  return (bytes / (1024 * 1024)).toFixed(3);
}

function parseGzipFromWranglerOutput(output) {
  const totalLine = output.match(
    /Total Upload:\s*([0-9.]+)\s*([KMGT]?i?B|B)\s*\/\s*gzip:\s*([0-9.]+)\s*([KMGT]?i?B|B)/i,
  );
  if (totalLine) {
    return {
      totalBytes: unitToBytes(totalLine[1], totalLine[2]),
      gzipBytes: unitToBytes(totalLine[3], totalLine[4]),
    };
  }
  const gzipLine = output.match(/gzip:\s*([0-9.]+)\s*([KMGT]?i?B|B)/i);
  if (gzipLine) {
    return {
      totalBytes: null,
      gzipBytes: unitToBytes(gzipLine[1], gzipLine[2]),
    };
  }
  return null;
}

async function collectFilesRecursive(rootDir) {
  const files = [];
  const stack = [rootDir];
  while (stack.length > 0) {
    const current = stack.pop();
    const entries = await readdir(current, { withFileTypes: true });
    for (const entry of entries) {
      const fullPath = resolve(current, entry.name);
      if (entry.isDirectory()) {
        stack.push(fullPath);
      } else if (entry.isFile()) {
        files.push(fullPath);
      }
    }
  }
  return files.sort();
}

async function calculateFromDryRunOutput(outDir) {
  const files = await collectFilesRecursive(outDir);
  const included = [];
  for (const filePath of files) {
    if (filePath.endsWith("/README.md") || filePath.endsWith("\\README.md")) {
      continue;
    }
    if (filePath.endsWith(".map")) {
      continue;
    }
    const [fileStats, fileBytes] = await Promise.all([stat(filePath), readFile(filePath)]);
    const gzipBytes = gzipSync(fileBytes, { level: 9 }).byteLength;
    included.push({
      path: filePath,
      bytes: fileStats.size,
      gzipBytes,
    });
  }
  const totalBytes = included.reduce((acc, item) => acc + item.bytes, 0);
  const gzipBytes = included.reduce((acc, item) => acc + item.gzipBytes, 0);
  return {
    method: "dry-run-files",
    totalBytes,
    gzipBytes,
    files: included,
  };
}

async function main() {
  const scriptDir = dirname(fileURLToPath(import.meta.url));
  const workerDir = resolve(scriptDir, "..");
  const dryRunOutDir = resolve(workerDir, ".wrangler", "deploy-dry-run");
  const generatedManifestPath = resolve(workerDir, "src", "generated", "manifest.json");
  const wranglerLogPath = resolve(workerDir, ".wrangler", "logs");
  const budget = parseByteBudget(process.env.CF_WORKER_GZIP_BUDGET ?? "10MB");
  await mkdir(wranglerLogPath, { recursive: true });
  await rm(dryRunOutDir, { recursive: true, force: true });

  const manifestRaw = await readFile(generatedManifestPath, "utf8");
  const manifest = JSON.parse(manifestRaw);

  const run = spawnSync(
    "wrangler",
    ["deploy", "--dry-run", "--outdir", ".wrangler/deploy-dry-run"],
    {
      cwd: workerDir,
      encoding: "utf8",
      env: {
        ...process.env,
        WRANGLER_LOG: process.env.WRANGLER_LOG ?? "none",
        WRANGLER_LOG_PATH: process.env.WRANGLER_LOG_PATH ?? wranglerLogPath,
      },
    },
  );

  const fullOutput = `${run.stdout ?? ""}\n${run.stderr ?? ""}`;
  if (run.status !== 0) {
    console.error(fullOutput.trim());
    throw new Error(`wrangler dry-run failed with exit code ${run.status ?? "unknown"}`);
  }

  const parsed = parseGzipFromWranglerOutput(fullOutput);
  const measured = parsed
    ? {
        method: "wrangler-output",
        gzipBytes: parsed.gzipBytes,
        totalBytes: parsed.totalBytes,
        files: null,
      }
    : await calculateFromDryRunOutput(dryRunOutDir);
  const headroom = budget - measured.gzipBytes;
  const summary = {
    measureMethod: measured.method,
    profile: manifest.profile,
    dictionaryDeflateBytes: manifest.dictionaryDeflate.bytes,
    wasmBytes: manifest.wasm.bytes,
    gzipBytes: measured.gzipBytes,
    totalBytes: measured.totalBytes,
    budgetBytes: budget,
    headroomBytes: headroom,
    files:
      measured.files?.map((item) => ({
        path: item.path.replace(`${workerDir}/`, ""),
        bytes: item.bytes,
        gzipBytes: item.gzipBytes,
      })) ?? null,
  };

  console.log("[check-size] summary");
  console.log(JSON.stringify(summary, null, 2));
  console.log(
    `[check-size] gzip=${measured.gzipBytes} bytes (${bytesToMiB(measured.gzipBytes)} MiB), budget=${budget} bytes (${bytesToMiB(budget)} MiB)`,
  );

  if (headroom < 0) {
    throw new Error(
      `gzip bundle exceeds budget by ${Math.abs(headroom)} bytes (${bytesToMiB(Math.abs(headroom))} MiB)`,
    );
  }
  console.log(`[check-size] headroom=${headroom} bytes (${bytesToMiB(headroom)} MiB)`);
}

main().catch((error) => {
  console.error(`[check-size] ${error?.stack ?? error}`);
  process.exit(1);
});
