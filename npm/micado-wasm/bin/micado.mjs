#!/usr/bin/env node
import { readFile } from "node:fs/promises";
import { createInterface } from "node:readline";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const __dirname = dirname(fileURLToPath(import.meta.url));

async function loadWasm() {
  const wasmPath = join(__dirname, "../dist/micado_cli.wasm");
  const wasmBinary = await readFile(wasmPath);
  const result = await WebAssembly.instantiate(wasmBinary, {});
  return result.instance.exports;
}

async function loadDictionary(wasm, profile, compressed) {
  const ext = compressed ? ".dic.bin.deflate" : ".dic.bin";
  const dicPath = join(__dirname, `../dist/${profile}${ext}`);
  let dicBytes = await readFile(dicPath);

  if (compressed) {
    const { inflateSync } = await import("node:zlib");
    dicBytes = inflateSync(dicBytes);
  }

  wasm.reset_dic_input();
  for (const byte of dicBytes) {
    wasm.push_dic_input_byte(byte);
  }
  const result = wasm.load_dic_bin();
  if (result < 0) {
    throw new Error("Failed to load dictionary");
  }
  return result;
}

function pushArgs(wasm, args) {
  const encoder = new TextEncoder();
  wasm.reset_args();
  for (const arg of args) {
    const bytes = encoder.encode(arg);
    for (const byte of bytes) {
      wasm.push_arg_byte(byte);
    }
    wasm.finalize_arg();
  }
}

function getOutput(wasm) {
  const len = wasm.output_length();
  const bytes = new Uint8Array(len);
  for (let i = 0; i < len; i++) {
    bytes[i] = wasm.output_byte_at(i);
  }
  return new TextDecoder().decode(bytes);
}

function processLine(wasm, line) {
  const encoder = new TextEncoder();
  const bytes = encoder.encode(line);
  wasm.reset_line();
  for (const byte of bytes) {
    wasm.push_line_byte(byte);
  }
  wasm.process_line();
  return getOutput(wasm);
}

// Map edition names to dictionary profile filenames
const EDITION_TO_PROFILE = {
  nano: "tiny",
  tiny: "tiny",
  mini: "mini",
  standard: "medium",
  medium: "medium",
  full: "full",
};

function parseEditionFromArgs(args) {
  for (let i = 0; i < args.length; i++) {
    if (args[i] === "-e" || args[i] === "--edition") {
      const edition = args[i + 1]?.toLowerCase();
      return EDITION_TO_PROFILE[edition] || "full";
    }
  }
  return "full";
}

function parseOutputModeFromArgs(args) {
  for (let i = 0; i < args.length; i++) {
    if (args[i] === "-O" || args[i] === "--output" || args[i] === "--output-format-type") {
      return args[i + 1]?.toLowerCase() || "mecab";
    }
    if (args[i].startsWith("-O") && args[i].length > 2) {
      return args[i].slice(2).toLowerCase();
    }
    if (args[i].startsWith("--output-format-type=")) {
      return args[i].slice(21).toLowerCase();
    }
  }
  return "mecab";
}

async function main() {
  const args = process.argv.slice(2);

  try {
    const wasm = await loadWasm();

    // Determine dictionary profile from args
    const profile = parseEditionFromArgs(args);
    await loadDictionary(wasm, profile, true);

    // Initialize CLI with args
    pushArgs(wasm, args);
    const initResult = wasm.init_cli();

    if (initResult === -2) {
      // Help was requested
      console.log(getOutput(wasm));
      process.exit(0);
    }

    if (initResult === -3) {
      // Version was requested
      console.log(getOutput(wasm));
      process.exit(0);
    }

    if (initResult < 0) {
      console.error(getOutput(wasm));
      process.exit(1);
    }

    // Check if there are input texts from command line arguments
    const inputTextCount = wasm.get_input_text_count();
    const outputMode = parseOutputModeFromArgs(args);

    if (inputTextCount > 0) {
      // Process input texts from arguments (MeCab compatible)
      for (let i = 0; i < inputTextCount; i++) {
        wasm.process_input_text(i);
        const output = getOutput(wasm);
        if (output && outputMode !== "count" && outputMode !== "none") {
          console.log(output);
        }
      }
    } else {
      // Process stdin line by line
      const rl = createInterface({
        input: process.stdin,
        crlfDelay: Infinity,
      });

      for await (const line of rl) {
        const output = processLine(wasm, line);
        if (output && outputMode !== "count" && outputMode !== "none") {
          console.log(output);
        }
      }
    }

    // Print statistics for count mode
    if (outputMode === "count") {
      const sentences = wasm.get_sentence_count();
      const tokens = wasm.get_token_count();
      console.log(`sentences=${sentences} tokens=${tokens}`);
    }
  } catch (err) {
    console.error(`Error: ${err.message}`);
    process.exit(1);
  }
}

main();
