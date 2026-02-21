#!/usr/bin/env node

import assert from "node:assert/strict";
import { streamTokenize } from "../src/lib/streaming/engine.ts";
import {
  consumeBlockTokens,
  dropConsumedTokens,
  mergePendingTokens,
} from "../src/lib/streaming/pending-tokens.ts";
import { createQuoteState, scanForBoundary } from "../src/lib/streaming/quote-boundary.ts";

function makeTokens(parts, posDetail = "記号,一般") {
  let cursor = 0;
  return parts.map((surface) => {
    const start = cursor;
    cursor += surface.length;
    return {
      surface,
      pos_detail: posDetail,
      mecab_feature: posDetail,
      start_pos: start,
      end_pos: cursor,
    };
  });
}

function toTSV(text) {
  let cursor = 0;
  const lines = [];
  for (const ch of text) {
    const start = cursor;
    cursor += ch.length;
    lines.push(`${ch}\t記号,一般\t記号,一般\t${start}\t${cursor}`);
  }
  return lines.join("\n");
}

function testQuoteBoundary() {
  const text = "太郎は「はい。」と言った。";
  const tokens = makeTokens(["太郎", "は", "「", "はい", "。", "」", "と", "言っ", "た", "。"]);
  const result = scanForBoundary(tokens, 0, text.length, createQuoteState(), text);
  assert.equal(result.boundary, text.length, "boundary should skip terminator inside quote");

  const textWithTrailing = "彼は言った。」  ";
  const tokens2 = makeTokens(["彼", "は", "言っ", "た", "。", "」", " ", " "]);
  const result2 = scanForBoundary(tokens2, 0, textWithTrailing.length, createQuoteState(), textWithTrailing);
  assert.equal(result2.boundary, textWithTrailing.length, "boundary should include trailing quote and spaces");
}

function testParagraphBreakBoundary() {
  const text = "前段\n\n\n後段。";
  const tokens = makeTokens(["前段", "\n", "\n", "\n", "後段", "。"]);
  const result = scanForBoundary(tokens, 0, text.length, createQuoteState(), text);
  assert.equal(result.reason, "paragraph-break");
  assert.equal(result.boundary, "前段\n\n\n".length);
}

function testPendingTokens() {
  const pending = [];
  const keys = new Set();
  const tokens = [
    ...makeTokens(["A", "B", "C"], "名詞,一般"),
    {
      surface: "B",
      pos_detail: "名詞,一般",
      mecab_feature: "名詞,一般",
      start_pos: 1,
      end_pos: 2,
    },
  ];

  mergePendingTokens(pending, keys, tokens, 1);
  assert.equal(pending.length, 2, "should skip consumed/duplicated tokens");
  assert.equal(pending[0].surface, "B");
  assert.equal(pending[1].surface, "C");

  const blockTokens = consumeBlockTokens(pending, keys, 1, 2);
  assert.equal(blockTokens.length, 1);
  assert.equal(blockTokens[0].surface, "B");

  dropConsumedTokens(pending, keys, 3);
  assert.equal(pending.length, 0, "all tokens should be consumed");
}

async function testEngine() {
  const text = "吾輩は「猫。」と言った。次の文。";
  const runtime = {
    stats: {
      profile: "test",
      sourceMode: "test",
      entryLimit: 0,
      targetDeflateBytes: 0,
    },
    tokenizeTSV(windowText) {
      return toTSV(windowText);
    },
  };

  const events = [];
  await streamTokenize({
    text,
    format: "compact",
    options: {
      windowChars: 8,
      overlapChars: 2,
      forceFlushChars: 64,
      notifyWindow: true,
      includeText: true,
    },
    runtime,
    send: async (event, data) => {
      events.push({ event, data });
      return true;
    },
  });

  assert.equal(events[0]?.event, "meta");
  assert.equal(events[events.length - 1]?.event, "done");
  assert.equal(events.filter((x) => x.event === "error").length, 0);

  const blocks = events.filter((x) => x.event === "block").map((x) => x.data);
  assert.ok(blocks.length >= 2, "should split by terminators outside quotes");
  const joined = blocks.map((b) => b.text).join("");
  assert.equal(joined, text, "joined block text should match source text");
  assert.equal(blocks[0].text, "吾輩は「猫。」と言った。");

  const done = events.find((x) => x.event === "done")?.data;
  assert.equal(done.finalCursor, text.length);
  assert.equal(done.textLength, text.length);
}

async function testEngineParagraphBreak() {
  const text = "第一段\n\n\n第二段";
  const runtime = {
    stats: {
      profile: "test",
      sourceMode: "test",
      entryLimit: 0,
      targetDeflateBytes: 0,
    },
    tokenizeTSV(windowText) {
      return toTSV(windowText);
    },
  };

  const events = [];
  await streamTokenize({
    text,
    format: "compact",
    options: {
      windowChars: 8,
      overlapChars: 2,
      forceFlushChars: 64,
      notifyWindow: true,
      includeText: true,
    },
    runtime,
    send: async (event, data) => {
      events.push({ event, data });
      return true;
    },
  });

  const blocks = events.filter((x) => x.event === "block").map((x) => x.data);
  assert.ok(blocks.length >= 2);
  assert.equal(blocks[0].reason, "paragraph-break");
  assert.equal(blocks[0].text, "第一段\n\n\n");
  assert.equal(blocks.map((x) => x.text).join(""), text);
}

async function testEngineDashParagraphBreak() {
  const text = "——\n\n次の行";
  const runtime = {
    stats: {
      profile: "test",
      sourceMode: "test",
      entryLimit: 0,
      targetDeflateBytes: 0,
    },
    tokenizeTSV(windowText) {
      return toTSV(windowText);
    },
  };

  const events = [];
  await streamTokenize({
    text,
    format: "compact",
    options: {
      windowChars: 6,
      overlapChars: 2,
      forceFlushChars: 64,
      notifyWindow: true,
      includeText: true,
    },
    runtime,
    send: async (event, data) => {
      events.push({ event, data });
      return true;
    },
  });

  const blocks = events.filter((x) => x.event === "block").map((x) => x.data);
  assert.ok(blocks.length >= 2);
  assert.equal(blocks[0].reason, "paragraph-break");
  assert.equal(blocks[0].text, "——\n\n");
  assert.equal(blocks.map((x) => x.text).join(""), text);
}

async function main() {
  testQuoteBoundary();
  testParagraphBreakBoundary();
  testPendingTokens();
  await testEngine();
  await testEngineParagraphBreak();
  await testEngineDashParagraphBreak();
  console.log("[test-streaming-core] ok");
}

main().catch((error) => {
  console.error(`[test-streaming-core] ${error?.stack ?? error}`);
  process.exit(1);
});
