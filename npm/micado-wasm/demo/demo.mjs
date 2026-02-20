import { createTokenizer, DICTIONARY_PROFILES } from "../index.mjs";

const statusEl = document.querySelector("#status");
const inputEl = document.querySelector("#input");
const resultEl = document.querySelector("#result");
const analyzeBtn = document.querySelector("#analyze");
const profileEl = document.querySelector("#profile");
const compressedEl = document.querySelector("#compressed");

const tokenizerCache = new Map();

for (const name of DICTIONARY_PROFILES) {
  const option = document.createElement("option");
  option.value = name;
  option.textContent = name;
  if (name === "medium") {
    option.selected = true;
  }
  profileEl.append(option);
}

function renderRows(tokens) {
  const html = tokens
    .map(
      (t) =>
        `<tr><td>${t.surface}</td><td>${t.pos_detail}</td><td>${t.start_pos}</td><td>${t.end_pos}</td></tr>`,
    )
    .join("");
  resultEl.innerHTML = html;
}

async function getTokenizer(profile, compressed) {
  const key = `${profile}:${compressed}`;
  if (tokenizerCache.has(key)) {
    return tokenizerCache.get(key);
  }
  const tokenizer = await createTokenizer({ profile, compressed });
  tokenizerCache.set(key, tokenizer);
  return tokenizer;
}

async function analyzeCurrentInput() {
  const profile = profileEl.value;
  const compressed = compressedEl.checked;
  statusEl.textContent = `Loading ${profile} (${compressed ? "deflate" : "raw"})...`;
  const tokenizer = await getTokenizer(profile, compressed);
  const input = inputEl.value ?? "";
  const tokens = tokenizer.tokenize(input);
  renderRows(tokens);
  statusEl.textContent = `${tokens.length} tokens / ${profile} (${tokenizer.stats.entryCount} entries)`;
}

analyzeBtn.addEventListener("click", () => {
  analyzeCurrentInput().catch((err) => {
    statusEl.textContent = `Error: ${err?.message ?? String(err)}`;
  });
});

profileEl.addEventListener("change", () => {
  analyzeCurrentInput().catch((err) => {
    statusEl.textContent = `Error: ${err?.message ?? String(err)}`;
  });
});

compressedEl.addEventListener("change", () => {
  analyzeCurrentInput().catch((err) => {
    statusEl.textContent = `Error: ${err?.message ?? String(err)}`;
  });
});

analyzeCurrentInput().catch((err) => {
  statusEl.textContent = `Error: ${err?.message ?? String(err)}`;
});
