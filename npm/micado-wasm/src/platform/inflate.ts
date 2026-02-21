/**
 * Platform-agnostic deflate decompression.
 * Uses DecompressionStream in browsers and zlib in Node.js.
 */
export async function inflateDeflate(bytes: Uint8Array): Promise<Uint8Array> {
  if (typeof DecompressionStream !== "undefined") {
    const stream = new Blob([bytes as BlobPart])
      .stream()
      .pipeThrough(new DecompressionStream("deflate"));
    const arrayBuffer = await new Response(stream).arrayBuffer();
    return new Uint8Array(arrayBuffer);
  }

  if (typeof process !== "undefined" && process.versions?.node) {
    const { inflateSync } = await import("node:zlib");
    const out = inflateSync(bytes);
    return new Uint8Array(out.buffer, out.byteOffset, out.byteLength);
  }

  throw new Error("No deflate decompressor available in this runtime");
}
