import type { BlockReason, DetailedToken, QuoteState, ScanResult } from "./types.js";

const TERMINATOR_CHARS = new Set(["。", "！", "？", ".", "!", "?"]);
const OPEN_TO_CLOSE = new Map([
  ["「", "」"],
  ["『", "』"],
  ["《", "》"],
  ["〈", "〉"],
  ["【", "】"],
  ["〔", "〕"],
  ["［", "］"],
  ["｛", "｝"],
  ["(", ")"],
  ["（", "）"],
  ["[", "]"],
  ["{", "}"],
  ["\u201C", "\u201D"],
  ["\u2018", "\u2019"],
]);
const CLOSE_CHARS = new Set(Array.from(OPEN_TO_CLOSE.values()));
const TRAILING_BOUNDARY_CHARS = new Set([
  ...CLOSE_CHARS,
  '"',
  "'",
  "」",
  "』",
  "》",
]);

export function createQuoteState(): QuoteState {
  return {
    stack: [],
    inSingleQuote: false,
    inDoubleQuote: false,
  };
}

function isOutsideQuotes(state: QuoteState): boolean {
  return state.stack.length === 0 && !state.inSingleQuote && !state.inDoubleQuote;
}

function applyQuoteChar(state: QuoteState, ch: string): void {
  if (ch === '"') {
    state.inDoubleQuote = !state.inDoubleQuote;
    return;
  }
  if (ch === "'") {
    state.inSingleQuote = !state.inSingleQuote;
    return;
  }
  const closing = OPEN_TO_CLOSE.get(ch);
  if (closing) {
    state.stack.push(closing);
    return;
  }
  if (!CLOSE_CHARS.has(ch)) {
    return;
  }
  for (let i = state.stack.length - 1; i >= 0; i -= 1) {
    if (state.stack[i] === ch) {
      state.stack.length = i;
      return;
    }
  }
}

function extendBoundary(
  text: string,
  boundary: number,
  safeEnd: number,
  quoteState: QuoteState
): number {
  let cursor = boundary;
  while (cursor < safeEnd) {
    const ch = text[cursor];
    if (!ch) {
      break;
    }
    const shouldConsume = TRAILING_BOUNDARY_CHARS.has(ch) || ch.trim() === "";
    if (!shouldConsume) {
      break;
    }
    applyQuoteChar(quoteState, ch);
    cursor += ch.length;
  }
  return cursor;
}

function findParagraphBoundary(
  text: string,
  start: number,
  safeEnd: number
): number | null {
  let cursor = start;
  let newlineCount = 0;
  let sawBreakChar = false;
  while (cursor < safeEnd) {
    const ch = text[cursor];
    if (ch === "\n") {
      newlineCount += 1;
      sawBreakChar = true;
      cursor += ch.length;
      continue;
    }
    if (ch === "\r") {
      sawBreakChar = true;
      cursor += ch.length;
      continue;
    }
    break;
  }
  if (!sawBreakChar || newlineCount < 2) {
    return null;
  }

  while (cursor < safeEnd) {
    const ch = text[cursor];
    if (ch === " " || ch === "\t" || ch === "　") {
      cursor += ch.length;
      continue;
    }
    break;
  }
  return cursor;
}

interface BoundaryResult {
  boundary: number;
  reason: BlockReason;
}

function scanBoundaryAtChar(
  text: string,
  charPos: number,
  safeEnd: number,
  quoteState: QuoteState
): BoundaryResult | null {
  const ch = text[charPos];
  if (!ch) {
    return null;
  }

  if (isOutsideQuotes(quoteState) && (ch === "\n" || ch === "\r")) {
    const paragraphBoundary = findParagraphBoundary(text, charPos, safeEnd);
    if (paragraphBoundary && paragraphBoundary > charPos) {
      return { boundary: paragraphBoundary, reason: "paragraph-break" };
    }
  }

  applyQuoteChar(quoteState, ch);
  if (TERMINATOR_CHARS.has(ch) && isOutsideQuotes(quoteState)) {
    const boundary = extendBoundary(text, charPos + ch.length, safeEnd, quoteState);
    return { boundary, reason: "terminator" };
  }
  return null;
}

interface RawRangeResult {
  boundary: number | null;
  scannedTo: number;
  reason: BlockReason | null;
}

function scanRawRange(
  text: string,
  from: number,
  to: number,
  safeEnd: number,
  quoteState: QuoteState
): RawRangeResult {
  let cursor = from;
  while (cursor < to) {
    const found = scanBoundaryAtChar(text, cursor, safeEnd, quoteState);
    if (found) {
      return {
        boundary: found.boundary,
        scannedTo: found.boundary,
        reason: found.reason,
      };
    }
    const ch = text[cursor];
    if (!ch) {
      break;
    }
    cursor += ch.length;
  }
  return { boundary: null, scannedTo: cursor, reason: null };
}

export function scanForBoundary(
  pendingTokens: DetailedToken[],
  scanCursor: number,
  safeEnd: number,
  quoteState: QuoteState,
  text: string
): ScanResult {
  if (scanCursor >= safeEnd) {
    return { boundary: null, scannedTo: safeEnd, reason: null };
  }

  let cursor = scanCursor;
  for (const token of pendingTokens) {
    if (token.end_pos <= cursor) {
      continue;
    }
    if (token.start_pos >= safeEnd) {
      break;
    }

    if (cursor < token.start_pos) {
      const gapResult = scanRawRange(
        text,
        cursor,
        Math.min(token.start_pos, safeEnd),
        safeEnd,
        quoteState
      );
      if (gapResult.boundary) {
        return gapResult;
      }
      cursor = Math.max(cursor, gapResult.scannedTo);
      if (cursor >= safeEnd) {
        return { boundary: null, scannedTo: safeEnd, reason: null };
      }
    }

    let charPos = token.start_pos;
    for (const _ch of token.surface) {
      const ch = text[charPos];
      if (!ch) {
        break;
      }
      const charEnd = charPos + ch.length;
      if (charEnd <= cursor) {
        charPos = charEnd;
        continue;
      }
      if (charPos >= safeEnd) {
        break;
      }
      const found = scanBoundaryAtChar(text, charPos, safeEnd, quoteState);
      if (found) {
        return {
          boundary: found.boundary,
          scannedTo: found.boundary,
          reason: found.reason,
        };
      }
      cursor = Math.max(cursor, charEnd);
      charPos = charEnd;
    }
  }

  if (cursor < safeEnd) {
    const tailResult = scanRawRange(text, cursor, safeEnd, safeEnd, quoteState);
    if (tailResult.boundary) {
      return tailResult;
    }
    cursor = Math.max(cursor, tailResult.scannedTo);
  }

  return { boundary: null, scannedTo: Math.min(cursor, safeEnd), reason: null };
}
