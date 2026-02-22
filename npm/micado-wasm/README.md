# micado

Japanese morphological analyzer powered by MoonBit + WebAssembly.

[![npm version](https://img.shields.io/npm/v/@trkbt10/micado.svg)](https://www.npmjs.com/package/@trkbt10/micado)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](https://github.com/trkbt10/moon-jamorph/blob/main/LICENSE)

## Features

- Pure WebAssembly runtime (no native dependencies)
- Multiple dictionary profiles: `tiny`, `mini`, `medium`, `full`
- Deflate-compressed dictionaries for minimal bundle size
- Works in Node.js and browsers
- MeCab-compatible token output

## Installation

```bash
npm install @trkbt10/micado
```

## Quick Start

```javascript
import { createTokenizer } from "@trkbt10/micado";

const tokenizer = await createTokenizer();
const tokens = tokenizer.tokenize("吾輩は猫である。名前はまだ無い。");

for (const token of tokens) {
  console.log(`${token.surface}\t${token.pos_detail}`);
}
```

Output:

```
吾輩	名詞,代名詞,一般,*,*,*,吾輩,ワガハイ,ワガハイ
は	助詞,係助詞,*,*,*,*,は,ハ,ワ
猫	名詞,一般,*,*,*,*,猫,ネコ,ネコ
で	助動詞,*,*,*,特殊・ダ,連用形,だ,デ,デ
ある	助動詞,*,*,*,五段・ラ行アル,基本形,ある,アル,アル
。	記号,句点,*,*,*,*,。,。,。
...
```

## API

### `createTokenizer(options?)`

Creates a tokenizer instance with the specified dictionary profile.

```typescript
const tokenizer = await createTokenizer({
  profile: "full",      // "tiny" | "mini" | "medium" | "full" (default: "full")
  compressed: true,     // Use deflate-compressed dictionary (default: true)
});

// Tokenize to detailed tokens
const tokens = tokenizer.tokenize("東京都に住む");

// Tokenize to TSV string
const tsv = tokenizer.tokenizeTSV("東京都に住む");
```

### `createMicadoWasm(options?)`

Creates a dual-tokenizer for scenarios requiring multiple dictionary profiles.

```typescript
const wasm = await createMicadoWasm({
  nanoProfile: "tiny",
  miniProfile: "mini",
});

const nanoTokens = wasm.tokenizeNano("すもももももももものうち");
const miniTokens = wasm.tokenizeMini("すもももももももものうち");
```

## Token Format

### DetailedToken

```typescript
interface DetailedToken {
  surface: string;      // Surface form (the actual text)
  pos: string;          // Short POS: "品詞,品詞細分類1"
  pos_detail: string;   // Full POS detail (comma-separated)
  mecab_feature: string; // MeCab feature string
  start_pos: number;    // Start byte offset
  end_pos: number;      // End byte offset (exclusive)
}
```

### CompactToken

```typescript
interface CompactToken {
  surface: string;
  pos_detail: string;
  start_pos: number;
  end_pos: number;
}
```

## Dictionary Profiles

| Profile | Entries | Size (deflate) | Use Case |
|---------|---------|----------------|----------|
| `tiny` | ~1,500 | ~50KB | Minimal, high-frequency words only |
| `mini` | ~5,000 | ~150KB | Basic tokenization |
| `medium` | ~12,000 | ~350KB | Balanced accuracy/size |
| `full` | All | ~2MB | Maximum accuracy |

## Browser Usage

```html
<script type="module">
import { createTokenizer } from "https://cdn.jsdelivr.net/npm/@trkbt10/micado/dist/index.js";

const tokenizer = await createTokenizer({ profile: "tiny" });
const tokens = tokenizer.tokenize("こんにちは世界");
console.log(tokens);
</script>
```

## Demo

Live demo: [https://trkbt10.github.io/moon-jamorph/](https://trkbt10.github.io/moon-jamorph/)

## License

Apache-2.0
