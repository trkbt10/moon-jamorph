import {
  DICTIONARY_DEFLATE,
  ENTRY_LIMIT,
  PROFILE,
  SOURCE_MODE,
  TARGET_DEFLATE_BYTES,
  WASM_MODULE,
} from "../generated/profile.mjs";

const encoder = new TextEncoder();
const decoder = new TextDecoder();

let runtimeSingleton = null;
let runtimePromise = null;
let runtimeInitStartedAt = null;
let runtimeReadyAt = null;
let runtimeInitAttempts = 0;
let runtimeInitError = null;

export class ServiceUnavailableError extends Error {
  constructor(message, cause = null) {
    super(message);
    this.name = "ServiceUnavailableError";
    this.cause = cause;
  }
}

async function inflateDeflate(bytes) {
  const stream = new Blob([bytes]).stream().pipeThrough(new DecompressionStream("deflate"));
  return new Uint8Array(await new Response(stream).arrayBuffer());
}

function decodeOutput(exportsObject, outputLen) {
  const out = new Uint8Array(outputLen);
  for (let i = 0; i < outputLen; i += 1) {
    out[i] = exportsObject.output_byte_at(i);
  }
  return decoder.decode(out);
}

function writeBytesByPush(exportsObject, resetFn, pushFn, bytes) {
  exportsObject[resetFn]();
  for (const byte of bytes) {
    exportsObject[pushFn](byte);
  }
}

async function createRuntime() {
  const instantiated = await WebAssembly.instantiate(WASM_MODULE, {});
  const instance = "instance" in instantiated ? instantiated.instance : instantiated;
  const exportsObject = instance.exports;

  const compressedBytes = new Uint8Array(DICTIONARY_DEFLATE);
  const dicBytes = await inflateDeflate(compressedBytes);

  writeBytesByPush(exportsObject, "reset_dic_input", "push_dic_input_byte", dicBytes);
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

  function tokenizeTSV(text) {
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

export function getRuntimeStatus() {
  const now = Date.now();
  const state = runtimeSingleton
    ? "ready"
    : runtimePromise
      ? "initializing"
      : runtimeInitError
        ? "error"
        : "idle";
  const elapsedMs = runtimeInitStartedAt ? Math.max(0, now - runtimeInitStartedAt) : null;
  return {
    state,
    attempts: runtimeInitAttempts,
    initStartedAt: runtimeInitStartedAt ? new Date(runtimeInitStartedAt).toISOString() : null,
    readyAt: runtimeReadyAt ? new Date(runtimeReadyAt).toISOString() : null,
    elapsedMs,
    initError: runtimeInitError,
  };
}

export function warmRuntimeInBackground() {
  if (runtimeSingleton || runtimePromise) {
    return runtimePromise ?? Promise.resolve(runtimeSingleton);
  }
  return getRuntime().catch(() => {});
}

export function getRuntimeSync() {
  return runtimeSingleton;
}

export async function getRuntime() {
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
      .catch((error) => {
        runtimeInitError = String(error?.message ?? error);
        runtimePromise = null;
        runtimeSingleton = null;
        throw error;
      });
  }
  return runtimePromise;
}
