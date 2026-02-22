/**
 * TDD tests for createTokenizer and loadDictionary
 */
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { describe, it } from "node:test";
import { createTokenizer, loadDictionary } from "../src/index.js";

describe("loadDictionary", () => {
  const distDir = new URL("../dist/", import.meta.url);

  it("should load dictionary from file path string", async () => {
    const dicPath = new URL("mini.dic.bin.deflate", distDir);
    const dictionary = await loadDictionary(dicPath.pathname);

    assert.ok(dictionary instanceof Uint8Array);
    assert.ok(dictionary.byteLength > 0);
  });

  it("should load dictionary from URL object", async () => {
    const dicURL = new URL("mini.dic.bin.deflate", distDir);
    const dictionary = await loadDictionary(dicURL);

    assert.ok(dictionary instanceof Uint8Array);
    assert.ok(dictionary.byteLength > 0);
  });

  it("should load dictionary from Response", async () => {
    const dicURL = new URL("mini.dic.bin.deflate", distDir);
    const response = new Response(await readFile(dicURL));
    const dictionary = await loadDictionary(response);

    assert.ok(dictionary instanceof Uint8Array);
    assert.ok(dictionary.byteLength > 0);
  });

  it("should load dictionary from Uint8Array (passthrough)", async () => {
    const dicURL = new URL("mini.dic.bin.deflate", distDir);
    const raw = new Uint8Array(await readFile(dicURL));
    const dictionary = await loadDictionary(raw);

    assert.strictEqual(dictionary, raw);
  });

  it("should auto-decompress deflate dictionary", async () => {
    const compressedURL = new URL("mini.dic.bin.deflate", distDir);
    const dictionary = await loadDictionary(compressedURL);

    const compressedSize = (await readFile(compressedURL)).byteLength;
    assert.ok(dictionary.byteLength > compressedSize);
  });
});

describe("createTokenizer", () => {
  const distDir = new URL("../dist/", import.meta.url);

  it("should create tokenizer with dictionary", async () => {
    const dictionary = await loadDictionary(new URL("mini.dic.bin.deflate", distDir));
    const tokenizer = await createTokenizer(dictionary);

    assert.equal(tokenizer.backend, "wasm");
    assert.ok(tokenizer.stats.entryCount > 0);
  });

  it("should tokenize text", async () => {
    const dictionary = await loadDictionary(new URL("mini.dic.bin.deflate", distDir));
    const tokenizer = await createTokenizer(dictionary);

    const tokens = tokenizer.tokenize("今日は良い天気です");
    assert.ok(tokens.length > 0);
    assert.equal(tokens[0].surface, "今日");
  });

  it("should tokenize to TSV", async () => {
    const dictionary = await loadDictionary(new URL("mini.dic.bin.deflate", distDir));
    const tokenizer = await createTokenizer(dictionary);

    const tsv = tokenizer.tokenizeTSV("テスト");
    assert.ok(tsv.includes("テスト"));
    assert.ok(tsv.includes("\t"));
  });

  describe("streaming", () => {
    it("should have createWriter", async () => {
      const dictionary = await loadDictionary(new URL("mini.dic.bin.deflate", distDir));
      const tokenizer = await createTokenizer(dictionary);

      assert.equal(typeof tokenizer.createWriter, "function");
    });

    it("should stream with write()", async () => {
      const dictionary = await loadDictionary(new URL("mini.dic.bin.deflate", distDir));
      const tokenizer = await createTokenizer(dictionary);
      const writer = tokenizer.createWriter();

      const events = [...writer.write("今日は。")];
      assert.ok(events.some(e => e.type === "meta"));
      assert.ok(events.some(e => e.type === "block"));
      assert.ok(events.some(e => e.type === "done"));
    });

    it("should get tokens via response().tokens()", async () => {
      const dictionary = await loadDictionary(new URL("mini.dic.bin.deflate", distDir));
      const tokenizer = await createTokenizer(dictionary);

      const tokens = await tokenizer.createWriter().response("テスト。").tokens();
      assert.ok(tokens.length > 0);
    });

    it("should create SSE response", async () => {
      const dictionary = await loadDictionary(new URL("mini.dic.bin.deflate", distDir));
      const tokenizer = await createTokenizer(dictionary);

      const response = tokenizer.createWriter().response("テスト。").toSSEResponse();
      assert.ok(response instanceof Response);
      assert.equal(response.headers.get("content-type"), "text/event-stream; charset=utf-8");
    });
  });
});
