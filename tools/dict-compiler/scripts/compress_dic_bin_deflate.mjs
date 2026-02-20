#!/usr/bin/env node
import { readFile, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import { deflateSync } from "node:zlib";

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
  const src = await readFile(inputPath);
  const compressed = deflateSync(src, { level: 9 });
  await writeFile(outputPath, compressed);

  const ratio = src.byteLength === 0 ? 0 : (compressed.byteLength / src.byteLength) * 100;
  console.log(
    `[dic-deflate] in=${src.byteLength} out=${compressed.byteLength} ratio=${ratio.toFixed(1)}% file=${outputPath}`,
  );
}

main().catch((err) => {
  console.error(err?.message ?? String(err));
  process.exit(1);
});
