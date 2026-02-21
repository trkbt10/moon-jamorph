import type {
  BlockReason,
  DetailedToken,
  Runtime,
  StreamOptions,
  TokenFormat,
} from "../../types.js";
import { parseTokensFromTSV } from "../tokenize.js";
import { normalizeBlockPayload } from "./payload.js";
import { createQuoteState, scanForBoundary } from "./quote-boundary.js";
import {
  consumeBlockTokens,
  dropConsumedTokens,
  findForcedBoundary,
  mergePendingTokens,
} from "./pending-tokens.js";

function toWindowTokens(tsv: string, windowStart: number): DetailedToken[] {
  return parseTokensFromTSV(tsv, true).map((token) => ({
    ...token,
    start_pos: token.start_pos + windowStart,
    end_pos: token.end_pos + windowStart,
  }));
}

function nextWindowStart(
  windowStart: number,
  step: number,
  emitCursor: number,
  overlapChars: number,
  textLength: number
): number {
  const resultDrivenStart = Math.max(
    windowStart + step,
    Math.max(0, emitCursor - overlapChars)
  );
  return Math.min(textLength, Math.max(windowStart + 1, resultDrivenStart));
}

export interface StreamTokenizeParams {
  text: string;
  format: TokenFormat;
  options: StreamOptions;
  runtime: Runtime;
  send: (event: string, payload: unknown) => Promise<boolean>;
}

export async function streamTokenize({
  text,
  format,
  options,
  runtime,
  send,
}: StreamTokenizeParams): Promise<void> {
  const pendingTokens: DetailedToken[] = [];
  const pendingTokenKeys = new Set<string>();
  const quoteState = createQuoteState();
  const step = Math.max(1, options.windowChars - options.overlapChars);
  let windowStart = 0;
  let emitCursor = 0;
  let scanCursor = 0;
  let blockIndex = 0;
  let windowIndex = 0;

  const emitBlock = async (
    boundary: number,
    reason: BlockReason
  ): Promise<boolean> => {
    if (boundary <= emitCursor) {
      return false;
    }
    const start = emitCursor;
    const end = boundary;
    const blockText = text.slice(start, end);
    const blockTokens = consumeBlockTokens(
      pendingTokens,
      pendingTokenKeys,
      start,
      end
    );
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
      windowEnd === text.length
        ? text.length
        : Math.max(emitCursor, windowEnd - options.overlapChars);
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
        text
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
        safeEnd > emitCursor &&
        (safeEnd - emitCursor >= options.forceFlushChars ||
          safeEnd === text.length);
      if (needForceFlush) {
        const forcedBoundary = findForcedBoundary(
          pendingTokens,
          emitCursor,
          safeEnd
        );
        const forceReason: BlockReason =
          safeEnd === text.length ? "eof" : "forced";
        const emitted = await emitBlock(forcedBoundary, forceReason);
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
    windowStart = nextWindowStart(
      windowStart,
      step,
      emitCursor,
      options.overlapChars,
      text.length
    );
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
