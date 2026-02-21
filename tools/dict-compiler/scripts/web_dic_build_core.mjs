#!/usr/bin/env node
import { spawn } from "node:child_process";
import { createReadStream } from "node:fs";
import {
  access,
  copyFile,
  mkdir,
  readdir,
  readFile,
  stat,
  writeFile,
} from "node:fs/promises";
import { constants as FsConstants } from "node:fs";
import { dirname, resolve } from "node:path";
import { createInterface } from "node:readline";
import { fileURLToPath } from "node:url";
import { deflateSync } from "node:zlib";

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const PROJECT_ROOT = resolve(SCRIPT_DIR, "../../..");

const IPADIC_ARCHIVE_URL =
  "https://raw.githubusercontent.com/takuyaa/mecab-ipadic-seed/master/dict/mecab-ipadic-2.7.0-20070801.tar.xz";
const DEFAULT_CONNECTION_COST = 10000;

export const DEFAULT_LIMITS = {
  tiny: 1500,
  mini: 5000,
  medium: 12000,
  full: 999999999,
};

export function resolveDefaultPaths(rootDir = PROJECT_ROOT) {
  const ipadicCacheDir = resolve(rootDir, "tools/dict-compiler/.cache/ipadic");
  const webSmallCacheDir = resolve(rootDir, "tools/dict-compiler/.cache/web-small");
  const ipadicArchivePath = resolve(ipadicCacheDir, "mecab-ipadic-2.7.0-20070801.tar.xz");
  const ipadicSourceDir = resolve(ipadicCacheDir, "mecab-ipadic-2.7.0-20070801");
  const webTsvPath = resolve(webSmallCacheDir, "ipadic_web_small.tsv");
  const defaultMatrixDefPath = resolve(ipadicSourceDir, "matrix.def");
  return {
    ipadicCacheDir,
    webSmallCacheDir,
    ipadicArchivePath,
    ipadicSourceDir,
    webTsvPath,
    defaultMatrixDefPath,
  };
}

function clampInt16(v) {
  if (!Number.isFinite(v)) {
    return 0;
  }
  if (v < -32768) {
    return -32768;
  }
  if (v > 32767) {
    return 32767;
  }
  return v | 0;
}

function clampInt32(v) {
  if (!Number.isFinite(v)) {
    return 0;
  }
  if (v < -2147483648) {
    return -2147483648;
  }
  if (v > 2147483647) {
    return 2147483647;
  }
  return v | 0;
}

function parsePositiveLimit(v, key) {
  const n = Number.parseInt(String(v), 10);
  if (!Number.isFinite(n) || n <= 0) {
    throw new Error(`invalid ${key}: ${v}`);
  }
  return n;
}

async function exists(path) {
  try {
    await access(path, FsConstants.F_OK);
    return true;
  } catch {
    return false;
  }
}

async function runCommand(command, args) {
  await new Promise((resolvePromise, rejectPromise) => {
    const proc = spawn(command, args, { stdio: "inherit" });
    proc.on("error", rejectPromise);
    proc.on("exit", (code) => {
      if (code === 0) {
        resolvePromise();
      } else {
        rejectPromise(new Error(`${command} failed with exit code ${code ?? "unknown"}`));
      }
    });
  });
}

function safeCol(cols, index, fallback = "*") {
  return index < cols.length && cols[index] !== "" ? cols[index] : fallback;
}

function buildFeature(cols) {
  if (cols.length >= 14) {
    return [
      safeCol(cols, 5),
      safeCol(cols, 6),
      safeCol(cols, 7),
      safeCol(cols, 8),
      safeCol(cols, 9),
      safeCol(cols, 10),
      safeCol(cols, 11, cols[0]),
      safeCol(cols, 12),
      safeCol(cols, 13),
    ].join(",");
  }
  if (cols.length >= 13) {
    return [
      safeCol(cols, 4),
      safeCol(cols, 5),
      safeCol(cols, 6),
      safeCol(cols, 7),
      safeCol(cols, 8),
      safeCol(cols, 9),
      safeCol(cols, 10, cols[0]),
      safeCol(cols, 11),
      safeCol(cols, 12),
    ].join(",");
  }
  if (cols.length >= 9) {
    return [
      safeCol(cols, 1),
      safeCol(cols, 2),
      safeCol(cols, 3),
      safeCol(cols, 4),
      safeCol(cols, 5),
      safeCol(cols, 6),
      safeCol(cols, 7, cols[0]),
      safeCol(cols, 8),
      safeCol(cols, 9),
    ].join(",");
  }
  if (cols.length >= 2) {
    return cols[1];
  }
  return "未知語,*,*,*,*,*,*,*,*";
}

function parseWordCost(cols) {
  if (cols.length >= 14) {
    const v = Number.parseInt(cols[4], 10);
    return Number.isFinite(v) ? v : 32767;
  }
  if (cols.length >= 13) {
    const v = Number.parseInt(cols[3], 10);
    return Number.isFinite(v) ? v : 32767;
  }
  if (cols.length >= 4) {
    const v = Number.parseInt(cols[3], 10);
    return Number.isFinite(v) ? v : 32767;
  }
  return 32767;
}

function parseConnIds(cols) {
  if (cols.length >= 14) {
    return {
      left: Number.parseInt(cols[2], 10),
      right: Number.parseInt(cols[3], 10),
    };
  }
  if (cols.length >= 13) {
    return {
      left: Number.parseInt(cols[1], 10),
      right: Number.parseInt(cols[2], 10),
    };
  }
  if (cols.length >= 4) {
    return {
      left: Number.parseInt(cols[1], 10),
      right: Number.parseInt(cols[2], 10),
    };
  }
  return { left: Number.NaN, right: Number.NaN };
}

function parsePos1Pos2(cols, feature) {
  if (cols.length >= 14) {
    return { pos1: safeCol(cols, 5, "未知語"), pos2: safeCol(cols, 6, "*") };
  }
  if (cols.length >= 13) {
    return { pos1: safeCol(cols, 4, "未知語"), pos2: safeCol(cols, 5, "*") };
  }
  if (cols.length >= 9) {
    return { pos1: safeCol(cols, 1, "未知語"), pos2: safeCol(cols, 2, "*") };
  }
  const parts = feature.split(",");
  return { pos1: parts[0] || "未知語", pos2: parts[1] || "*" };
}

function canonicalConnId(pos1, pos2) {
  if (pos1 === "助詞") {
    return 2;
  }
  if (pos1 === "名詞") {
    if (pos2 === "非自立") {
      return 3;
    }
    return 1;
  }
  return 3;
}

function parseFreqTSV(text) {
  const map = new Map();
  for (const line of text.split(/\r?\n/)) {
    if (!line || line.startsWith("#")) {
      continue;
    }
    const cols = line.split("\t");
    if (cols.length < 2) {
      continue;
    }
    const surface = cols[0];
    const n = Number.parseInt(cols[1], 10);
    if (!surface || !Number.isFinite(n) || n <= 0) {
      continue;
    }
    map.set(surface, n);
  }
  return map;
}

function parseRows(tsvText, freqMap) {
  const rows = [];
  for (const line of tsvText.split(/\r?\n/)) {
    if (!line || line.startsWith("#")) {
      continue;
    }
    const cols = line.split("\t");
    if (cols.length === 0) {
      continue;
    }
    const surface = cols[0];
    if (!surface) {
      continue;
    }
    const feature = buildFeature(cols);
    const wordCost = clampInt32(parseWordCost(cols));
    const pos = parsePos1Pos2(cols, feature);
    const canonicalId = canonicalConnId(pos.pos1, pos.pos2);
    const ids = parseConnIds(cols);
    rows.push({
      surface,
      feature,
      left_id: clampInt16(Number.isFinite(ids.left) ? ids.left : canonicalId),
      right_id: clampInt16(Number.isFinite(ids.right) ? ids.right : canonicalId),
      word_cost: wordCost,
      freq: freqMap?.get(surface) ?? 0,
    });
  }

  rows.sort((a, b) => {
    if (a.freq !== b.freq) {
      return b.freq - a.freq;
    }
    if (a.word_cost !== b.word_cost) {
      return a.word_cost - b.word_cost;
    }
    if (a.surface.length !== b.surface.length) {
      return b.surface.length - a.surface.length;
    }
    if (a.surface < b.surface) {
      return -1;
    }
    if (a.surface > b.surface) {
      return 1;
    }
    if (a.feature < b.feature) {
      return -1;
    }
    if (a.feature > b.feature) {
      return 1;
    }
    if (a.left_id !== b.left_id) {
      return a.left_id - b.left_id;
    }
    if (a.right_id !== b.right_id) {
      return a.right_id - b.right_id;
    }
    return a.word_cost - b.word_cost;
  });

  return rows;
}

function trimRows(allRows, limit) {
  return allRows.slice(0, limit).map((row) => ({
    surface: row.surface,
    feature: row.feature,
    left_id: row.left_id,
    right_id: row.right_id,
    word_cost: row.word_cost,
  }));
}

function collectUsedIds(rows) {
  const set = new Set([0, 1, 2, 3]);
  for (const row of rows) {
    set.add(row.left_id);
    set.add(row.right_id);
  }
  return Array.from(set)
    .sort((a, b) => a - b)
    .map((v) => clampInt16(v));
}

function parseCompactMatrix(matrixText, usedIds, defaultCost) {
  const idToIndex = new Map();
  for (let i = 0; i < usedIds.length; i += 1) {
    idToIndex.set(usedIds[i], i);
  }

  const n = usedIds.length;
  const costs = new Int16Array(n * n);
  costs.fill(clampInt16(defaultCost));

  let seenHeader = false;
  for (const rawLine of matrixText.split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line || line.startsWith("#")) {
      continue;
    }
    const parts = line.split(/\s+/);
    if (!seenHeader) {
      if (parts.length >= 2) {
        seenHeader = true;
      }
      continue;
    }
    if (parts.length < 3) {
      continue;
    }

    const rightId = Number.parseInt(parts[0], 10);
    const leftId = Number.parseInt(parts[1], 10);
    const cost = Number.parseInt(parts[2], 10);
    if (!Number.isFinite(rightId) || !Number.isFinite(leftId) || !Number.isFinite(cost)) {
      continue;
    }

    const rightIndex = idToIndex.get(rightId);
    const leftIndex = idToIndex.get(leftId);
    if (rightIndex === undefined || leftIndex === undefined) {
      continue;
    }
    costs[rightIndex * n + leftIndex] = clampInt16(cost);
  }

  return {
    ids: Int16Array.from(usedIds),
    costs,
    defaultCost: clampInt32(defaultCost),
  };
}

function encodeBin(rows, matrix) {
  const encoder = new TextEncoder();
  const surfaceBytes = rows.map((r) => encoder.encode(r.surface));
  const featureBytes = rows.map((r) => encoder.encode(r.feature));

  let stringsByteLen = 0;
  for (let i = 0; i < rows.length; i += 1) {
    stringsByteLen += surfaceBytes[i].length;
    stringsByteLen += featureBytes[i].length;
  }

  const HEADER_SIZE = 24;
  const RECORD_SIZE = 24;
  const recordBytes = rows.length * RECORD_SIZE;
  const stringsOffset = HEADER_SIZE + recordBytes;
  const matrixOffset = stringsOffset + stringsByteLen;

  const MATRIX_MAGIC_SIZE = 4;
  const MATRIX_META_SIZE = 16;
  const idsBytesLen = matrix.ids.length * 2;
  const costsBytesLen = matrix.costs.length * 2;
  const matrixSectionSize = MATRIX_MAGIC_SIZE + MATRIX_META_SIZE + idsBytesLen + costsBytesLen;

  const totalBytes = matrixOffset + matrixSectionSize;
  const out = new Uint8Array(totalBytes);
  const view = new DataView(out.buffer);

  out[0] = 0x4d;
  out[1] = 0x44;
  out[2] = 0x49;
  out[3] = 0x43;
  out[4] = 0x01;
  out[5] = 0x00;
  out[6] = 0x00;
  out[7] = 0x00;
  view.setUint32(8, rows.length, true);
  view.setUint32(12, HEADER_SIZE, true);
  view.setUint32(16, recordBytes, true);
  view.setUint32(20, stringsOffset, true);

  let stringCursor = stringsOffset;
  for (let i = 0; i < rows.length; i += 1) {
    const rec = HEADER_SIZE + i * RECORD_SIZE;
    const surface = surfaceBytes[i];
    const feature = featureBytes[i];

    const surfaceOffset = stringCursor - stringsOffset;
    out.set(surface, stringCursor);
    stringCursor += surface.length;

    const featureOffset = stringCursor - stringsOffset;
    out.set(feature, stringCursor);
    stringCursor += feature.length;

    view.setUint32(rec + 0, surfaceOffset, true);
    view.setUint16(rec + 4, surface.length, true);
    view.setUint16(rec + 6, 0, true);
    view.setUint32(rec + 8, featureOffset, true);
    view.setUint16(rec + 12, feature.length, true);
    view.setUint16(rec + 14, 0, true);
    view.setInt16(rec + 16, rows[i].left_id, true);
    view.setInt16(rec + 18, rows[i].right_id, true);
    view.setInt32(rec + 20, rows[i].word_cost, true);
  }

  let cursor = matrixOffset;
  out[cursor + 0] = 0x4d;
  out[cursor + 1] = 0x54;
  out[cursor + 2] = 0x58;
  out[cursor + 3] = 0x31;
  cursor += MATRIX_MAGIC_SIZE;

  view.setUint32(cursor + 0, matrix.ids.length, true);
  view.setInt32(cursor + 4, matrix.defaultCost, true);
  view.setUint32(cursor + 8, idsBytesLen, true);
  view.setUint32(cursor + 12, costsBytesLen, true);
  cursor += MATRIX_META_SIZE;

  for (let i = 0; i < matrix.ids.length; i += 1) {
    view.setInt16(cursor + i * 2, matrix.ids[i], true);
  }
  cursor += idsBytesLen;

  for (let i = 0; i < matrix.costs.length; i += 1) {
    view.setInt16(cursor + i * 2, matrix.costs[i], true);
  }

  return out;
}

async function extractCsvRows(csvPath, limitPerFile) {
  const out = [];
  const input = createReadStream(csvPath, { encoding: "utf8" });
  const reader = createInterface({ input, crlfDelay: Infinity });
  for await (const line of reader) {
    if (out.length >= limitPerFile) {
      break;
    }
    if (!line) {
      continue;
    }
    const cols = line.split(",");
    const surface = cols[0] ?? "";
    if (!surface) {
      continue;
    }
    const leftId = cols[1] ?? "";
    const rightId = cols[2] ?? "";
    const wordCost = cols[3] ?? "";
    const pos1 = cols[4] ?? "";
    const pos2 = cols[5] ?? "";
    const pos3 = cols[6] ?? "";
    const pos4 = cols[7] ?? "";
    const ctype = cols[8] === "" ? "*" : cols[8] ?? "*";
    const cform = cols[9] === "" ? "*" : cols[9] ?? "*";
    const base = cols[10] === "" ? surface : cols[10] ?? surface;
    const read = cols[11] === "" ? "*" : cols[11] ?? "*";
    const pron = cols[12] === "" ? "*" : cols[12] ?? "*";
    out.push(
      [
        surface,
        leftId,
        rightId,
        wordCost,
        pos1,
        pos2,
        pos3,
        pos4,
        ctype,
        cform,
        base,
        read,
        pron,
      ].join("\t"),
    );
  }
  input.close();
  return out;
}

export async function ensureWebSmallTSV({
  limit,
  rootDir = PROJECT_ROOT,
  outputPath,
} = {}) {
  const actualLimit = parsePositiveLimit(limit, "--limit");
  const paths = resolveDefaultPaths(rootDir);
  const outPath = outputPath ? resolve(outputPath) : paths.webTsvPath;
  await mkdir(paths.webSmallCacheDir, { recursive: true });
  await mkdir(paths.ipadicCacheDir, { recursive: true });

  if (!(await exists(paths.ipadicArchivePath))) {
    console.log("[web-small] downloading ipadic archive...");
    await runCommand("curl", ["-fsSL", IPADIC_ARCHIVE_URL, "-o", paths.ipadicArchivePath]);
  }

  if (!(await exists(paths.ipadicSourceDir))) {
    console.log("[web-small] extracting ipadic archive...");
    await runCommand("tar", ["-xf", paths.ipadicArchivePath, "-C", paths.ipadicCacheDir]);
  }

  console.log(`[web-small] extracting rows (limit=${actualLimit})...`);
  const names = await readdir(paths.ipadicSourceDir);
  const csvPaths = names
    .filter((name) => name.endsWith(".csv"))
    .map((name) => resolve(paths.ipadicSourceDir, name))
    .sort();
  if (csvPaths.length === 0) {
    throw new Error(`[web-small] csv files not found under: ${paths.ipadicSourceDir}`);
  }

  const perFile = Math.ceil(actualLimit / csvPaths.length);
  const rows = [];
  for (const csvPath of csvPaths) {
    const chunk = await extractCsvRows(csvPath, perFile);
    for (const row of chunk) {
      rows.push(row);
    }
  }

  const acceptedRows = rows.slice(0, actualLimit);
  const tsv = acceptedRows.length === 0 ? "" : `${acceptedRows.join("\n")}\n`;
  await writeFile(outPath, tsv);
  console.log(`[web-small] accepted rows: ${acceptedRows.length}`);
  console.log(`[web-small] generated: ${outPath}`);

  return {
    tsvPath: outPath,
    matrixDefPath: paths.defaultMatrixDefPath,
    acceptedRows: acceptedRows.length,
  };
}

export async function compileDicBinFromTSV({
  inputPath,
  outputPath,
  limit,
  freqPath = null,
  matrixDefPath = null,
} = {}) {
  if (!inputPath || !outputPath) {
    throw new Error("inputPath and outputPath are required");
  }
  const actualLimit = parsePositiveLimit(limit, "--limit");
  const tsvText = await readFile(resolve(inputPath), "utf8");

  let matrixPath = matrixDefPath ? resolve(matrixDefPath) : null;
  if (!matrixPath) {
    const defaultPaths = resolveDefaultPaths();
    matrixPath = defaultPaths.defaultMatrixDefPath;
  }
  const matrixText = await readFile(matrixPath, "utf8");
  const freqMap = freqPath ? parseFreqTSV(await readFile(resolve(freqPath), "utf8")) : null;

  const parsedRows = parseRows(tsvText, freqMap);
  const rows = trimRows(parsedRows, actualLimit);
  const usedIds = collectUsedIds(rows);
  const matrix = parseCompactMatrix(matrixText, usedIds, DEFAULT_CONNECTION_COST);
  const bin = encodeBin(rows, matrix);

  await mkdir(dirname(resolve(outputPath)), { recursive: true });
  await writeFile(resolve(outputPath), bin);

  return {
    outputPath: resolve(outputPath),
    entries: rows.length,
    ids: matrix.ids.length,
    bytes: bin.byteLength,
    kb: (bin.byteLength / 1024).toFixed(1),
    freqPath: freqPath ? resolve(freqPath) : null,
  };
}

export async function compressDicBinDeflate({
  inputPath,
  outputPath,
} = {}) {
  if (!inputPath || !outputPath) {
    throw new Error("inputPath and outputPath are required");
  }
  const src = await readFile(resolve(inputPath));
  const compressed = deflateSync(src, { level: 9 });
  await mkdir(dirname(resolve(outputPath)), { recursive: true });
  await writeFile(resolve(outputPath), compressed);
  const ratio = src.byteLength === 0 ? 0 : (compressed.byteLength / src.byteLength) * 100;
  return {
    inputPath: resolve(inputPath),
    outputPath: resolve(outputPath),
    inputBytes: src.byteLength,
    outputBytes: compressed.byteLength,
    ratio,
  };
}

export async function buildWebDicArtifacts({
  outDir,
  limits = DEFAULT_LIMITS,
  freqPath = null,
  matrixDefPath = null,
  rootDir = PROJECT_ROOT,
  webTsvPath = null,
  aliasMedium = true,
} = {}) {
  if (!outDir) {
    throw new Error("--out-dir is required");
  }

  const normalizedLimits = {
    tiny: parsePositiveLimit(limits.tiny, "--tiny-limit"),
    mini: parsePositiveLimit(limits.mini, "--mini-limit"),
    medium: parsePositiveLimit(limits.medium, "--medium-limit"),
    full: parsePositiveLimit(limits.full, "--full-limit"),
  };

  const maxLimit = Math.max(
    normalizedLimits.tiny,
    normalizedLimits.mini,
    normalizedLimits.medium,
    normalizedLimits.full,
  );
  const tsvInfo = await ensureWebSmallTSV({
    limit: maxLimit,
    rootDir,
    outputPath: webTsvPath,
  });

  const matrixPath = matrixDefPath ? resolve(matrixDefPath) : tsvInfo.matrixDefPath;
  const matrixText = await readFile(matrixPath, "utf8");
  const tsvText = await readFile(tsvInfo.tsvPath, "utf8");
  const freqMap = freqPath ? parseFreqTSV(await readFile(resolve(freqPath), "utf8")) : null;
  const allRows = parseRows(tsvText, freqMap);

  const outputDir = resolve(outDir);
  await mkdir(outputDir, { recursive: true });

  const summaries = [];
  const order = ["tiny", "mini", "medium", "full"];
  for (const profile of order) {
    const limit = normalizedLimits[profile];
    const rows = trimRows(allRows, limit);
    const usedIds = collectUsedIds(rows);
    const matrix = parseCompactMatrix(matrixText, usedIds, DEFAULT_CONNECTION_COST);
    const bin = encodeBin(rows, matrix);

    const binPath = resolve(outputDir, `${profile}.dic.bin`);
    const deflatePath = `${binPath}.deflate`;
    await writeFile(binPath, bin);
    const compressed = deflateSync(bin, { level: 9 });
    await writeFile(deflatePath, compressed);

    const ratio = bin.byteLength === 0 ? 0 : (compressed.byteLength / bin.byteLength) * 100;
    summaries.push({
      profile,
      limit,
      entries: rows.length,
      ids: matrix.ids.length,
      binPath,
      deflatePath,
      bytes: bin.byteLength,
      compressedBytes: compressed.byteLength,
      ratio,
    });
  }

  if (aliasMedium) {
    const mediumSummary = summaries.find((item) => item.profile === "medium");
    const mediumBin = resolve(outputDir, "medium.dic.bin");
    const mediumDeflate = resolve(outputDir, "medium.dic.bin.deflate");
    const aliasBin = resolve(outputDir, "micado_web_small.dic.bin");
    const aliasDeflate = resolve(outputDir, "micado_web_small.dic.bin.deflate");
    await copyFile(mediumBin, aliasBin);
    await copyFile(mediumDeflate, aliasDeflate);
    const binStats = await stat(aliasBin);
    const deflateStats = await stat(aliasDeflate);
    summaries.push({
      profile: "micado_web_small",
      limit: normalizedLimits.medium,
      entries: mediumSummary?.entries ?? 0,
      ids: mediumSummary?.ids ?? 0,
      binPath: aliasBin,
      deflatePath: aliasDeflate,
      bytes: binStats.size,
      compressedBytes: deflateStats.size,
      ratio: binStats.size === 0 ? 0 : (deflateStats.size / binStats.size) * 100,
    });
  }

  return {
    tsvPath: tsvInfo.tsvPath,
    freqPath: freqPath ? resolve(freqPath) : null,
    matrixPath,
    summaries,
  };
}
