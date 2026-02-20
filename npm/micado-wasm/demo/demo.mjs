import { createTokenizer, DICTIONARY_PROFILES } from "../index.mjs";

const statusEl = document.querySelector("#status");
const inputEl = document.querySelector("#input");
const resultEl = document.querySelector("#result");
const analyzeBtn = document.querySelector("#analyze");
const exampleEl = document.querySelector("#example");
const profileEl = document.querySelector("#profile");
const compressedEl = document.querySelector("#compressed");

const tokenizerCache = new Map();
const LITERARY_EXAMPLES = [
  { label: "夏目漱石『吾輩は猫である』", text: "吾輩は猫である。名前はまだ無い。" },
  { label: "太宰治『人間失格』", text: "恥の多い生涯を送って来ました。" },
  { label: "芥川龍之介『羅生門』", text: "ある日の暮方の事である。" },
  { label: "森鴎外『舞姫』", text: "石炭をば早や積み果てつ。" },
  { label: "川端康成『雪国』", text: "国境の長いトンネルを抜けると雪国であった。" },
  { label: "島崎藤村『夜明け前』", text: "木曽路はすべて山の中である。" },
  { label: "清少納言『枕草子』", text: "春はあけぼの。やうやう白くなりゆく山ぎは、少しあかりて。" },
  { label: "紫式部『源氏物語』", text: "いづれの御時にか、女御更衣あまたさぶらひ給ひける中に。" },
  { label: "鴨長明『方丈記』", text: "ゆく河の流れは絶えずして、しかももとの水にあらず。" },
  { label: "吉田兼好『徒然草』", text: "つれづれなるままに、日ぐらし硯にむかひて。" },
];

for (const name of DICTIONARY_PROFILES) {
  const option = document.createElement("option");
  option.value = name;
  option.textContent = name;
  if (name === "medium") {
    option.selected = true;
  }
  profileEl.append(option);
}

for (let i = 0; i < LITERARY_EXAMPLES.length; i += 1) {
  const option = document.createElement("option");
  option.value = String(i);
  option.textContent = LITERARY_EXAMPLES[i].label;
  exampleEl.append(option);
}

function pickRandomExampleIndex() {
  return Math.floor(Math.random() * LITERARY_EXAMPLES.length);
}

function setExampleByIndex(index) {
  if (index < 0 || index >= LITERARY_EXAMPLES.length) {
    return;
  }
  exampleEl.value = String(index);
  inputEl.value = LITERARY_EXAMPLES[index].text;
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

compressedEl.addEventListener("change", () => {
  analyzeCurrentInput().catch((err) => {
    statusEl.textContent = `Error: ${err?.message ?? String(err)}`;
  });
});

setExampleByIndex(pickRandomExampleIndex());

analyzeCurrentInput().catch((err) => {
  statusEl.textContent = `Error: ${err?.message ?? String(err)}`;
});
