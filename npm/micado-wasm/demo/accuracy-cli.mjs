import { readFile } from "node:fs/promises";
import { createTokenizer } from "../index.mjs";
import { AOZORA_EXAMPLES } from "./examples.mjs";

function parseArgs(argv) {
  const out = {
    profiles: ["tiny", "mini", "medium"],
    top: 20,
    input: null,
  };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--profiles") {
      out.profiles = argv[i + 1].split(",").map((x) => x.trim()).filter(Boolean);
      i += 1;
      continue;
    }
    if (arg === "--top") {
      out.top = Number.parseInt(argv[i + 1], 10);
      i += 1;
      continue;
    }
    if (arg === "--input") {
      out.input = argv[i + 1];
      i += 1;
      continue;
    }
    throw new Error(`unknown option: ${arg}`);
  }
  return out;
}

async function loadSentences(path) {
  if (!path) {
    return AOZORA_EXAMPLES.map((x) => ({ label: x.label, text: x.text }));
  }
  const raw = await readFile(path, "utf8");
  return raw
    .split(/\r?\n/)
    .map((x, i) => ({ label: `line:${i + 1}`, text: x.trim() }))
    .filter((x) => x.text.length > 0);
}

function tokenSurfaces(tokens) {
  return tokens.map((t) => t.surface);
}

function boundaries(tokens) {
  const set = new Set();
  for (const t of tokens) {
    set.add(t.end_pos);
  }
  return set;
}

function intersectSize(a, b) {
  let count = 0;
  for (const x of a) {
    if (b.has(x)) {
      count += 1;
    }
  }
  return count;
}

function fmtPct(numerator, denominator) {
  if (denominator === 0) {
    return "0.00%";
  }
  return `${((numerator / denominator) * 100).toFixed(2)}%`;
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  const samples = await loadSentences(options.input);

  const fullTokenizer = await createTokenizer({ profile: "full", compressed: true });
  const fullTokenized = samples.map((s) => ({
    ...s,
    tokens: fullTokenizer.tokenize(s.text),
  }));

  const refSurfaceFreq = new Map();
  let refTokenTotal = 0;
  let refBoundaryTotal = 0;
  for (const s of fullTokenized) {
    refTokenTotal += s.tokens.length;
    refBoundaryTotal += boundaries(s.tokens).size;
    for (const t of s.tokens) {
      refSurfaceFreq.set(t.surface, (refSurfaceFreq.get(t.surface) ?? 0) + 1);
    }
  }

  console.log(`# Accuracy Report`);
  console.log(`sentences=${samples.length} ref_profile=full ref_tokens=${refTokenTotal}`);

  for (const profile of options.profiles) {
    const tokenizer = await createTokenizer({ profile, compressed: true });
    const entries = Array.isArray(tokenizer.entries) ? tokenizer.entries : [];
    const dictSurfaceSet = new Set(entries.map((e) => e.surface));

    let sentenceExact = 0;
    let tokenMatch = 0;
    let predTokenTotal = 0;
    let predBoundaryTotal = 0;
    let boundaryHit = 0;

    const perSentence = [];
    for (let i = 0; i < fullTokenized.length; i += 1) {
      const ref = fullTokenized[i];
      const predTokens = tokenizer.tokenize(ref.text);
      const refSurfaces = tokenSurfaces(ref.tokens);
      const predSurfaces = tokenSurfaces(predTokens);
      const exact = JSON.stringify(refSurfaces) === JSON.stringify(predSurfaces);
      if (exact) {
        sentenceExact += 1;
      }

      const samePos = Math.min(refSurfaces.length, predSurfaces.length);
      for (let j = 0; j < samePos; j += 1) {
        if (refSurfaces[j] === predSurfaces[j]) {
          tokenMatch += 1;
        }
      }

      predTokenTotal += predSurfaces.length;

      const refBoundary = boundaries(ref.tokens);
      const predBoundary = boundaries(predTokens);
      predBoundaryTotal += predBoundary.size;
      boundaryHit += intersectSize(refBoundary, predBoundary);

      perSentence.push({
        label: ref.label,
        exact,
      });
    }

    const boundaryPrecision = predBoundaryTotal === 0 ? 0 : boundaryHit / predBoundaryTotal;
    const boundaryRecall = refBoundaryTotal === 0 ? 0 : boundaryHit / refBoundaryTotal;
    const boundaryF1 =
      boundaryPrecision + boundaryRecall === 0
        ? 0
        : (2 * boundaryPrecision * boundaryRecall) / (boundaryPrecision + boundaryRecall);

    let coveredByDict = 0;
    let totalFreq = 0;
    const missing = [];
    if (entries.length > 0) {
      for (const [surface, count] of refSurfaceFreq.entries()) {
        totalFreq += count;
        if (dictSurfaceSet.has(surface)) {
          coveredByDict += count;
        } else {
          missing.push({ surface, count });
        }
      }
      missing.sort((a, b) => b.count - a.count || a.surface.localeCompare(b.surface, "ja"));
    }

    console.log(`\n[profile=${profile}]`);
    console.log(`entry_count=${tokenizer.stats.entryCount}`);
    console.log(`sentence_exact=${sentenceExact}/${samples.length} (${fmtPct(sentenceExact, samples.length)})`);
    console.log(
      `token_pos_match=${tokenMatch}/${Math.max(refTokenTotal, predTokenTotal)} (${fmtPct(tokenMatch, Math.max(refTokenTotal, predTokenTotal))})`,
    );
    console.log(
      `boundary: precision=${(boundaryPrecision * 100).toFixed(2)}% recall=${(boundaryRecall * 100).toFixed(2)}% f1=${(boundaryF1 * 100).toFixed(2)}%`,
    );
    if (entries.length > 0) {
      console.log(`dict_coverage_by_ref_freq=${coveredByDict}/${totalFreq} (${fmtPct(coveredByDict, totalFreq)})`);
    } else {
      console.log("dict_coverage_by_ref_freq=unavailable (wasm runtime index)");
    }

    const failed = perSentence.filter((x) => !x.exact).map((x) => x.label);
    console.log(`failed_examples=${failed.length === 0 ? "none" : failed.join(" | ")}`);

    if (entries.length > 0) {
      const topMissing = missing.slice(0, options.top);
      if (topMissing.length === 0) {
        console.log("top_missing_surfaces=none");
      } else {
        console.log("top_missing_surfaces:");
        for (const row of topMissing) {
          console.log(`  ${row.surface}\t${row.count}`);
        }
      }
    } else {
      console.log("top_missing_surfaces=unavailable");
    }
  }
}

main().catch((err) => {
  console.error(err?.message ?? String(err));
  process.exit(1);
});
