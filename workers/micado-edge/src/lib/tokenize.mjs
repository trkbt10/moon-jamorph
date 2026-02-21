function posFromDetail(posDetail) {
  const cols = posDetail.split(",");
  const c0 = cols[0] || "未知語";
  const c1 = cols[1] || "*";
  return `${c0},${c1}`;
}

export function parseTokensFromTSV(tsv, detailed) {
  if (!tsv) {
    return [];
  }
  const tokens = [];
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
    const startPos = Number.parseInt(parts[hasFeature ? 3 : 2], 10);
    const endPos = Number.parseInt(parts[hasFeature ? 4 : 3], 10);
    if (!Number.isFinite(startPos) || !Number.isFinite(endPos)) {
      continue;
    }
    if (detailed) {
      const mecabFeature = hasFeature ? parts[2] : posDetail;
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

export function toCompactToken(token) {
  return {
    surface: token.surface,
    pos_detail: token.pos_detail,
    start_pos: token.start_pos,
    end_pos: token.end_pos,
  };
}

export function tokensToTSV(tokens) {
  return tokens
    .map(
      (token) =>
        `${token.surface}\t${token.pos_detail}\t${token.mecab_feature ?? token.pos_detail}\t${token.start_pos}\t${token.end_pos}`,
    )
    .join("\n");
}
