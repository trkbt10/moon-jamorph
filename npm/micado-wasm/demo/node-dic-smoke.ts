import { readFile } from "node:fs/promises";
import { createTokenizer } from "../src/index.js";

const medium = await createTokenizer({ profile: "medium", compressed: true });
const full = await createTokenizer({ profile: "full", compressed: true });

const sentence = (
  await readFile(new URL("./smoke-sentence.txt", import.meta.url), "utf8")
).trim();
const mediumTokens = medium.tokenize(sentence);
const fullTokens = full.tokenize(sentence);

if (full.stats.entryCount < 300000) {
  throw new Error(`full profile too small: ${full.stats.entryCount}`);
}
if ((full.stats.connectionIdCount ?? 0) < 100) {
  throw new Error(
    `connection matrix ids too small: ${full.stats.connectionIdCount}`
  );
}

const fullSurfaces = fullTokens.map((t) => t.surface);
for (const required of ["吾輩", "猫", "名前", "無い"]) {
  if (!fullSurfaces.includes(required)) {
    throw new Error(
      `missing required surface: ${required} got=${JSON.stringify(fullSurfaces)}`
    );
  }
}
if (fullSurfaces.some((s) => s.includes("�"))) {
  throw new Error(`mojibake detected: ${JSON.stringify(fullSurfaces)}`);
}

console.log(
  `medium entries=${medium.stats.entryCount} tokens=${mediumTokens.length}`
);
console.log(`full entries=${full.stats.entryCount} tokens=${fullTokens.length}`);
console.log(fullTokens.map((t) => `${t.surface}:${t.pos}`).join("|"));
console.log("verification=ok");
