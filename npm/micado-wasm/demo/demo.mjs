import { createTokenizer } from "../index.mjs";

const statusEl = document.querySelector("#status");
const inputEl = document.querySelector("#input");
const resultEl = document.querySelector("#result");
const analyzeBtn = document.querySelector("#analyze");

function renderRows(tokens) {
  const html = tokens
    .map(
      (t) =>
        `<tr><td>${t.surface}</td><td>${t.pos_detail}</td><td>${t.start_pos}</td><td>${t.end_pos}</td></tr>`,
    )
    .join("");
  resultEl.innerHTML = html;
}

const tokenizer = await createTokenizer({
  dicURL: new URL("../dist/micado_web_small.dic.bin", import.meta.url),
});

statusEl.textContent = `Ready (${tokenizer.stats.entryCount} entries)`;

analyzeBtn.addEventListener("click", () => {
  const input = inputEl.value ?? "";
  const tokens = tokenizer.tokenize(input);
  renderRows(tokens);
  statusEl.textContent = `${tokens.length} tokens`;
});

renderRows(tokenizer.tokenize(inputEl.value));
