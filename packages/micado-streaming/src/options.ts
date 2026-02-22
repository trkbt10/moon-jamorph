import type { StreamOptions, StreamOptionsInput, TokenFormat } from "./types.js";

export function parseBoolean(
  raw: string | boolean | null | undefined,
  fallback: boolean
): boolean {
  if (raw === undefined || raw === null || raw === "") {
    return fallback;
  }
  if (typeof raw === "boolean") {
    return raw;
  }
  const value = String(raw).toLowerCase();
  if (value === "1" || value === "true" || value === "yes" || value === "on") {
    return true;
  }
  if (value === "0" || value === "false" || value === "no" || value === "off") {
    return false;
  }
  return fallback;
}

export function normalizeInt(
  raw: string | number | null | undefined,
  fallback: number,
  min: number,
  max: number
): number {
  const parsed = Number.parseInt(String(raw ?? fallback), 10);
  const safe = Number.isFinite(parsed) ? parsed : fallback;
  return Math.max(min, Math.min(max, safe));
}

const VALID_FORMATS: TokenFormat[] = ["tsv", "compact", "detailed"];

export function normalizeFormat(raw: string | TokenFormat | undefined): TokenFormat {
  if (!raw) {
    return "detailed";
  }
  const lower = String(raw).toLowerCase() as TokenFormat;
  return VALID_FORMATS.includes(lower) ? lower : "detailed";
}

export function normalizeStreamOptions(raw: StreamOptionsInput = {}): StreamOptions {
  const windowChars = normalizeInt(raw.windowChars, 1024, 256, 65536);
  const overlapChars = normalizeInt(
    raw.overlapChars,
    256,
    64,
    Math.max(64, windowChars - 128)
  );
  const forceFlushChars = normalizeInt(
    raw.forceFlushChars,
    Math.max(windowChars * 2, 4096),
    Math.max(windowChars, 2048),
    windowChars * 32
  );
  const notifyWindow = parseBoolean(raw.notifyWindow, false);
  const includeText = parseBoolean(raw.includeText, true);
  const format = normalizeFormat(raw.format);

  return {
    windowChars,
    overlapChars,
    forceFlushChars,
    notifyWindow,
    includeText,
    format,
  };
}
