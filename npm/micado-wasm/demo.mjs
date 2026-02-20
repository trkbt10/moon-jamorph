import { createTokenizer, DICTIONARY_PROFILES } from "./index.mjs";
import { AOZORA_EXAMPLES } from "./examples.mjs";

const statusEl = document.querySelector("#status");
const inputEl = document.querySelector("#input");
const resultEl = document.querySelector("#result");
const analyzeBtn = document.querySelector("#analyze");
const exampleEl = document.querySelector("#example");
const profileEl = document.querySelector("#profile");

const tokenizerCache = new Map();

for (const name of DICTIONARY_PROFILES) {
  const option = document.createElement("option");
  option.value = name;
  option.textContent = name;
  if (name === "full") {
    option.selected = true;
  }
  profileEl.append(option);
}

for (let i = 0; i < AOZORA_EXAMPLES.length; i += 1) {
  const option = document.createElement("option");
  option.value = String(i);
  option.textContent = AOZORA_EXAMPLES[i].label;
  exampleEl.append(option);
}

function pickRandomExampleIndex() {
  return Math.floor(Math.random() * AOZORA_EXAMPLES.length);
}

function setExampleByIndex(index) {
  if (index < 0 || index >= AOZORA_EXAMPLES.length) {
    return;
  }
  exampleEl.value = String(index);
  inputEl.value = AOZORA_EXAMPLES[index].text;
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

async function getTokenizer(profile) {
  const key = profile;
  if (tokenizerCache.has(key)) {
    return tokenizerCache.get(key);
  }
  const tokenizer = await createTokenizer({ profile, compressed: true });
  tokenizerCache.set(key, tokenizer);
  return tokenizer;
}

async function analyzeCurrentInput() {
  const profile = profileEl.value;
  statusEl.textContent = `Loading ${profile} (deflate)...`;
  const tokenizer = await getTokenizer(profile);
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

exampleEl.addEventListener("change", () => {
  const index = Number.parseInt(exampleEl.value, 10);
  if (Number.isFinite(index)) {
    setExampleByIndex(index);
  }
  analyzeCurrentInput().catch((err) => {
    statusEl.textContent = `Error: ${err?.message ?? String(err)}`;
  });
});

profileEl.addEventListener("change", () => {
  analyzeCurrentInput().catch((err) => {
    statusEl.textContent = `Error: ${err?.message ?? String(err)}`;
  });
});

setExampleByIndex(pickRandomExampleIndex());

analyzeCurrentInput().catch((err) => {
  statusEl.textContent = `Error: ${err?.message ?? String(err)}`;
});
