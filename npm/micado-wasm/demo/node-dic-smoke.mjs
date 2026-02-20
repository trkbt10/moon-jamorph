import { createTokenizer } from "../index.mjs";

const medium = await createTokenizer({ profile: "medium", compressed: true });
const full = await createTokenizer({ profile: "full", compressed: true });

const sentence = "東京大学で自然言語処理を学ぶ";
const mediumTokens = medium.tokenize(sentence);
const fullTokens = full.tokenize(sentence);

if (full.stats.entryCount < 300000) {
  throw new Error(`full profile too small: ${full.stats.entryCount}`);
}

const expectedSurfaces = ["東京大学", "で", "自然", "言語", "処理", "を", "学ぶ"];
const fullSurfaces = fullTokens.map((t) => t.surface);
if (JSON.stringify(fullSurfaces) !== JSON.stringify(expectedSurfaces)) {
  throw new Error(
    `unexpected full tokenization: ${JSON.stringify(fullSurfaces)} expected=${JSON.stringify(expectedSurfaces)}`,
  );
}

console.log(`medium entries=${medium.stats.entryCount} tokens=${mediumTokens.length}`);
console.log(`full entries=${full.stats.entryCount} tokens=${fullTokens.length}`);
console.log(fullTokens.map((t) => `${t.surface}:${t.pos}`).join("|"));
console.log("verification=ok");
