#!/usr/bin/env node
import { resolve } from "node:path";
import {
  DEFAULT_LIMITS,
  buildWebDicArtifacts,
  ensureWebSmallTSV,
} from "./web_dic_build_core.mjs";

const HELP = `usage:
  node tools/dict-compiler/scripts/build_web_dic_artifacts.mjs --out-dir <dir> [--tiny-limit N] [--mini-limit N] [--medium-limit N] [--full-limit N] [--freq-tsv PATH] [--matrix-def PATH] [--web-tsv PATH]
  node tools/dict-compiler/scripts/build_web_dic_artifacts.mjs --only-tsv --limit N [--web-tsv PATH]
`;

function parseArgs(argv) {
  let outDir = null;
  let tinyLimit = DEFAULT_LIMITS.tiny;
  let miniLimit = DEFAULT_LIMITS.mini;
  let mediumLimit = DEFAULT_LIMITS.medium;
  let fullLimit = DEFAULT_LIMITS.full;
  let freqPath = null;
  let matrixDefPath = null;
  let webTsvPath = null;
  let onlyTsv = false;
  let limit = null;

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--out-dir") {
      if (i + 1 >= argv.length) {
        throw new Error("--out-dir requires a value");
      }
      outDir = resolve(argv[i + 1]);
      i += 1;
      continue;
    }
    if (arg === "--tiny-limit") {
      tinyLimit = Number.parseInt(argv[i + 1], 10);
      i += 1;
      continue;
    }
    if (arg === "--mini-limit") {
      miniLimit = Number.parseInt(argv[i + 1], 10);
      i += 1;
      continue;
    }
    if (arg === "--medium-limit") {
      mediumLimit = Number.parseInt(argv[i + 1], 10);
      i += 1;
      continue;
    }
    if (arg === "--full-limit") {
      fullLimit = Number.parseInt(argv[i + 1], 10);
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
    if (arg === "--web-tsv") {
      if (i + 1 >= argv.length) {
        throw new Error("--web-tsv requires a value");
      }
      webTsvPath = resolve(argv[i + 1]);
      i += 1;
      continue;
    }
    if (arg === "--only-tsv") {
      onlyTsv = true;
      continue;
    }
    if (arg === "--limit") {
      if (i + 1 >= argv.length) {
        throw new Error("--limit requires a value");
      }
      limit = Number.parseInt(argv[i + 1], 10);
      i += 1;
      continue;
    }
    throw new Error(`unknown option: ${arg}`);
  }

  return {
    outDir,
    tinyLimit,
    miniLimit,
    mediumLimit,
    fullLimit,
    freqPath,
    matrixDefPath,
    webTsvPath,
    onlyTsv,
    limit,
  };
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.onlyTsv) {
    const info = await ensureWebSmallTSV({
      limit: args.limit ?? args.fullLimit,
      outputPath: args.webTsvPath,
    });
    console.log(`[web-small] matrix.def: ${info.matrixDefPath}`);
    return;
  }

  if (!args.outDir) {
    throw new Error(`${HELP.trim()}\n\n--out-dir is required`);
  }

  const result = await buildWebDicArtifacts({
    outDir: args.outDir,
    limits: {
      tiny: args.tinyLimit,
      mini: args.miniLimit,
      medium: args.mediumLimit,
      full: args.fullLimit,
    },
    freqPath: args.freqPath,
    matrixDefPath: args.matrixDefPath,
    webTsvPath: args.webTsvPath,
  });

  if (result.freqPath) {
    console.log(`[web-dic-artifacts] frequency source: ${result.freqPath}`);
  }
  console.log(`[web-dic-artifacts] tsv: ${result.tsvPath}`);
  for (const item of result.summaries) {
    console.log(
      `[web-dic-artifacts] ${item.profile}: entries=${item.entries} ids=${item.ids} bytes=${item.bytes} deflate=${item.compressedBytes} ratio=${item.ratio.toFixed(1)}%`,
    );
  }
}

main().catch((err) => {
  console.error(err?.message ?? String(err));
  process.exit(1);
});
