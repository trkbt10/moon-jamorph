import { createWebSmallTokenizer } from "../index.mjs";

const tokenizer = await createWebSmallTokenizer({
  dicURL: new URL("../dist/micado_web_small.dic.bin", import.meta.url),
});

const tokens = tokenizer.tokenize("東京大学で自然言語処理を学ぶ");
console.log(tokens.map((t) => `${t.surface}:${t.pos}`).join("|"));
console.log(`entries=${tokenizer.stats.entryCount} maxLen=${tokenizer.stats.maxSurfaceLength}`);
