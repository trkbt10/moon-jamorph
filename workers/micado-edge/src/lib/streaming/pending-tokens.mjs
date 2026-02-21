export function tokenKey(token) {
  return `${token.start_pos}:${token.end_pos}:${token.surface}:${token.pos_detail}`;
}

function compareTokenOrder(a, b) {
  if (a.start_pos !== b.start_pos) {
    return a.start_pos - b.start_pos;
  }
  if (a.end_pos !== b.end_pos) {
    return a.end_pos - b.end_pos;
  }
  if (a.surface < b.surface) {
    return -1;
  }
  if (a.surface > b.surface) {
    return 1;
  }
  return 0;
}

export function mergePendingTokens(pendingTokens, pendingTokenKeys, tokens, emitCursor) {
  for (const token of tokens) {
    if (token.end_pos <= emitCursor || token.start_pos < emitCursor) {
      continue;
    }
    const key = tokenKey(token);
    if (pendingTokenKeys.has(key)) {
      continue;
    }
    pendingTokenKeys.add(key);
    pendingTokens.push(token);
  }
  pendingTokens.sort(compareTokenOrder);
}

export function dropConsumedTokens(pendingTokens, pendingTokenKeys, cursor) {
  let writeIndex = 0;
  for (const token of pendingTokens) {
    if (token.end_pos <= cursor) {
      pendingTokenKeys.delete(tokenKey(token));
      continue;
    }
    pendingTokens[writeIndex] = token;
    writeIndex += 1;
  }
  pendingTokens.length = writeIndex;
}

export function findForcedBoundary(pendingTokens, emitCursor, safeEnd) {
  let boundary = emitCursor;
  for (const token of pendingTokens) {
    if (token.end_pos <= emitCursor) {
      continue;
    }
    if (token.end_pos <= safeEnd && token.end_pos > boundary) {
      boundary = token.end_pos;
    }
  }
  return boundary > emitCursor ? boundary : safeEnd;
}

export function consumeBlockTokens(pendingTokens, pendingTokenKeys, start, end) {
  const blockTokens = [];
  let writeIndex = 0;
  for (const token of pendingTokens) {
    const key = tokenKey(token);
    if (token.end_pos <= start) {
      pendingTokenKeys.delete(key);
      continue;
    }
    if (token.end_pos <= end) {
      if (token.start_pos >= start) {
        blockTokens.push(token);
      }
      pendingTokenKeys.delete(key);
      continue;
    }
    pendingTokens[writeIndex] = token;
    writeIndex += 1;
  }
  pendingTokens.length = writeIndex;
  return blockTokens;
}
