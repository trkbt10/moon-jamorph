function normalizeBytes(source) {
  if (source instanceof Uint8Array) {
    return source;
  }
  if (source instanceof ArrayBuffer) {
    return new Uint8Array(source);
  }
  throw new Error("dic.bin source must be Uint8Array or ArrayBuffer");
}

function sourceLooksCompressed(source) {
  if (source instanceof URL) {
    return source.pathname.toLowerCase().endsWith(".deflate");
  }
  if (typeof source === "string") {
    return source.toLowerCase().endsWith(".deflate");
  }
  return false;
}

async function inflateDeflate(bytes) {
  if (typeof DecompressionStream !== "undefined") {
    const stream = new Blob([bytes]).stream().pipeThrough(new DecompressionStream("deflate"));
    const arrayBuffer = await new Response(stream).arrayBuffer();
    return new Uint8Array(arrayBuffer);
  }

  if (typeof process !== "undefined" && process.versions?.node) {
    const { inflateSync } = await import("node:zlib");
    const out = inflateSync(bytes);
    return new Uint8Array(out.buffer, out.byteOffset, out.byteLength);
  }

  throw new Error("No deflate decompressor available in this runtime");
}

async function readSourceBytes(source) {
  if (source instanceof Uint8Array || source instanceof ArrayBuffer) {
    return normalizeBytes(source);
  }

  const url = source instanceof URL ? source : new URL(source, import.meta.url);
  let bytes;
  if (url.protocol === "file:") {
    const fs = await import("node:fs/promises");
    const file = await fs.readFile(url);
    bytes = new Uint8Array(file.buffer, file.byteOffset, file.byteLength);
  } else {
    const response = await fetch(url);
    if (!response.ok) {
      throw new Error(`Failed to fetch dic.bin: ${response.status} ${response.statusText}`);
    }
    bytes = new Uint8Array(await response.arrayBuffer());
  }
  return bytes;
}

function parsePosFromFeature(feature) {
  if (!feature) {
    return { pos: "未知語,*", pos_detail: "未知語,*,*,*" };
  }
  if (feature.includes("\t")) {
    const cols = feature.split("\t");
    const pos = cols[3] || "未知語";
    return { pos, pos_detail: pos };
  }
  const cols = feature.split(",");
  const c0 = cols[0] || "未知語";
  const c1 = cols[1] || "*";
  const c2 = cols[2] || "*";
  const c3 = cols[3] || "*";
  return {
    pos: `${c0},${c1}`,
    pos_detail: `${c0},${c1},${c2},${c3}`,
  };
}

export function parseDicBin(source) {
  const bytes = normalizeBytes(source);
  if (bytes.length < 24) {
    throw new Error("dic.bin too small");
  }
  if (
    bytes[0] !== 0x4d ||
    bytes[1] !== 0x44 ||
    bytes[2] !== 0x49 ||
    bytes[3] !== 0x43
  ) {
    throw new Error("dic.bin magic mismatch");
  }

  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const version = bytes[4];
  if (version !== 1) {
    throw new Error(`unsupported dic.bin version: ${version}`);
  }
  const entryCount = view.getUint32(8, true);
  const indexOffset = view.getUint32(12, true);
  const recordBytes = view.getUint32(16, true);
  const stringsOffset = view.getUint32(20, true);

  const recordSize = 16;
  if (recordBytes !== entryCount * recordSize) {
    throw new Error("dic.bin index size mismatch");
  }
  if (stringsOffset !== indexOffset + recordBytes) {
    throw new Error("dic.bin strings offset mismatch");
  }
  if (stringsOffset > bytes.length) {
    throw new Error("dic.bin strings offset out of range");
  }

  const decoder = new TextDecoder();
  const entries = [];
  for (let i = 0; i < entryCount; i += 1) {
    const rec = indexOffset + i * recordSize;
    const sOff = view.getUint32(rec + 0, true);
    const sLen = view.getUint16(rec + 4, true);
    const fOff = view.getUint32(rec + 8, true);
    const fLen = view.getUint16(rec + 12, true);

    const sStart = stringsOffset + sOff;
    const sEnd = sStart + sLen;
    const fStart = stringsOffset + fOff;
    const fEnd = fStart + fLen;
    if (sEnd > bytes.length || fEnd > bytes.length) {
      throw new Error("dic.bin string range out of bounds");
    }

    const surface = decoder.decode(bytes.subarray(sStart, sEnd));
    const feature = decoder.decode(bytes.subarray(fStart, fEnd));
    const pos = parsePosFromFeature(feature);

    entries.push({
      surface,
      mecab_feature: feature,
      pos: pos.pos,
      pos_detail: pos.pos_detail,
    });
  }

  return {
    version,
    entries,
    bytes,
  };
}

export async function loadDicBin(source, options = {}) {
  const bytes = await readSourceBytes(source);
  const compressed =
    options.compressed === undefined ? sourceLooksCompressed(source) : !!options.compressed;
  const raw = compressed ? await inflateDeflate(bytes) : bytes;
  return parseDicBin(raw);
}

export function createDicBinTokenizer(dic) {
  const parsed = dic?.entries ? dic : parseDicBin(dic);
  const map = new Map();
  let maxLen = 1;

  for (const entry of parsed.entries) {
    if (!map.has(entry.surface)) {
      map.set(entry.surface, entry);
      const len = [...entry.surface].length;
      if (len > maxLen) {
        maxLen = len;
      }
    }
  }

  function tokenize(text) {
    const chars = [...text];
    const tokens = [];
    let i = 0;
    while (i < chars.length) {
      let hit = null;
      const remaining = chars.length - i;
      const tryMax = remaining < maxLen ? remaining : maxLen;

      for (let len = tryMax; len >= 1; len -= 1) {
        const surface = chars.slice(i, i + len).join("");
        const found = map.get(surface);
        if (found) {
          hit = found;
          break;
        }
      }

      if (hit) {
        const start = i;
        const end = i + [...hit.surface].length;
        tokens.push({
          surface: hit.surface,
          pos: hit.pos,
          pos_detail: hit.pos_detail,
          mecab_feature: hit.mecab_feature,
          start_pos: start,
          end_pos: end,
        });
        i = end;
        continue;
      }

      const surface = chars[i];
      tokens.push({
        surface,
        pos: "未知語,*",
        pos_detail: "未知語,*,*,*",
        mecab_feature: "未知語,*,*,*,*,*,*,*,*",
        start_pos: i,
        end_pos: i + 1,
      });
      i += 1;
    }

    return tokens;
  }

  return {
    entries: parsed.entries,
    tokenize,
    stats: {
      entryCount: parsed.entries.length,
      maxSurfaceLength: maxLen,
      bytes: parsed.bytes?.byteLength ?? 0,
    },
  };
}
