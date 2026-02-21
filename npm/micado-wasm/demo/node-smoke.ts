import { createMicadoWasm, createTokenizer } from "../src/index.js";
import type { CompactToken } from "../src/types.js";

const sentence = "すもももももももものうち";
const wasm = await createMicadoWasm({
  nanoProfile: "tiny",
  miniProfile: "mini",
  compressed: true,
});
const wasmNano = wasm.tokenizeNano(sentence);
const wasmMini = wasm.tokenizeMini(sentence);
console.log(`wasm-nano=${wasmNano.map((t) => t.surface).join("|")}`);
console.log(`wasm-mini=${wasmMini.map((t) => t.surface).join("|")}`);

const tokenizer = await createTokenizer({
  profile: "tiny",
  compressed: true,
});
const dicTokens = tokenizer.tokenize(sentence);
console.log(`dic-tiny=${dicTokens.map((t) => t.surface).join("|")}`);
console.log(`profile=${tokenizer.profile} entries=${tokenizer.stats.entryCount}`);

const dicCompact: CompactToken[] = dicTokens.map((t) => ({
  surface: t.surface,
  pos_detail: t.pos_detail,
  start_pos: t.start_pos,
  end_pos: t.end_pos,
}));
if (JSON.stringify(wasmNano) !== JSON.stringify(dicCompact)) {
  throw new Error(
    "createMicadoWasm(tokenizeNano) must match createTokenizer(profile=tiny)"
  );
}
const miniTokenizer = await createTokenizer({ profile: "mini", compressed: true });
const miniCompact: CompactToken[] = miniTokenizer.tokenize(sentence).map((t) => ({
  surface: t.surface,
  pos_detail: t.pos_detail,
  start_pos: t.start_pos,
  end_pos: t.end_pos,
}));
if (JSON.stringify(wasmMini) !== JSON.stringify(miniCompact)) {
  throw new Error(
    "createMicadoWasm(tokenizeMini) must match createTokenizer(profile=mini)"
  );
}
console.log("unified=nano-ok");
console.log("unified=mini-ok");
