#!/usr/bin/env node
import { readFile, writeFile } from "node:fs/promises";
import { resolve } from "node:path";

const HELP = `usage: node tools/dict-compiler/scripts/build_web_dic_bin.mjs <input.tsv> <output.dic.bin> [--limit N] [--freq-tsv PATH] [--matrix-def PATH]\n`;
const DEFAULT_MATRIX_DEF = resolve(
  "tools/dict-compiler/.cache/ipadic/mecab-ipadic-2.7.0-20070801/matrix.def",
);
const DEFAULT_CONNECTION_COST = 10000;

function parseArgs(argv) {
  if (argv.length < 2) {
    throw new Error(HELP.trim());
  }
  const inputPath = resolve(argv[0]);
  const outputPath = resolve(argv[1]);
  let limit = Number.POSITIVE_INFINITY;
  let freqPath = null;
  let matrixDefPath = DEFAULT_MATRIX_DEF;

  for (let i = 2; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--limit") {
      if (i + 1 >= argv.length) {
        throw new Error("--limit requires a value");
      }
      limit = Number.parseInt(argv[i + 1], 10);
      i += 1;
      continue;
    }
    if (arg === "--freq-tsv") {
      if (i + 1 >= argv.length) {
        throw new Error("--freq-tsv requires a value");
      }
      freqPath = resolve(argv[i + 1]);
      i += 1;
      continue;
    }
    if (arg === "--matrix-def") {
      if (i + 1 >= argv.length) {
        throw new Error("--matrix-def requires a value");
      }
      matrixDefPath = resolve(argv[i + 1]);
      i += 1;
      continue;
    }
    throw new Error(`unknown option: ${arg}`);
  }

  if (!Number.isFinite(limit) || limit <= 0) {
    throw new Error(`invalid --limit: ${limit}`);
  }

  return { inputPath, outputPath, limit, freqPath, matrixDefPath };
}

function safeCol(cols, index, fallback = "*") {
  return index < cols.length && cols[index] !== "" ? cols[index] : fallback;
}

function buildFeature(cols) {
  if (cols.length >= 14) {
    // surface, tag, left, right, cost, pos1..pos4, ctype, cform, base, read, pron
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
    // surface, left, right, cost, pos1..pos4, ctype, cform, base, read, pron
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
    const left = Number.parseInt(cols[2], 10);
    const right = Number.parseInt(cols[3], 10);
    return { left, right };
  }
  if (cols.length >= 13) {
    const left = Number.parseInt(cols[1], 10);
    const right = Number.parseInt(cols[2], 10);
    return { left, right };
  }
  if (cols.length >= 4) {
    const left = Number.parseInt(cols[1], 10);
    const right = Number.parseInt(cols[2], 10);
    return { left, right };
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
  const c = feature.split(",");
  return { pos1: c[0] || "未知語", pos2: c[1] || "*" };
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

function parseRows(tsvText, limit, freqMap) {
  const rows = [];
  const lines = tsvText.split(/\r?\n/);
  for (const line of lines) {
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
    const leftId = Number.isFinite(ids.left) ? ids.left : canonicalId;
    const rightId = Number.isFinite(ids.right) ? ids.right : canonicalId;

    rows.push({
      surface,
      feature,
      left_id: clampInt16(leftId),
      right_id: clampInt16(rightId),
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

  return rows.slice(0, limit).map((r) => ({
    surface: r.surface,
    feature: r.feature,
    left_id: r.left_id,
    right_id: r.right_id,
    word_cost: r.word_cost,
  }));
}

function collectUsedIds(rows) {
  const set = new Set([0, 1, 2, 3]);
  for (const row of rows) {
    set.add(row.left_id);
    set.add(row.right_id);
  }
  return Array.from(set).sort((a, b) => a - b).map((v) => clampInt16(v));
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

    const ri = idToIndex.get(rightId);
    const li = idToIndex.get(leftId);
    if (ri === undefined || li === undefined) {
      continue;
    }
    costs[ri * n + li] = clampInt16(cost);
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

  out[0] = 0x4d; // M
  out[1] = 0x44; // D
  out[2] = 0x49; // I
  out[3] = 0x43; // C
  out[4] = 0x01; // version
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
    const s = surfaceBytes[i];
    const f = featureBytes[i];

    const sOff = stringCursor - stringsOffset;
    out.set(s, stringCursor);
    stringCursor += s.length;

    const fOff = stringCursor - stringsOffset;
    out.set(f, stringCursor);
    stringCursor += f.length;

    view.setUint32(rec + 0, sOff, true);
    view.setUint16(rec + 4, s.length, true);
    view.setUint16(rec + 6, 0, true);
    view.setUint32(rec + 8, fOff, true);
    view.setUint16(rec + 12, f.length, true);
    view.setUint16(rec + 14, 0, true);
    view.setInt16(rec + 16, rows[i].left_id, true);
    view.setInt16(rec + 18, rows[i].right_id, true);
    view.setInt32(rec + 20, rows[i].word_cost, true);
  }

  let p = matrixOffset;
  out[p + 0] = 0x4d; // M
  out[p + 1] = 0x54; // T
  out[p + 2] = 0x58; // X
  out[p + 3] = 0x31; // 1
  p += MATRIX_MAGIC_SIZE;

  view.setUint32(p + 0, matrix.ids.length, true);
  view.setInt32(p + 4, matrix.defaultCost, true);
  view.setUint32(p + 8, idsBytesLen, true);
  view.setUint32(p + 12, costsBytesLen, true);
  p += MATRIX_META_SIZE;

  for (let i = 0; i < matrix.ids.length; i += 1) {
    view.setInt16(p + i * 2, matrix.ids[i], true);
  }
  p += idsBytesLen;

  for (let i = 0; i < matrix.costs.length; i += 1) {
    view.setInt16(p + i * 2, matrix.costs[i], true);
  }

  return out;
}

async function main() {
  const { inputPath, outputPath, limit, freqPath, matrixDefPath } = parseArgs(process.argv.slice(2));
  const tsvText = await readFile(inputPath, "utf8");
  const matrixText = await readFile(matrixDefPath, "utf8");
  const freqMap = freqPath ? parseFreqTSV(await readFile(freqPath, "utf8")) : null;
  const rows = parseRows(tsvText, limit, freqMap);
  const usedIds = collectUsedIds(rows);
  const matrix = parseCompactMatrix(matrixText, usedIds, DEFAULT_CONNECTION_COST);
  const bin = encodeBin(rows, matrix);
  await writeFile(outputPath, bin);

  const kb = (bin.byteLength / 1024).toFixed(1);
  const freqInfo = freqPath ? ` freq=${freqPath}` : "";
  console.log(
    `[web-dic-bin] entries=${rows.length} ids=${matrix.ids.length} bytes=${bin.byteLength} (${kb}KB) out=${outputPath}${freqInfo}`,
  );
}

main().catch((err) => {
  console.error(err?.message ?? String(err));
  process.exit(1);
});
