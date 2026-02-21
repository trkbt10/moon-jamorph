import { normalizeInt, parseBoolean } from "../http.js";
import type { StreamOptions, StreamOptionsInput } from "../../types.js";

export function normalizeStreamOptions(raw: StreamOptionsInput = {}): StreamOptions {
  const windowChars = normalizeInt(raw.windowChars, 1024, 1024, 65536);
  const overlapChars = normalizeInt(
    raw.overlapChars,
    256,
    128,
    Math.max(128, windowChars - 256)
  );
  const forceFlushChars = normalizeInt(
    raw.forceFlushChars,
    Math.max(windowChars * 2, 4096),
    Math.max(windowChars, 2048),
    windowChars * 32
  );
  const notifyWindow = parseBoolean(raw.notifyWindow as string | undefined, true);
  const includeText = parseBoolean(raw.includeText as string | undefined, true);
  return {
    windowChars,
    overlapChars,
    forceFlushChars,
    notifyWindow,
    includeText,
  };
}
