#!/usr/bin/env node
/**
 * MeCab Dictionary Converter
 *
 * Converts MeCab dictionary directories (ipadic, unidic, jumandic) to micado dic.bin format.
 * Reads CSV source files directly from the dictionary directory.
 *
 * Usage:
 *   node tools/dict-compiler/scripts/convert_mecab.mjs /path/to/mecab/dic -o output.dic.bin
 *
 * Examples:
 *   # Convert Homebrew ipadic
 *   node tools/dict-compiler/scripts/convert_mecab.mjs \
 *     /opt/homebrew/lib/mecab/dic/ipadic \
 *     -o npm/micado-wasm/dist/ipadic.dic.bin
 *
 *   # Convert with entry limit
 *   node tools/dict-compiler/scripts/convert_mecab.mjs \
 *     /opt/homebrew/lib/mecab/dic/ipadic \
 *     -o /tmp/ipadic-mini.dic.bin \
 *     --limit 10000
 */

import { resolve } from "node:path";
import { compileDicBinFromMecabDir } from "./web_dic_build_core.mjs";

const HELP = `
MeCab Dictionary Converter

Converts MeCab dictionary directories to micado dic.bin format.
Reads CSV source files from the dictionary directory, handling charset conversion automatically.

Usage:
  node convert_mecab.mjs <mecab-dic-dir> -o <output.dic.bin> [options]

Arguments:
  <mecab-dic-dir>    Path to MeCab dictionary directory (e.g., /opt/homebrew/lib/mecab/dic/ipadic)

Options:
  -o, --output PATH  Output path for dic.bin file (required)
  --limit N          Maximum number of entries to include
  --freq-tsv PATH    Optional frequency TSV file for sorting entries
  -h, --help         Show this help message

Supported dictionaries:
  - ipadic (IPA dictionary)
  - unidic (UniDic)
  - jumandic (JUMAN dictionary)

Examples:
  # Convert ipadic source to micado format
  node convert_mecab.mjs path/to/mecab-ipadic-2.7.0-20070801 -o ipadic.dic.bin

  # Convert with entry limit for smaller size
  node convert_mecab.mjs path/to/mecab-ipadic -o mini.dic.bin --limit 10000

Note:
  The tool reads CSV source files from the dictionary directory.
  Compiled MeCab dictionaries (sys.dic) are not supported - use the original source.

  When using --limit without --freq-tsv, common grammatical words (particles, etc.)
  may be excluded. For best results, either:
    - Use the full dictionary (no --limit)
    - Provide a frequency file (--freq-tsv) to prioritize common words
`.trim();

function parseArgs(argv) {
  if (argv.length === 0 || argv.includes("-h") || argv.includes("--help")) {
    console.log(HELP);
    process.exit(0);
  }

  let mecabDicPath = null;
  let outputPath = null;
  let limit = Number.MAX_SAFE_INTEGER;
  let freqPath = null;

  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];

    if (arg === "-o" || arg === "--output") {
      if (i + 1 >= argv.length) {
        throw new Error("-o/--output requires a value");
      }
      outputPath = resolve(argv[i + 1]);
      i++;
      continue;
    }

    if (arg === "--limit") {
      if (i + 1 >= argv.length) {
        throw new Error("--limit requires a value");
      }
      limit = Number.parseInt(argv[i + 1], 10);
      if (!Number.isFinite(limit) || limit <= 0) {
        throw new Error(`Invalid --limit value: ${argv[i + 1]}`);
      }
      i++;
      continue;
    }

    if (arg === "--freq-tsv") {
      if (i + 1 >= argv.length) {
        throw new Error("--freq-tsv requires a value");
      }
      freqPath = resolve(argv[i + 1]);
      i++;
      continue;
    }

    if (arg.startsWith("-")) {
      throw new Error(`Unknown option: ${arg}`);
    }

    // Positional argument: mecab dictionary path
    if (!mecabDicPath) {
      mecabDicPath = resolve(arg);
    } else {
      throw new Error(`Unexpected argument: ${arg}`);
    }
  }

  if (!mecabDicPath) {
    throw new Error("Missing required argument: <mecab-dic-dir>");
  }

  if (!outputPath) {
    throw new Error("Missing required option: -o/--output");
  }

  return { mecabDicPath, outputPath, limit, freqPath };
}

async function main() {
  const options = parseArgs(process.argv.slice(2));

  console.log(`[convert-mecab] Input: ${options.mecabDicPath}`);
  console.log(`[convert-mecab] Output: ${options.outputPath}`);
  if (options.limit < Number.MAX_SAFE_INTEGER) {
    console.log(`[convert-mecab] Limit: ${options.limit}`);
  }
  if (options.freqPath) {
    console.log(`[convert-mecab] Freq TSV: ${options.freqPath}`);
  }
  console.log();

  const result = await compileDicBinFromMecabDir(options);

  console.log();
  console.log(`[convert-mecab] Success!`);
  console.log(`  Charset: ${result.charset}`);
  console.log(`  Entries: ${result.entries}`);
  console.log(`  Connection IDs: ${result.ids}`);
  console.log(`  Size: ${result.bytes} bytes (${result.kb} KB)`);
  console.log(`  Output: ${result.outputPath}`);
}

main().catch((err) => {
  console.error(`[convert-mecab] Error: ${err?.message ?? String(err)}`);
  process.exit(1);
});
