import { createMicadoWasm, createTokenizer } from "../index.mjs";

const wasm = await createMicadoWasm({
  wasmURL: new URL("../dist/micado_wasm.wasm", import.meta.url),
});
const wasmTokens = wasm.tokenizeNano("すもももももももものうち");
console.log(`wasm=${wasmTokens.map((t) => t.surface).join("|")}`);

const tokenizer = await createTokenizer({
  profile: "tiny",
  compressed: true,
});
const dicTokens = tokenizer.tokenize("すもももももももものうち");
console.log(`dic=${dicTokens.map((t) => t.surface).join("|")}`);
console.log(`profile=${tokenizer.profile} entries=${tokenizer.stats.entryCount}`);
