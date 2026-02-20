# micado_mbt

MoonBit で実装している日本語形態素解析プロジェクトです。

- モジュール名: `username/micado_mbt`（`moon.mod.json`）
- ライセンス: `Apache-2.0`（`LICENSE`）
- 詳細設計: `SPEC.md`

## 現在の構成

```
.
├── src/
│   ├── scanner/utf16, scanner/utf8
│   ├── core/da_trie, lattice, scorer, unknown, viterbi
│   ├── dict/nano, mini, standard, full
│   ├── tokenizer
│   └── types
├── cmd/
│   ├── main          (MeCab dicdir を使う CLI)
│   ├── ipadic_demo   (standard edition demo)
│   ├── neologd_demo  (full edition demo)
│   ├── wasm_api      (wasm 線形 ABI)
│   └── bench
├── tools/
│   ├── dict-compiler
│   └── distribution
├── test/accuracy, test/regression
├── bench/lexmatch_vs_manual, bench/throughput
└── npm/micado-wasm
```

## 公開 API（現状）

`src/tokenizer`:

- `Tokenizer::new()`
- `Tokenizer::set_edition(...)`
- `Tokenizer::set_mode(...)`
- `Tokenizer::set_use_lexmatch_scanner(...)`
- `Tokenizer::tokenize(String)`
- `Tokenizer::tokenize_utf8(BytesView)`
- `EDITION_NANO` / `EDITION_MINI` / `EDITION_STANDARD` / `EDITION_FULL`

`src/types`:

- `Morpheme { surface, pos, pos_detail, mecab_feature, start_pos, end_pos }`

トップレベル `username/micado_mbt` パッケージは現在 `fib` と `sum` を公開しています（`pkg.generated.mbti`）。

## ビルド・整形・テスト

プロジェクト内ドキュメントで使っている基本コマンド:

```sh
moon info
moon fmt
moon test
moon check
```

## 実行例

IPADIC demo:

```sh
moon run cmd/ipadic_demo
```

NEologd demo:

```sh
moon run cmd/neologd_demo
```

MeCab dicdir を使う CLI（`cmd/main`）:

```sh
moon run --target native cmd/main -- -d /path/to/mecab/dic -O mecab "東京大学"
moon run --target native cmd/main -- -d /path/to/mecab/dic -O json "太郎は走った。"
```

`cmd/main` の `--dicdir` は必須で、native/llvm 以外では stub 実装になります（`cmd/main/moon.pkg.json`, `mecab_runner_stub.mbt`）。

## 辞書生成ワークフロー

詳細は `IPADIC_WORKFLOW.md` と `NEOLOGD_WORKFLOW.md`。

IPADIC:

```sh
tools/dict-compiler/scripts/build_ipadic_generated.sh 3000
tools/dict-compiler/scripts/build_connection_generated.sh
```

NEologd:

```sh
tools/dict-compiler/scripts/build_neologd_generated.sh /path/to/mecab-ipadic-neologd-0.0.7 5000
tools/dict-compiler/scripts/build_connection_generated.sh
```

DA 配列生成は `tools/dict-compiler/cmd/emit_da` を内部で利用します。

## Wasm / npm 配布

配布パッケージ: `npm/micado-wasm`（`@micado/wasm`）

- JS エントリ: `index.mjs`
- dic.bin ローダ: `dic-bin.mjs`
- 生成物: `dist/micado_wasm.wasm`, `dist/*.dic.bin`, `dist/*.dic.bin.deflate`

生成:

```sh
tools/distribution/build_wasm_npm.sh
```

または `npm/micado-wasm` で:

```sh
npm run build:wasm
```

## 関連ドキュメント

- `SPEC.md`（設計）
- `IMPLEMENTATION_PLAN.md`（実行計画）
- `PROGRESS.md`（進捗、最終更新: 2026-02-20）
- `PHASE4_REPORT.md`, `PHASE5_REPORT.md`
- `P3_P4_TASK_BOARD.md`
