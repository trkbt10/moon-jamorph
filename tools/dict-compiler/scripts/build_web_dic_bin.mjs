#!/usr/bin/env node
import { resolve } from "node:path";
import { compileDicBinFromTSV, resolveDefaultPaths } from "./web_dic_build_core.mjs";

const HELP =
  "usage: node tools/dict-compiler/scripts/build_web_dic_bin.mjs <input.tsv> <output.dic.bin> [--limit N] [--freq-tsv PATH] [--matrix-def PATH]";

function parseArgs(argv) {
  if (argv.length < 2) {
    throw new Error(HELP);
  }

  const inputPath = resolve(argv[0]);
  const outputPath = resolve(argv[1]);
  let limit = Number.MAX_SAFE_INTEGER;
  let freqPath = null;
  let matrixDefPath = resolveDefaultPaths().defaultMatrixDefPath;

  for (let i = 2; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--limit") {
      if (i + 1 >= argv.length) {
        throw new Error("--limit requires a value");
      }
      limit = Number.parseInt(argv[i + 1], 10);
      i += 1;
      continue;
    }
    if (arg === "--freq-tsv") {
      if (i + 1 >= argv.length) {
        throw new Error("--freq-tsv requires a value");
      }
      freqPath = resolve(argv[i + 1]);
      i += 1;
      continue;
    }
    if (arg === "--matrix-def") {
      if (i + 1 >= argv.length) {
        throw new Error("--matrix-def requires a value");
      }
      matrixDefPath = resolve(argv[i + 1]);
      i += 1;
      continue;
    }
    throw new Error(`unknown option: ${arg}`);
  }

  if (!Number.isFinite(limit) || limit <= 0) {
    throw new Error(`invalid --limit: ${limit}`);
  }

  return { inputPath, outputPath, limit, freqPath, matrixDefPath };
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  const result = await compileDicBinFromTSV(options);
  const freqInfo = result.freqPath ? ` freq=${result.freqPath}` : "";
  console.log(
    `[web-dic-bin] entries=${result.entries} ids=${result.ids} bytes=${result.bytes} (${result.kb}KB) out=${result.outputPath}${freqInfo}`,
  );
}

main().catch((err) => {
  console.error(err?.message ?? String(err));
  process.exit(1);
});
