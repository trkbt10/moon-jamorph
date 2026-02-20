#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { createTokenizer } from "../../../npm/micado-wasm/index.mjs";

const HELP = `usage: node tools/dict-compiler/scripts/build_aozorahack_freq_tsv.mjs --repo-dir <aozorahack_repo> --out <freq.tsv> [--max-files N] [--max-chars-per-file N] [--min-count N]\n`;

function parseArgs(argv) {
  let repoDir = null;
  let outPath = null;
  let maxFiles = 1200;
  let maxCharsPerFile = 12000;
  let minCount = 1;

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--repo-dir") {
      repoDir = resolve(argv[i + 1]);
      i += 1;
      continue;
    }
    if (arg === "--out") {
      outPath = resolve(argv[i + 1]);
      i += 1;
      continue;
    }
    if (arg === "--max-files") {
      maxFiles = Number.parseInt(argv[i + 1], 10);
      i += 1;
      continue;
    }
    if (arg === "--max-chars-per-file") {
      maxCharsPerFile = Number.parseInt(argv[i + 1], 10);
      i += 1;
      continue;
    }
    if (arg === "--min-count") {
      minCount = Number.parseInt(argv[i + 1], 10);
      i += 1;
      continue;
    }
    throw new Error(`unknown option: ${arg}`);
  }

  if (!repoDir || !outPath) {
    throw new Error(HELP.trim());
  }
  if (!Number.isFinite(maxFiles) || maxFiles <= 0) {
    throw new Error(`invalid --max-files: ${maxFiles}`);
  }
  if (!Number.isFinite(maxCharsPerFile) || maxCharsPerFile <= 0) {
    throw new Error(`invalid --max-chars-per-file: ${maxCharsPerFile}`);
  }
  if (!Number.isFinite(minCount) || minCount <= 0) {
    throw new Error(`invalid --min-count: ${minCount}`);
  }

  return { repoDir, outPath, maxFiles, maxCharsPerFile, minCount };
}

function listAozoraTextFiles(repoDir) {
  const cardsDir = resolve(repoDir, "cards");
  const output = execFileSync("find", [cardsDir, "-type", "f", "-name", "*.txt"], {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
    maxBuffer: 1024 * 1024 * 256,
  });
  return output
    .split(/\r?\n/)
    .map((x) => x.trim())
    .filter(Boolean)
    .sort();
}

function cardIdFromPath(path) {
  const m = path.match(/\/cards\/(\d{6})\//);
  return m ? m[1] : "unknown";
}

function selectDiverseFiles(files, maxFiles) {
  const byCard = new Map();
  for (const path of files) {
    const card = cardIdFromPath(path);
    const arr = byCard.get(card) ?? [];
    arr.push(path);
    byCard.set(card, arr);
  }
  for (const arr of byCard.values()) {
    arr.sort();
  }

  const cards = Array.from(byCard.keys()).sort();
  const picked = [];
  let round = 0;
  while (picked.length < maxFiles) {
    let progressed = false;
    for (const card of cards) {
      const arr = byCard.get(card);
      if (!arr || round >= arr.length) {
        continue;
      }
      picked.push(arr[round]);
      progressed = true;
      if (picked.length >= maxFiles) {
        break;
      }
    }
    if (!progressed) {
      break;
    }
    round += 1;
  }
  return picked;
}

function stripAozoraMarkup(text) {
  let t = text.replace(/^\uFEFF/, "").replace(/\r/g, "");

  let lines = t.split("\n");
  const cut = [];
  for (let i = 0; i < lines.length; i += 1) {
    const line = lines[i].trim();
    if (line.includes("-----") || /^-{20,}$/.test(line)) {
      cut.push(i);
    }
  }
  if (cut.length >= 2) {
    lines = lines.slice(cut[0] + 1, cut[1]);
  }

  const footerIndex = lines.findIndex((line) =>
    /^(底本|入力|校正|公開|作成)\s*：/.test(line.trim())
  );
  if (footerIndex >= 0) {
    lines = lines.slice(0, footerIndex);
  }

  t = lines.join("\n");

  t = t.replace(/［＃[^］]*］/g, "");
  t = t.replace(/《[^》]*》/g, "");
  t = t.replace(/｜/g, "");
  t = t
    .split("\n")
    .filter((line) => {
      const x = line.trim();
      if (x.length === 0) {
        return false;
      }
      if (x.startsWith("※")) {
        return false;
      }
      if (/^(底本|入力|校正|作成|公開|青空文庫|このファイル)/.test(x)) {
        return false;
      }
      return true;
    })
    .join("\n");
  t = t.replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F]/g, "");
  return t;
}

function decodeAozoraBytes(bytes) {
  try {
    return new TextDecoder("shift_jis", { fatal: true }).decode(bytes);
  } catch (_) {
    return new TextDecoder("utf-8").decode(bytes);
  }
}

function isJapaneseSurface(surface) {
  if (!surface || /^\s+$/.test(surface)) {
    return false;
  }
  return /[ぁ-ゖァ-ヺー一-龯々〆ヵヶ]/u.test(surface);
}

function countOccurrences(text, needle) {
  let count = 0;
  let pos = 0;
  while (pos < text.length) {
    const idx = text.indexOf(needle, pos);
    if (idx < 0) {
      break;
    }
    count += 1;
    pos = idx + needle.length;
  }
  return count;
}

function shouldSkipDocument(text) {
  if (text.length < 500) {
    return true;
  }
  const proseHint = countOccurrences(text, "。") + countOccurrences(text, "、");
  if (proseHint < 8) {
    return true;
  }

  const noisyKeywords = [
    "ルビ",
    "外字",
    "入力",
    "校正",
    "底本",
    "区点",
    "傍点",
    "注記",
    "テキスト",
    "記号",
  ];
  let noisyScore = 0;
  for (const key of noisyKeywords) {
    noisyScore += countOccurrences(text, key);
  }
  return noisyScore >= 20;
}

async function main() {
  const { repoDir, outPath, maxFiles, maxCharsPerFile, minCount } = parseArgs(process.argv.slice(2));

  const files = listAozoraTextFiles(repoDir);
  const targets = selectDiverseFiles(files, maxFiles);
  if (targets.length === 0) {
    throw new Error(`no .txt files found under ${repoDir}/cards`);
  }

  const tokenizer = await createTokenizer({ profile: "full", compressed: true });
  const freq = new Map();
  let kept = 0;
  let skipped = 0;

  for (let i = 0; i < targets.length; i += 1) {
    const path = targets[i];
    const raw = await readFile(path);
    const decoded = decodeAozoraBytes(raw);
    const normalized = stripAozoraMarkup(decoded).slice(0, maxCharsPerFile);
    if (!normalized || shouldSkipDocument(normalized)) {
      skipped += 1;
      continue;
    }
    kept += 1;
    const tokens = tokenizer.tokenize(normalized);
    for (const token of tokens) {
      const s = token.surface;
      if (!isJapaneseSurface(s)) {
        continue;
      }
      freq.set(s, (freq.get(s) ?? 0) + 1);
    }
    if ((i + 1) % 100 === 0) {
      console.log(`[aozora-freq] processed ${i + 1}/${targets.length}`);
    }
  }

  const rows = Array.from(freq.entries())
    .filter(([, count]) => count >= minCount)
    .sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0], "ja"));

  await mkdir(dirname(outPath), { recursive: true });
  await writeFile(outPath, rows.map(([s, c]) => `${s}\t${c}`).join("\n") + "\n", "utf8");

  console.log(
    `[aozora-freq] files=${targets.length} kept=${kept} skipped=${skipped} vocab=${rows.length} out=${outPath}`,
  );
}

main().catch((err) => {
  console.error(err?.message ?? String(err));
  process.exit(1);
});
