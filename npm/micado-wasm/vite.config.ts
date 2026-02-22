import { defineConfig } from "vite";

export default defineConfig({
  build: {
    rollupOptions: {
      external: [],
    },
    assetsInlineLimit: 0,
  },
  assetsInclude: [
    "**/*.wasm",
    "**/*.dic.bin.deflate",
    "**/LICENSE.dic.bin",
  ],
  publicDir: false,
  plugins: [
    {
      name: "exclude-uncompressed-dic",
      generateBundle(_, bundle) {
        for (const fileName of Object.keys(bundle)) {
          // Exclude uncompressed dic files (e.g., tiny.dic-HASH.bin)
          // Keep: *.deflate, LICENSE.dic*
          if (
            fileName.match(/\.dic[^/]*\.bin$/) &&
            !fileName.includes("deflate") &&
            !fileName.includes("LICENSE")
          ) {
            delete bundle[fileName];
          }
        }
      },
    },
  ],
});
