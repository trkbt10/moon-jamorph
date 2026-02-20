#!/usr/bin/env node
import { readFile, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";

const HELP = `usage: node tools/dict-compiler/scripts/build_web_dic_bin.mjs <input.tsv> <output.dic.bin> [--limit N]\n`;

function parseArgs(argv) {
  if (argv.length < 2) {
    throw new Error(HELP.trim());
  }
  const inputPath = resolve(argv[0]);
  const outputPath = resolve(argv[1]);
  let limit = Number.POSITIVE_INFINITY;
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
    throw new Error(`unknown option: ${arg}`);
  }
  if (!Number.isFinite(limit) || limit <= 0) {
    throw new Error(`invalid --limit: ${limit}`);
  }
  return { inputPath, outputPath, limit };
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

function parseRows(tsvText, limit) {
  const dedup = new Map();
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
    if (!surface || dedup.has(surface)) {
      continue;
    }
    dedup.set(surface, buildFeature(cols));
    if (dedup.size >= limit) {
      break;
    }
  }
  const rows = [];
  for (const [surface, feature] of dedup.entries()) {
    rows.push({ surface, feature });
  }
  return rows;
}

function encodeBin(rows) {
  const encoder = new TextEncoder();
  const surfaceBytes = rows.map((r) => encoder.encode(r.surface));
  const featureBytes = rows.map((r) => encoder.encode(r.feature));

  let stringsByteLen = 0;
  for (let i = 0; i < rows.length; i += 1) {
    stringsByteLen += surfaceBytes[i].length;
    stringsByteLen += featureBytes[i].length;
  }

  const HEADER_SIZE = 24;
  const RECORD_SIZE = 16;
  const recordBytes = rows.length * RECORD_SIZE;
  const stringsOffset = HEADER_SIZE + recordBytes;
  const totalBytes = stringsOffset + stringsByteLen;

  const out = new Uint8Array(totalBytes);
  const view = new DataView(out.buffer);

  // Header
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
  }

  return out;
}

async function main() {
  const { inputPath, outputPath, limit } = parseArgs(process.argv.slice(2));
  const tsvText = await readFile(inputPath, "utf8");
  const rows = parseRows(tsvText, limit);
  const bin = encodeBin(rows);
  await writeFile(outputPath, bin);

  const kb = (bin.byteLength / 1024).toFixed(1);
  console.log(
    `[web-dic-bin] entries=${rows.length} bytes=${bin.byteLength} (${kb}KB) out=${outputPath}`,
  );
}

main().catch((err) => {
  console.error(err?.message ?? String(err));
  process.exit(1);
});
