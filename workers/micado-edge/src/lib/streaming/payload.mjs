import { toCompactToken, tokensToTSV } from "../tokenize.mjs";

export function normalizeBlockPayload(blockTokens, format) {
  if (format === "tsv") {
    return { tsv: tokensToTSV(blockTokens), tokenCount: blockTokens.length };
  }
  if (format === "compact") {
    return {
      tokenCount: blockTokens.length,
      tokens: blockTokens.map((token) => toCompactToken(token)),
    };
  }
  return {
    tokenCount: blockTokens.length,
    tokens: blockTokens,
  };
}
