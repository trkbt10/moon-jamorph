#!/usr/bin/env node
import { resolve } from "node:path";
import { compressDicBinDeflate } from "./web_dic_build_core.mjs";

const HELP =
  "usage: node tools/dict-compiler/scripts/compress_dic_bin_deflate.mjs <input.dic.bin> <output.dic.bin.deflate>";

function parseArgs(argv) {
  if (argv.length !== 2) {
    throw new Error(HELP);
  }
  return {
    inputPath: resolve(argv[0]),
    outputPath: resolve(argv[1]),
  };
}

async function main() {
  const { inputPath, outputPath } = parseArgs(process.argv.slice(2));
  const result = await compressDicBinDeflate({ inputPath, outputPath });
  console.log(
    `[dic-deflate] in=${result.inputBytes} out=${result.outputBytes} ratio=${result.ratio.toFixed(1)}% file=${result.outputPath}`,
  );
}

main().catch((err) => {
  console.error(err?.message ?? String(err));
  process.exit(1);
});
