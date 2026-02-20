import { createMicadoWasm } from "../index.mjs";

const micado = await createMicadoWasm({
  wasmURL: new URL("../dist/micado_wasm.wasm", import.meta.url),
});

const tokens = micado.tokenizeNano("すもももももももものうち");
console.log(tokens.map((t) => t.surface).join("|"));
