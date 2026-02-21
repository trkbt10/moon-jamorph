import {
  DICTIONARY_DEFLATE,
  ENTRY_LIMIT,
  PROFILE,
  SOURCE_MODE,
  TARGET_DEFLATE_BYTES,
  WASM_MODULE,
} from "../generated/profile.mjs";
import type { MicadoWasmExports, Runtime, RuntimeStatus } from "../types.js";

const encoder = new TextEncoder();
const decoder = new TextDecoder();

let runtimeSingleton: Runtime | null = null;
let runtimePromise: Promise<Runtime> | null = null;
let runtimeInitStartedAt: number | null = null;
let runtimeReadyAt: number | null = null;
let runtimeInitAttempts = 0;
let runtimeInitError: string | null = null;

export class ServiceUnavailableError extends Error {
  cause: unknown;
  constructor(message: string, cause: unknown = null) {
    super(message);
    this.name = "ServiceUnavailableError";
    this.cause = cause;
  }
}

async function inflateDeflate(bytes: Uint8Array): Promise<Uint8Array> {
  const stream = new Blob([bytes])
    .stream()
    .pipeThrough(new DecompressionStream("deflate"));
  return new Uint8Array(await new Response(stream).arrayBuffer());
}

function decodeOutput(exportsObject: MicadoWasmExports, outputLen: number): string {
  const out = new Uint8Array(outputLen);
  for (let i = 0; i < outputLen; i += 1) {
    out[i] = exportsObject.output_byte_at(i);
  }
  return decoder.decode(out);
}

function writeBytesByPush(
  exportsObject: MicadoWasmExports,
  resetFn: "reset_input" | "reset_dic_input",
  pushFn: "push_input_byte" | "push_dic_input_byte",
  bytes: Uint8Array
): void {
  exportsObject[resetFn]();
  for (const byte of bytes) {
    exportsObject[pushFn](byte);
  }
}

async function createRuntime(): Promise<Runtime> {
  const instance = await WebAssembly.instantiate(WASM_MODULE, {});
  const exportsObject = instance.exports as unknown as MicadoWasmExports;

  const compressedBytes = new Uint8Array(DICTIONARY_DEFLATE);
  const dicBytes = await inflateDeflate(compressedBytes);

  writeBytesByPush(
    exportsObject,
    "reset_dic_input",
    "push_dic_input_byte",
    dicBytes
  );
  const loaded = exportsObject.load_dic_bin();
  if (loaded < 0) {
    throw new Error("Failed to load dictionary bytes into wasm runtime");
  }

  const stats = {
    profile: PROFILE,
    sourceMode: SOURCE_MODE,
    entryLimit: ENTRY_LIMIT,
    targetDeflateBytes: TARGET_DEFLATE_BYTES,
    dictionaryCompressedBytes: compressedBytes.byteLength,
    dictionaryBytes: dicBytes.byteLength,
    entryCount: exportsObject.dictionary_entry_count(),
    maxSurfaceLength: exportsObject.dictionary_max_surface_length(),
    connectionIdCount: exportsObject.dictionary_connection_id_count(),
  };

  function tokenizeTSV(text: string): string {
    const input = encoder.encode(text);
    writeBytesByPush(exportsObject, "reset_input", "push_input_byte", input);
    const outputLen = exportsObject.tokenize_nano_tsv();
    return decodeOutput(exportsObject, outputLen);
  }

  return {
    stats,
    tokenizeTSV,
  };
}

export function getRuntimeStatus(): RuntimeStatus {
  const now = Date.now();
  const state = runtimeSingleton
    ? "ready"
    : runtimePromise
      ? "initializing"
      : runtimeInitError
        ? "error"
        : "idle";
  const elapsedMs = runtimeInitStartedAt
    ? Math.max(0, now - runtimeInitStartedAt)
    : null;
  return {
    state,
    attempts: runtimeInitAttempts,
    initStartedAt: runtimeInitStartedAt
      ? new Date(runtimeInitStartedAt).toISOString()
      : null,
    readyAt: runtimeReadyAt ? new Date(runtimeReadyAt).toISOString() : null,
    elapsedMs,
    initError: runtimeInitError,
  };
}

export function warmRuntimeInBackground(): Promise<Runtime | void> | null {
  if (runtimeSingleton || runtimePromise) {
    return runtimePromise ?? Promise.resolve(runtimeSingleton!);
  }
  return getRuntime().catch(() => {});
}

export function getRuntimeSync(): Runtime | null {
  return runtimeSingleton;
}

export async function getRuntime(): Promise<Runtime> {
  if (runtimeSingleton) {
    return runtimeSingleton;
  }
  if (!runtimePromise) {
    runtimeInitAttempts += 1;
    runtimeInitStartedAt = Date.now();
    runtimeReadyAt = null;
    runtimeInitError = null;
    runtimePromise = createRuntime()
      .then((runtime) => {
        runtimeSingleton = runtime;
        runtimeReadyAt = Date.now();
        return runtime;
      })
      .catch((error: unknown) => {
        runtimeInitError = String(
          error instanceof Error ? error.message : error
        );
        runtimePromise = null;
        runtimeSingleton = null;
        throw error;
      });
  }
  return runtimePromise;
}
