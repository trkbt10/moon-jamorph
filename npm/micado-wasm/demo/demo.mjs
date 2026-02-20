import { createMicadoWasm } from "../index.mjs";

const statusEl = document.querySelector("#status");
const inputEl = document.querySelector("#input");
const resultEl = document.querySelector("#result");
const analyzeBtn = document.querySelector("#analyze");

function selectedEdition() {
  const checked = document.querySelector("input[name='edition']:checked");
  return checked ? checked.value : "nano";
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

const micado = await createMicadoWasm({
  wasmURL: new URL("../dist/micado_wasm.wasm", import.meta.url),
});

statusEl.textContent = "Ready";

analyzeBtn.addEventListener("click", () => {
  const input = inputEl.value ?? "";
  const edition = selectedEdition();
  const tokens =
    edition === "mini" ? micado.tokenizeMini(input) : micado.tokenizeNano(input);
  renderRows(tokens);
  statusEl.textContent = `${tokens.length} tokens`;
});

renderRows(micado.tokenizeNano(inputEl.value));
