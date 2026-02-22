/**
 * Demo: Streaming tokenization API
 */
import { createTokenizer } from "../src/index.js";

async function main() {
  console.log("=== Streaming Tokenization Demo ===\n");

  const tokenizer = await createTokenizer({ profile: "mini" });
  console.log(`Loaded tokenizer: profile=${tokenizer.profile}, entries=${tokenizer.stats.entryCount}`);

  const text = "今日は良い天気です。明日も晴れるでしょう。東京タワーから富士山が見えました。";
  console.log(`\nInput text: ${text}\n`);

  // Pattern A: Synchronous generator
  console.log("--- Pattern A: Synchronous Generator ---");
  const writer = tokenizer.createWriter({ format: "detailed" });
  for (const event of writer.write(text)) {
    if (event.type === "meta") {
      console.log(`[meta] profile=${event.profile}, textLength=${event.textLength}`);
    } else if (event.type === "block") {
      console.log(`[block ${event.index}] reason=${event.reason}, tokens=${event.tokenCount}`);
      if (event.tokens) {
        for (const token of event.tokens) {
          console.log(`  - ${token.surface} (${token.pos_detail.split(",")[0]})`);
        }
      }
    } else if (event.type === "done") {
      console.log(`[done] blocks=${event.blocks}, windows=${event.windows}`);
    }
  }

  // Pattern B: ReadableStream
  console.log("\n--- Pattern B: ReadableStream ---");
  const writer2 = tokenizer.createWriter({ format: "compact" });
  const stream = writer2.stream(text);
  const reader = stream.getReader();
  let blockCount = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    if (value.type === "block") {
      blockCount++;
    }
  }
  console.log(`Received ${blockCount} blocks from ReadableStream`);

  // Pattern C: Response-like API
  console.log("\n--- Pattern C: Response-like API ---");
  const writer3 = tokenizer.createWriter({ format: "detailed" });
  const response = writer3.response(text);

  // .tokens()
  const tokens = await response.tokens();
  console.log(`response.tokens(): ${tokens.length} tokens`);
  console.log(`  First token: ${tokens[0]?.surface}`);
  console.log(`  Last token: ${tokens[tokens.length - 1]?.surface}`);

  // New response for .json() (previous one was consumed)
  const writer4 = tokenizer.createWriter({ format: "detailed" });
  const response2 = writer4.response(text);
  const result = await response2.json();
  console.log(`\nresponse.json():`);
  console.log(`  meta.profile: ${result.meta.profile}`);
  console.log(`  blocks: ${result.blocks.length}`);
  console.log(`  allTokens: ${result.allTokens.length}`);

  // New response for .text()
  const writer5 = tokenizer.createWriter({ format: "tsv" });
  const response3 = writer5.response(text);
  const tsv = await response3.text();
  console.log(`\nresponse.text() (TSV format):`);
  const lines = tsv.split("\n").slice(0, 3);
  for (const line of lines) {
    console.log(`  ${line}`);
  }
  console.log(`  ... (${tsv.split("\n").length} lines total)`);

  // Pattern D: Async iterator
  console.log("\n--- Pattern D: Async Iterator ---");
  const writer6 = tokenizer.createWriter({ format: "compact" });
  const response4 = writer6.response(text);
  let eventCount = 0;
  for await (const event of response4) {
    eventCount++;
  }
  console.log(`Async iterator: ${eventCount} events`);

  console.log("\n=== Demo Complete ===");
}

main().catch(console.error);
