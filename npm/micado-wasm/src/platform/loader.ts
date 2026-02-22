/**
 * Source types that can be loaded as binary data.
 */
export type BinarySource = Uint8Array | ArrayBuffer | URL | string;

/**
 * Load binary data from various sources.
 * Supports Uint8Array, ArrayBuffer, URL, and string paths.
 */
export async function loadBinary(
  source: BinarySource,
  baseURL?: URL
): Promise<Uint8Array> {
  if (source instanceof Uint8Array) {
    return source;
  }
  if (source instanceof ArrayBuffer) {
    return new Uint8Array(source);
  }

  const url =
    source instanceof URL ? source : new URL(source, baseURL ?? import.meta.url);

  if (url.protocol === "file:") {
    const fs = await import("node:fs/promises");
    const bytes = await fs.readFile(url);
    return new Uint8Array(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  }

  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`Failed to fetch: ${response.status} ${response.statusText}`);
  }
  return new Uint8Array(await response.arrayBuffer());
}

/**
 * Check if a source looks like a compressed file (ends with .deflate).
 */
export function sourceLooksCompressed(source: BinarySource): boolean {
  if (source instanceof URL) {
    return source.pathname.toLowerCase().endsWith(".deflate");
  }
  if (typeof source === "string") {
    return source.toLowerCase().endsWith(".deflate");
  }
  return false;
}
