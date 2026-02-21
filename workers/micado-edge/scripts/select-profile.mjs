#!/usr/bin/env node

import { createReadStream } from "node:fs";
import { mkdir, readFile, readdir, rm, stat, writeFile, copyFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { createInterface } from "node:readline";
import { fileURLToPath } from "node:url";
import {
  DEFAULT_LIMITS,
  compileDicBinFromTSV,
  compressDicBinDeflate,
  resolveDefaultPaths,
} from "../../../tools/dict-compiler/scripts/web_dic_build_core.mjs";

const VALID_PROFILES = new Set(["tiny", "mini", "medium", "full"]);

function parseArgs(argv) {
  const args = {
    profile: process.env.MICADO_PROFILE ?? "fit",
    limit: null,
    targetDeflateBytes: process.env.MICADO_TARGET_DEFLATE_BYTES ?? "9000000",
    minLimit: process.env.MICADO_MIN_LIMIT ?? String(DEFAULT_LIMITS.medium),
    maxLimit: process.env.MICADO_MAX_LIMIT ?? String(DEFAULT_LIMITS.full),
    freqPath: process.env.WEB_FREQ_TSV ?? null,
    webTsvPath: process.env.WEB_TSV_PATH ?? null,
    matrixDefPath: process.env.WEB_MATRIX_DEF ?? null,
  };
  for (let i = 0; i < argv.length; i += 1) {
    const token = argv[i];
    if (token === "--profile" && argv[i + 1]) {
      args.profile = argv[i + 1];
      i += 1;
      continue;
    }
    if (token.startsWith("--profile=")) {
      args.profile = token.slice("--profile=".length);
      continue;
    }
    if (token === "--limit" && argv[i + 1]) {
      args.limit = argv[i + 1];
      i += 1;
      continue;
    }
    if (token.startsWith("--limit=")) {
      args.limit = token.slice("--limit=".length);
      continue;
    }
    if (token === "--target-deflate-bytes" && argv[i + 1]) {
      args.targetDeflateBytes = argv[i + 1];
      i += 1;
      continue;
    }
    if (token.startsWith("--target-deflate-bytes=")) {
      args.targetDeflateBytes = token.slice("--target-deflate-bytes=".length);
      continue;
    }
    if (token === "--min-limit" && argv[i + 1]) {
      args.minLimit = argv[i + 1];
      i += 1;
      continue;
    }
    if (token.startsWith("--min-limit=")) {
      args.minLimit = token.slice("--min-limit=".length);
      continue;
    }
    if (token === "--max-limit" && argv[i + 1]) {
      args.maxLimit = argv[i + 1];
      i += 1;
      continue;
    }
    if (token.startsWith("--max-limit=")) {
      args.maxLimit = token.slice("--max-limit=".length);
      continue;
    }
    if (token === "--freq-tsv" && argv[i + 1]) {
      args.freqPath = argv[i + 1];
      i += 1;
      continue;
    }
    if (token.startsWith("--freq-tsv=")) {
      args.freqPath = token.slice("--freq-tsv=".length);
      continue;
    }
    if (token === "--web-tsv" && argv[i + 1]) {
      args.webTsvPath = argv[i + 1];
      i += 1;
      continue;
    }
    if (token.startsWith("--web-tsv=")) {
      args.webTsvPath = token.slice("--web-tsv=".length);
      continue;
    }
    if (token === "--matrix-def" && argv[i + 1]) {
      args.matrixDefPath = argv[i + 1];
      i += 1;
      continue;
    }
    if (token.startsWith("--matrix-def=")) {
      args.matrixDefPath = token.slice("--matrix-def=".length);
    }
  }
  return args;
}

function parsePositiveInt(raw, key) {
  const value = Number.parseInt(String(raw), 10);
  if (!Number.isFinite(value) || value <= 0) {
    throw new Error(`invalid ${key}: ${raw}`);
  }
  return value;
}

function parsePositiveIntOrNull(raw, key) {
  if (raw === null || raw === undefined || raw === "") {
    return null;
  }
  return parsePositiveInt(raw, key);
}

async function pathExists(path) {
  try {
    await stat(path);
    return true;
  } catch {
    return false;
  }
}

function resolveDefaultFreqPath(repoRoot) {
  const primary = resolve(repoRoot, "tools/dict-compiler/resources/aozorahack.freq.tsv");
  const secondary = resolve(repoRoot, "tools/dict-compiler/resources/aozora_examples.freq.tsv");
  return { primary, secondary };
}

async function countNonEmptyLines(filePath) {
  const input = createReadStream(filePath, { encoding: "utf8" });
  const rl = createInterface({ input, crlfDelay: Infinity });
  let count = 0;
  for await (const line of rl) {
    if (line && !line.startsWith("#")) {
      count += 1;
    }
  }
  return count;
}

async function sha256Hex(filePath) {
  const { createHash } = await import("node:crypto");
  const buffer = await readFile(filePath);
  return createHash("sha256").update(buffer).digest("hex");
}

async function buildCustomDictionary({
  workerDir,
  repoRoot,
  limit,
  freqPath,
  webTsvPath,
  matrixDefPath,
}) {
  const customDir = resolve(workerDir, ".cache", "custom-dictionary");
  await mkdir(customDir, { recursive: true });
  const binPath = resolve(customDir, `custom.limit-${limit}.dic.bin`);
  const deflatePath = `${binPath}.deflate`;

  const compileResult = await compileDicBinFromTSV({
    inputPath: webTsvPath,
    outputPath: binPath,
    limit,
    freqPath,
    matrixDefPath,
  });
  const compressResult = await compressDicBinDeflate({
    inputPath: binPath,
    outputPath: deflatePath,
  });

  return {
    mode: "custom",
    profile: `custom-limit-${limit}`,
    limit,
    webTsvPath: resolve(webTsvPath),
    matrixDefPath: resolve(matrixDefPath),
    freqPath: freqPath ? resolve(freqPath) : null,
    binPath: compileResult.outputPath,
    deflatePath: compressResult.outputPath,
    binBytes: compileResult.bytes,
    deflateBytes: compressResult.outputBytes,
    entries: compileResult.entries,
    ids: compileResult.ids,
    ratio: compressResult.ratio,
  };
}

async function resolveBuildInputs({
  repoRoot,
  requestedWebTsvPath,
  requestedMatrixDefPath,
  requestedFreqPath,
  requiredLimit,
}) {
  const defaults = resolveDefaultPaths(repoRoot);
  const freqDefaults = resolveDefaultFreqPath(repoRoot);
  const webTsvPath = requestedWebTsvPath ? resolve(requestedWebTsvPath) : defaults.webTsvPath;
  const matrixDefPath = requestedMatrixDefPath
    ? resolve(requestedMatrixDefPath)
    : defaults.defaultMatrixDefPath;

  let freqPath = null;
  if (requestedFreqPath) {
    freqPath = resolve(requestedFreqPath);
  } else if (await pathExists(freqDefaults.primary)) {
    freqPath = freqDefaults.primary;
  } else if (await pathExists(freqDefaults.secondary)) {
    freqPath = freqDefaults.secondary;
  }

  if (!(await pathExists(webTsvPath))) {
    throw new Error(
      `web TSV not found: ${webTsvPath}; run tools/dict-compiler/scripts/build_web_dic_artifacts.mjs or pass --web-tsv`,
    );
  }
  if (!(await pathExists(matrixDefPath))) {
    throw new Error(
      `matrix.def not found: ${matrixDefPath}; pass --matrix-def or build ipadic cache first`,
    );
  }

  const availableRows = await countNonEmptyLines(webTsvPath);
  if (availableRows < requiredLimit) {
    throw new Error(
      `web TSV rows are insufficient: required=${requiredLimit}, available=${availableRows}; regenerate TSV with larger limit`,
    );
  }

  return {
    webTsvPath,
    matrixDefPath,
    freqPath,
    availableRows,
  };
}

async function fitDictionaryUnderTarget({
  workerDir,
  repoRoot,
  targetDeflateBytes,
  minLimit,
  maxLimit,
  webTsvPath,
  matrixDefPath,
  freqPath,
}) {
  const lowBound = minLimit;
  const highBound = maxLimit;
  if (lowBound > highBound) {
    throw new Error(`invalid range: min-limit=${lowBound} > max-limit=${highBound}`);
  }

  const attempts = [];
  const evaluated = new Map();
  const evaluate = async (limit) => {
    if (evaluated.has(limit)) {
      return evaluated.get(limit);
    }
    const result = await buildCustomDictionary({
      workerDir,
      repoRoot,
      limit,
      webTsvPath,
      matrixDefPath,
      freqPath,
    });
    attempts.push({
      limit: result.limit,
      entries: result.entries,
      deflateBytes: result.deflateBytes,
      ratio: Number(result.ratio.toFixed(4)),
    });
    evaluated.set(limit, result);
    return result;
  };

  let left = lowBound;
  let right = highBound;
  let bestUnder = null;
  let smallestOver = null;

  while (left <= right) {
    const mid = Math.floor((left + right) / 2);
    const current = await evaluate(mid);
    if (current.deflateBytes <= targetDeflateBytes) {
      if (!bestUnder || current.deflateBytes > bestUnder.deflateBytes) {
        bestUnder = current;
      }
      left = mid + 1;
    } else {
      if (!smallestOver || current.deflateBytes < smallestOver.deflateBytes) {
        smallestOver = current;
      }
      right = mid - 1;
    }
  }

  const selected = bestUnder ?? smallestOver;
  if (!selected) {
    throw new Error("fit search failed; no candidate dictionary was generated");
  }

  return {
    ...selected,
    mode: "fit",
    profile: `fit-${selected.limit}`,
    targetDeflateBytes,
    search: {
      minLimit: lowBound,
      maxLimit: highBound,
      attempts,
      foundUnderTarget: Boolean(bestUnder),
    },
  };
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const rawProfile = args.profile;
  const profile = String(rawProfile).toLowerCase();
  if (!VALID_PROFILES.has(profile) && profile !== "fit") {
    const expected = `${Array.from(VALID_PROFILES).join("|")}|fit`;
    throw new Error(`unknown profile: ${rawProfile}; expected ${expected}`);
  }

  const scriptDir = dirname(fileURLToPath(import.meta.url));
  const workerDir = resolve(scriptDir, "..");
  const repoRoot = resolve(workerDir, "..", "..");
  const sourceDist = resolve(repoRoot, "npm", "micado-wasm", "dist");
  const generatedDir = resolve(workerDir, "src", "generated");

  const sourceWasm = resolve(sourceDist, "micado_wasm.wasm");
  const outWasm = resolve(generatedDir, "micado_wasm.wasm");
  const outDictionary = resolve(generatedDir, "dictionary.dic.bin.deflate");
  const outProfileModule = resolve(generatedDir, "profile.mjs");
  const outManifest = resolve(generatedDir, "manifest.json");
  const request = {
    profile,
    limit: parsePositiveIntOrNull(args.limit, "--limit"),
    targetDeflateBytes: parsePositiveIntOrNull(args.targetDeflateBytes, "--target-deflate-bytes"),
    minLimit: parsePositiveIntOrNull(args.minLimit, "--min-limit"),
    maxLimit: parsePositiveIntOrNull(args.maxLimit, "--max-limit"),
    freqPath: args.freqPath ? resolve(args.freqPath) : null,
    webTsvPath: args.webTsvPath ? resolve(args.webTsvPath) : null,
    matrixDefPath: args.matrixDefPath ? resolve(args.matrixDefPath) : null,
  };

  if (
    (await pathExists(outManifest)) &&
    (await pathExists(outWasm)) &&
    (await pathExists(outDictionary)) &&
    (await pathExists(outProfileModule))
  ) {
    const currentManifest = JSON.parse(await readFile(outManifest, "utf8"));
    if (JSON.stringify(currentManifest.request ?? null) === JSON.stringify(request)) {
      console.log(`[select-profile] reuse generated artifacts for request=${JSON.stringify(request)}`);
      return;
    }
  }

  await mkdir(generatedDir, { recursive: true });

  const existingFiles = await readdir(generatedDir);
  for (const fileName of existingFiles) {
    if (fileName === ".gitkeep") {
      continue;
    }
    if (fileName.endsWith(".wasm") || fileName.endsWith(".deflate")) {
      await rm(resolve(generatedDir, fileName), { force: true });
    }
  }

  let dictionarySource = null;
  let selection = null;
  if (VALID_PROFILES.has(profile) && !args.limit) {
    dictionarySource = resolve(sourceDist, `${profile}.dic.bin.deflate`);
    selection = {
      mode: "preset",
      profile,
      limit: null,
      targetDeflateBytes: null,
      search: null,
      sourceDist,
    };
  } else {
    const explicitLimit = args.limit ? parsePositiveInt(args.limit, "--limit") : null;
    const targetDeflateBytes = parsePositiveInt(
      args.targetDeflateBytes,
      "--target-deflate-bytes",
    );
    const fullDictionaryPath = resolve(sourceDist, "full.dic.bin.deflate");
    const fullDictionaryBytes = (await stat(fullDictionaryPath)).size;
    const minLimit = parsePositiveInt(args.minLimit, "--min-limit");
    const maxLimit = parsePositiveInt(args.maxLimit, "--max-limit");
    const requiredLimit = explicitLimit ?? Math.max(minLimit, DEFAULT_LIMITS.medium);

    if (!explicitLimit && profile === "fit" && targetDeflateBytes >= fullDictionaryBytes) {
      dictionarySource = fullDictionaryPath;
      selection = {
        mode: "fit-preset",
        profile: "full",
        limit: null,
        targetDeflateBytes,
        search: {
          optimized: true,
          reason: "target >= full dictionary deflate size",
        },
        availableRows: null,
      };
    } else {
      const buildInputs = await resolveBuildInputs({
        repoRoot,
        requestedWebTsvPath: args.webTsvPath,
        requestedMatrixDefPath: args.matrixDefPath,
        requestedFreqPath: args.freqPath,
        requiredLimit: Math.min(requiredLimit, maxLimit),
      });

      if (explicitLimit) {
        selection = await buildCustomDictionary({
          workerDir,
          repoRoot,
          limit: explicitLimit,
          freqPath: buildInputs.freqPath,
          webTsvPath: buildInputs.webTsvPath,
          matrixDefPath: buildInputs.matrixDefPath,
        });
        selection.mode = "custom";
        selection.targetDeflateBytes = null;
        selection.search = null;
        selection.availableRows = buildInputs.availableRows;
      } else {
        const boundedMaxLimit = Math.min(maxLimit, buildInputs.availableRows);
        const boundedMinLimit = Math.min(minLimit, boundedMaxLimit);
        selection = await fitDictionaryUnderTarget({
          workerDir,
          repoRoot,
          targetDeflateBytes,
          minLimit: boundedMinLimit,
          maxLimit: boundedMaxLimit,
          webTsvPath: buildInputs.webTsvPath,
          matrixDefPath: buildInputs.matrixDefPath,
          freqPath: buildInputs.freqPath,
        });
        selection.availableRows = buildInputs.availableRows;
      }
      dictionarySource = selection.deflatePath;
    }

  }

  if (!(await pathExists(dictionarySource))) {
    throw new Error(`dictionary source not found: ${dictionarySource}`);
  }

  await copyFile(sourceWasm, outWasm);
  await copyFile(dictionarySource, outDictionary);

  const [wasmStats, dictionaryStats] = await Promise.all([stat(outWasm), stat(outDictionary)]);
  const [wasmSha256, dictionarySha256] = await Promise.all([
    sha256Hex(outWasm),
    sha256Hex(outDictionary),
  ]);

  const moduleSource = [
    "import wasmModule from './micado_wasm.wasm';",
    "import dictionaryDeflate from './dictionary.dic.bin.deflate';",
    "",
    `export const PROFILE = '${selection.profile}';`,
    `export const SOURCE_MODE = '${selection.mode}';`,
    `export const ENTRY_LIMIT = ${selection.limit === null ? "null" : selection.limit};`,
    `export const TARGET_DEFLATE_BYTES = ${
      selection.targetDeflateBytes === null ? "null" : selection.targetDeflateBytes
    };`,
    "export const WASM_MODULE = wasmModule;",
    "export const DICTIONARY_DEFLATE = dictionaryDeflate;",
    `export const WASM_BYTES = ${wasmStats.size};`,
    `export const DICTIONARY_DEFLATE_BYTES = ${dictionaryStats.size};`,
    "",
  ].join("\n");
  await writeFile(outProfileModule, moduleSource, "utf8");

  const manifest = {
    generatedAt: new Date().toISOString(),
    request,
    mode: selection.mode,
    profile: selection.profile,
    limit: selection.limit,
    targetDeflateBytes: selection.targetDeflateBytes,
    search: selection.search,
    availableRows: selection.availableRows ?? null,
    wasm: {
      path: "src/generated/micado_wasm.wasm",
      bytes: wasmStats.size,
      sha256: wasmSha256,
    },
    dictionaryDeflate: {
      path: "src/generated/dictionary.dic.bin.deflate",
      bytes: dictionaryStats.size,
      sha256: dictionarySha256,
      sourcePath: dictionarySource,
    },
    sourceDist,
  };
  await writeFile(outManifest, `${JSON.stringify(manifest, null, 2)}\n`, "utf8");

  const mib = (dictionaryStats.size / (1024 * 1024)).toFixed(3);
  console.log(
    `[select-profile] mode=${selection.mode} profile=${selection.profile} dictionary=${dictionaryStats.size} bytes (${mib} MiB) wasm=${wasmStats.size} bytes`,
  );
  if (selection.limit !== null) {
    console.log(`[select-profile] entry-limit=${selection.limit}`);
  }
  if (selection.targetDeflateBytes !== null) {
    console.log(`[select-profile] target-deflate-bytes=${selection.targetDeflateBytes}`);
  }
  if (selection.search?.attempts?.length) {
    const trail = selection.search.attempts
      .map((item) => `${item.limit}:${item.deflateBytes}`)
      .join(", ");
    console.log(`[select-profile] fit-attempts=${trail}`);
  }
  console.log(`[select-profile] generated: ${outProfileModule}`);
}

main().catch((error) => {
  console.error(`[select-profile] ${error?.stack ?? error}`);
  process.exit(1);
});
