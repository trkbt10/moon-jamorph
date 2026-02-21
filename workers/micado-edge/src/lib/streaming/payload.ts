import { toCompactToken, tokensToTSV } from "../tokenize.js";
import type { DetailedToken, TokenFormat } from "../../types.js";

export interface BlockPayload {
  tokenCount: number;
  tokens?: unknown[];
  tsv?: string;
}

export function normalizeBlockPayload(
  blockTokens: DetailedToken[],
  format: TokenFormat
): BlockPayload {
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
