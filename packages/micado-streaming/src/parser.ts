import type { CompactToken, DetailedToken, Token, TokenFormat } from "./types.js";

function posFromDetail(posDetail: string): string {
  const cols = posDetail.split(",");
  const c0 = cols[0] || "未知語";
  const c1 = cols[1] || "*";
  return `${c0},${c1}`;
}

export function parseTokensFromTSV(tsv: string, detailed: true): DetailedToken[];
export function parseTokensFromTSV(tsv: string, detailed: false): CompactToken[];
export function parseTokensFromTSV(
  tsv: string,
  detailed: boolean
): CompactToken[] | DetailedToken[] {
  if (!tsv) {
    return [];
  }
  const tokens: Token[] = [];
  const lines = tsv.split("\n");
  for (const line of lines) {
    if (!line) {
      continue;
    }
    const parts = line.split("\t");
    const surface = parts[0];
    const posDetail = parts[1];
    if (!surface || !posDetail) {
      continue;
    }
    const hasFeature = parts.length >= 5;
    const startPos = Number.parseInt(parts[hasFeature ? 3 : 2] ?? "", 10);
    const endPos = Number.parseInt(parts[hasFeature ? 4 : 3] ?? "", 10);
    if (!Number.isFinite(startPos) || !Number.isFinite(endPos)) {
      continue;
    }
    if (detailed) {
      const mecabFeature = hasFeature ? (parts[2] ?? posDetail) : posDetail;
      tokens.push({
        surface,
        pos: posFromDetail(posDetail),
        pos_detail: posDetail,
        mecab_feature: mecabFeature,
        start_pos: startPos,
        end_pos: endPos,
      });
    } else {
      tokens.push({
        surface,
        pos_detail: posDetail,
        start_pos: startPos,
        end_pos: endPos,
      });
    }
  }
  return tokens;
}

export function toCompactToken(token: Token): CompactToken {
  return {
    surface: token.surface,
    pos_detail: token.pos_detail,
    start_pos: token.start_pos,
    end_pos: token.end_pos,
  };
}

export function tokensToTSV(tokens: Token[]): string {
  return tokens
    .map((token) => {
      const mecabFeature =
        "mecab_feature" in token ? token.mecab_feature : token.pos_detail;
      return `${token.surface}\t${token.pos_detail}\t${mecabFeature}\t${token.start_pos}\t${token.end_pos}`;
    })
    .join("\n");
}

export interface BlockPayload {
  tokenCount: number;
  tokens?: CompactToken[] | DetailedToken[];
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
