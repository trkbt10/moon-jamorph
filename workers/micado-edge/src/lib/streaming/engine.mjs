import { parseTokensFromTSV } from "../tokenize.mjs";
import { normalizeBlockPayload } from "./payload.mjs";
import { createQuoteState, scanForBoundary } from "./quote-boundary.mjs";
import {
  consumeBlockTokens,
  dropConsumedTokens,
  findForcedBoundary,
  mergePendingTokens,
} from "./pending-tokens.mjs";

function toWindowTokens(tsv, windowStart) {
  return parseTokensFromTSV(tsv, true).map((token) => ({
    ...token,
    start_pos: token.start_pos + windowStart,
    end_pos: token.end_pos + windowStart,
  }));
}

function nextWindowStart(windowStart, step, emitCursor, overlapChars, textLength) {
  const resultDrivenStart = Math.max(windowStart + step, Math.max(0, emitCursor - overlapChars));
  return Math.min(textLength, Math.max(windowStart + 1, resultDrivenStart));
}

export async function streamTokenize({ text, format, options, runtime, send }) {
  const pendingTokens = [];
  const pendingTokenKeys = new Set();
  const quoteState = createQuoteState();
  const step = Math.max(1, options.windowChars - options.overlapChars);
  let windowStart = 0;
  let emitCursor = 0;
  let scanCursor = 0;
  let blockIndex = 0;
  let windowIndex = 0;

  const emitBlock = async (boundary, reason) => {
    if (boundary <= emitCursor) {
      return false;
    }
    const start = emitCursor;
    const end = boundary;
    const blockText = text.slice(start, end);
    const blockTokens = consumeBlockTokens(pendingTokens, pendingTokenKeys, start, end);
    const payload = normalizeBlockPayload(blockTokens, format);
    const sentBlock = await send("block", {
      index: blockIndex,
      reason,
      start,
      end,
      charLength: end - start,
      text: options.includeText ? blockText : undefined,
      ...payload,
    });
    if (!sentBlock) {
      return false;
    }
    emitCursor = end;
    scanCursor = Math.max(scanCursor, emitCursor);
    dropConsumedTokens(pendingTokens, pendingTokenKeys, emitCursor);
    blockIndex += 1;
    return true;
  };

  const sentMeta = await send("meta", {
    profile: runtime.stats.profile,
    sourceMode: runtime.stats.sourceMode,
    entryLimit: runtime.stats.entryLimit,
    targetDeflateBytes: runtime.stats.targetDeflateBytes,
    textLength: text.length,
    format,
    options,
  });
  if (!sentMeta) {
    return;
  }

  while (windowStart < text.length) {
    const windowEnd = Math.min(text.length, windowStart + options.windowChars);
    const windowText = text.slice(windowStart, windowEnd);
    const tsv = runtime.tokenizeTSV(windowText);
    const windowTokens = toWindowTokens(tsv, windowStart);
    mergePendingTokens(pendingTokens, pendingTokenKeys, windowTokens, emitCursor);
    dropConsumedTokens(pendingTokens, pendingTokenKeys, emitCursor);

    const safeEnd =
      windowEnd === text.length ? text.length : Math.max(emitCursor, windowEnd - options.overlapChars);
    scanCursor = Math.max(scanCursor, emitCursor);
    if (scanCursor > safeEnd) {
      scanCursor = safeEnd;
    }

    if (options.notifyWindow) {
      const sentWindow = await send("window", {
        index: windowIndex,
        start: windowStart,
        end: windowEnd,
        safeEnd,
        emitCursor,
        scanCursor,
        pendingTokenCount: pendingTokens.length,
        tokenCount: windowTokens.length,
      });
      if (!sentWindow) {
        return;
      }
    }

    while (true) {
      scanCursor = Math.max(scanCursor, emitCursor);
      if (scanCursor > safeEnd) {
        scanCursor = safeEnd;
      }
      const { boundary, scannedTo, reason } = scanForBoundary(
        pendingTokens,
        scanCursor,
        safeEnd,
        quoteState,
        text,
      );
      scanCursor = Math.max(scanCursor, scannedTo);

      if (boundary && boundary > emitCursor) {
        const emitted = await emitBlock(boundary, reason ?? "terminator");
        if (!emitted) {
          return;
        }
        continue;
      }

      const needForceFlush =
        safeEnd > emitCursor && (safeEnd - emitCursor >= options.forceFlushChars || safeEnd === text.length);
      if (needForceFlush) {
        const forcedBoundary = findForcedBoundary(pendingTokens, emitCursor, safeEnd);
        const reason = safeEnd === text.length ? "eof" : "forced";
        const emitted = await emitBlock(forcedBoundary, reason);
        if (!emitted) {
          return;
        }
        continue;
      }
      break;
    }

    if (windowEnd >= text.length) {
      break;
    }
    windowStart = nextWindowStart(windowStart, step, emitCursor, options.overlapChars, text.length);
    windowIndex += 1;
  }

  if (emitCursor < text.length) {
    const emitted = await emitBlock(text.length, "eof");
    if (!emitted) {
      return;
    }
  }

  await send("done", {
    windows: windowIndex + 1,
    blocks: blockIndex,
    finalCursor: emitCursor,
    textLength: text.length,
  });
}
