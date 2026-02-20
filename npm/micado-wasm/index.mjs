import { createDicBinTokenizer, loadDicBin, parseDicBin } from "./dic-bin.mjs";

const DEFAULT_DIC_BIN_URL = new URL("./dist/micado_web_small.dic.bin", import.meta.url);

export async function createTokenizer(options = {}) {
  const dic = await loadDicBin(options.dicURL ?? DEFAULT_DIC_BIN_URL);
  return createDicBinTokenizer(dic);
}

export async function createWebSmallTokenizer(options = {}) {
  return createTokenizer(options);
}

export { parseDicBin, loadDicBin, createDicBinTokenizer };
