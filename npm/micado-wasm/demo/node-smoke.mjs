import { createTokenizer } from "../index.mjs";

const tokenizer = await createTokenizer({
  dicURL: new URL("../dist/micado_web_small.dic.bin", import.meta.url),
});

const tokens = tokenizer.tokenize("すもももももももものうち");
console.log(tokens.map((t) => t.surface).join("|"));
console.log(`entries=${tokenizer.stats.entryCount}`);
