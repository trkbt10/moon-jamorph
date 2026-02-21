# micado

`micado` は、MoonBit で実装している日本語形態素解析プロジェクトです。

- ライセンス: `Apache-2.0`（`LICENSE`）
- GitHub Pages Demo: [https://trkbt10.github.io/moon-jamorph/](https://trkbt10.github.io/moon-jamorph/)

## できること

- `src/tokenizer` で日本語テキストを形態素に分割
- 制約つき解析（境界制約 / 品詞制約 / 未知語許可制御）
- N-best 解（`tokenize_nbest*`）の取得
- `cmd/main` で MeCab 辞書ディレクトリ（`--dicdir`）を使った CLI 実行
- `npm/micado-wasm` で Wasm + `.dic.bin` のブラウザ向け配布

## 形態素解析器の比較（概要）

この表は、主要な日本語形態素解析器の設計思想と実装上の違いを、実装方式の観点で並べたものです。
`micado` は現時点で完全互換を目的にしているわけではありませんが、方向性としては **MeCab 系（DA + Viterbi + 連接コスト）** に近い設計を採っています。
軽量な `dic.bin` プロファイル（`tiny/mini/medium`）は配布サイズを優先するため、`full` と比べて精度が落ちる場合があります。`full` は参照精度、`tiny/mini/medium` は用途別のトレードオフ用です。

| 項目 | **micado** | **MeCab** | [ChaSen](http://chasen.naist.jp/) | [JUMAN](http://pine.kuee.kyoto-u.ac.jp/nl-resource/juman.html) | [KAKASI](http://kakasi.namazu.org) |
|---|---|---|---|---|---|
| 解析モデル | bi-gram マルコフモデル | bi-gram マルコフモデル | 可変長マルコフモデル | bi-gram マルコフモデル | 最長一致 |
| コスト推定 | MeCab辞書から取得 | コーパスから学習 | コーパスから学習 | 人手 | コストという概念なし |
| 学習モデル | -（辞書依存） | [CRF](http://www.cis.upenn.edu/~pereira/papers/crf.pdf)（識別モデル） | HMM（生成モデル） | - | - |
| 辞書引きアルゴリズム | Double Array | Double Array | Double Array | パトリシア木 | Hash? |
| 解探索アルゴリズム | Viterbi | Viterbi | Viterbi | Viterbi | 決定的? |
| 連接表の実装 | 2次元 Table（圧縮ID） | 2次元 Table | オートマトン | 2次元 Table? | 連接表なし? |
| 品詞の階層 | 簡易列挙型 + mecab_feature | 無制限多階層品詞 | 無制限多階層品詞 | 2段階固定 | 品詞という概念なし? |
| 未知語処理 | 字種（複数候補生成） | 字種（動作定義を変更可能） | 字種（変更不可能） | 字種（変更不可能） | - |
| 制約つき解析 | 可能 | 可能 | 2.4.0 で可能 | 不可能 | 不可能 |
| N-best 解 | 可能 | 可能 | 不可能 | 不可能 | 不可能 |

補足:
- この比較は MeCab 作者サイト等で知られている実装比較を要約したものです。
- `micado` の開発目標は、上記のうち MeCab 系の実用上重要な要素（辞書引き・スコアリング・探索）を段階的に高精度化することです。

## ディレクトリ構成

```text
.
├── src/
│   ├── scanner/utf16, scanner/utf8
│   ├── core/da_trie, lattice, scorer, unknown, viterbi
│   ├── cli/mecab     (MeCab互換CLIロジック)
│   ├── tokenizer
│   └── types
├── cmd/
│   ├── main          (MeCab dicdir を使う CLI)
│   ├── tokenize      (stdin を内部 tokenizer で処理する CLI)
│   ├── ipadic_demo   (standard edition demo)
│   ├── neologd_demo  (full edition demo)
│   ├── wasm_api      (wasm 線形 ABI)
│   └── bench
├── tools/
│   ├── dict-compiler
│   ├── distribution
│   └── benchmark
├── bench/corpus
├── bench/lexmatch_vs_manual, bench/throughput
└── npm/micado-wasm
```

運用境界:

- ライブラリ層: `src/**` + トップレベルパッケージ（`trkbt10/micado_mbt`）
- CLI層: `src/cli/**` + `cmd/**`（`cmd/main` は MeCab 互換の `--dicdir` フロー）

## 主要 API

トップレベル（`trkbt10/micado_mbt`）:

- `new_tokenizer()`
- `tokenize(String)`
- `tokenize_with_options(String, ParseOptions)`
- `tokenize_nbest(String, Int)`
- `tokenize_nbest_with_options(String, Int, ParseOptions)`
- `tokenize_utf8(BytesView)`
- `tokenize_utf8_with_options(BytesView, ParseOptions)`
- `tokenize_utf8_nbest(BytesView, Int)`
- `tokenize_utf8_nbest_with_options(BytesView, Int, ParseOptions)`
- `token_count(String)`
- `EDITION_NANO` / `EDITION_MINI` / `EDITION_STANDARD` / `EDITION_FULL`
- `MODE_NORMAL` / `MODE_SEARCH`

ライブラリ利用時は、まずトップレベルを入口にし、必要に応じて `src/tokenizer` / `src/types` を直接使ってください。

`src/tokenizer`:

- `Tokenizer::new()`
- `Tokenizer::set_edition(...)`
- `Tokenizer::set_mode(...)`
- `Tokenizer::set_use_lexmatch_scanner(...)`
- `Tokenizer::tokenize(String)`
- `Tokenizer::tokenize_with_options(String, ParseOptions)`
- `Tokenizer::tokenize_nbest(String, Int)`
- `Tokenizer::tokenize_nbest_with_options(String, Int, ParseOptions)`
- `Tokenizer::tokenize_utf8(BytesView)`
- `Tokenizer::tokenize_utf8_with_options(BytesView, ParseOptions)`
- `Tokenizer::tokenize_utf8_nbest(BytesView, Int)`
- `Tokenizer::tokenize_utf8_nbest_with_options(BytesView, Int, ParseOptions)`
- `EDITION_NANO` / `EDITION_MINI` / `EDITION_STANDARD` / `EDITION_FULL`
  - 互換のため残しています（`src/dict` 廃止後は同一挙動）。

`src/types`:

- `Morpheme { surface, pos, pos_detail, mecab_feature, start_pos, end_pos }`
- `ParseConstraint { must_break_positions, forbid_break_positions, must_cover_spans, allowed_pos, disallowed_pos, allow_unknown }`
- `ParseOptions { constraint }`
- `NBestResult { morphemes, total_cost }`

## 開発用コマンド

```sh
moon info
moon fmt
moon test
moon check
```

## 実行時スモーク検証（CLI + Wasm）

外付け MeCab 辞書 (`--dicdir`) と `.dic.bin` の両方を一度に検証:

```sh
tools/distribution/verify_cli_wasm.sh
```

- CLI (`cmd/main`, native target) を実行し、JSON/分かち書き出力を検証
- 非UTF-8辞書（例: `ipadic`）は `config-charset` を検出して UTF-8 へ変換
- Wasm + `.dic.bin` をビルドして Node スモークを実行
- 入力文は `npm/micado-wasm/demo/smoke-sentence.txt` を CLI/Wasm で共通利用
- CI では `.github/workflows/runtime-smoke.yml` から同じ検証を実行

## 実行方法

`ipadic_demo`:

```sh
moon run cmd/ipadic_demo
```

`neologd_demo`:

```sh
moon run cmd/neologd_demo
```

MeCab `dicdir` を使う CLI（`cmd/main`）:

```sh
moon run --target native cmd/main -- -d /path/to/mecab/dic -O mecab "吾輩は猫である。"
moon run --target native cmd/main -- -d /path/to/mecab/dic -O json "太郎は走った。"
```

`cmd/main` では `--dicdir` が必須です。native/llvm 以外では stub 実装になります（`cmd/main/moon.pkg.json`, `mecab_runner_stub.mbt`）。

内部 tokenizer を stdin から実行する CLI（`cmd/tokenize`）:

```sh
cat bench/corpus/aozora_openings.txt | moon run --target native cmd/tokenize --
cat bench/corpus/aozora_openings.txt | moon run --target native cmd/tokenize -- -O wakati
```

`cmd/tokenize` は MeCab 互換寄りのオプション名に対応しています（互換サブセット）。

- `-O, --output-format-type <type>`: `mecab`（既定）/ `wakati` / `none`（`count` は独自拡張）
- `-N, --nbest <n>`（`--nbest=<n>` も可）: N-best 出力数
- `-d, --dicdir <dir>`（`--dicdir=<dir>` も可）: 互換用に受理（現状は未使用）
- `--no-unknown`: 未知語トークンを含む経路を拒否
- `--must-break <csv>`: 指定位置（文字インデックス）に必須境界を要求
- `--forbid-break <csv>`: 指定位置（文字インデックス）に境界を禁止
- `--must-cover-span <csv>`: 必須トークン span を要求（`start:end` 形式）
- `--allow-pos <csv>`: 許可 POS を制限（`noun-general,particle,...`）
- `--disallow-pos <csv>`: 禁止 POS を指定

例:

```sh
printf '太郎は走る\n' | moon run --target native cmd/tokenize --
printf '太郎は走る\n' | moon run --target native cmd/tokenize -- -O wakati
printf '龘龘龘\n' | moon run --target native cmd/tokenize -- --output-format-type=wakati --nbest=3 --must-break 1
printf '龘龘\n' | moon run --target native cmd/tokenize -- -O wakati --must-cover-span 0:2
printf '迅速\n' | moon run --target native cmd/tokenize -- -O count --allow-pos noun-general
```

## 軽量ベンチ比較

`tools/benchmark/run_all.sh` を実行すると、`micado` / `mecab` / `vibrato` の比較を回して
結果テキストと SVG / PNG グラフを自動生成します。

```sh
tools/benchmark/run_all.sh --dicdir /opt/homebrew/lib/mecab/dic/ipadic
```

共有しやすい画像サイズにしたい場合は、`--png-max-width`（既定: `960`）と
`--chart-layout auto|horizontal|vertical` を指定できます（既定: `auto`）。

出力されるベンチ指標は次の方針です。

- `Elapsed_seconds_to_tokenize_all_sentences` / `Sentences_per_second` は起動コスト込み（従来互換）
- `*_without_startup_estimate` は空入力計測を差し引いた推定値（起動影響を抑えた比較用）
- グラフは上記2系統（起動込み / 差し引き推定）を併記

生成物:

```text
bench/benchmark/quick_compare_latest.txt
bench/benchmark/quick_compare_latest.svg
bench/benchmark/quick_compare_latest.png
```

<!-- BENCHMARK_RESULTS_BEGIN -->
実測結果（`bench/benchmark/quick_compare_latest.txt` から自動更新）:

```text
[micado/full]
Warmup: 0.048463
Warmup_startup_overhead_estimate: 0.007016
Warmup_without_startup_estimate: 0.041447
Number_of_sentences: 20000
Elapsed_seconds_to_tokenize_all_sentences: [0.043505,0.044134,0.045193]
Sentences_per_second: [442546.41,453165.36,459717.27]
Startup_overhead_seconds_estimate: [0.005730,0.006015,0.006438]
Elapsed_seconds_without_startup_estimate: [0.037775,0.038119,0.038755]
Sentences_per_second_without_startup_estimate: [516062.44,524672.74,529450.69]

[mecab/ipadic]
Warmup: 0.176983
Warmup_startup_overhead_estimate: 0.006401
Warmup_without_startup_estimate: 0.170582
Number_of_sentences: 20000
Elapsed_seconds_to_tokenize_all_sentences: [0.173306,0.175538,0.179938]
Sentences_per_second: [111149.40,113935.44,115402.81]
Startup_overhead_seconds_estimate: [0.006118,0.006372,0.006757]
Elapsed_seconds_without_startup_estimate: [0.167188,0.169166,0.173181]
Sentences_per_second_without_startup_estimate: [115486.11,118227.07,119625.81]

[vibrato/ipadic-mecab-2_7_0]
Warmup: 0.216959
Warmup_startup_overhead_estimate: 0.135492
Warmup_without_startup_estimate: 0.081466
Number_of_sentences: 20000
Elapsed_seconds_to_tokenize_all_sentences: [0.166726,0.170203,0.176622]
Sentences_per_second: [113236.03,117506.98,119957.00]
Startup_overhead_seconds_estimate: [0.130243,0.132174,0.134707]
Elapsed_seconds_without_startup_estimate: [0.036484,0.038028,0.041916]
Sentences_per_second_without_startup_estimate: [477149.70,525922.69,548189.76]
```

![軽量ベンチ比較チャート](bench/benchmark/quick_compare_latest.svg)

<!-- BENCHMARK_RESULTS_END -->

## 辞書運用方針

`src/dict` は廃止済みです。

- ネイティブCLIは外付け MeCab 辞書（`--dicdir`）を利用します。
- Web/npm は `.dic.bin` を実行時ロードします。
- `tools/dict-compiler/scripts/build_*_generated.sh` は廃止され、実行するとエラー終了します。
- Web向け辞書生成は `tools/dict-compiler/scripts/build_web_dic_artifacts.mjs` に統一されています。

## 配布モデル（推奨）

配布は次の2系統に分けます。

- Moon package（軽量）: CLI/コアコードのみ。MeCab互換CLIは `--dicdir` で外付け辞書を使う
- Wasm配布（辞書同梱）: `npm/micado-wasm/dist` をベースに `.dic.bin(.deflate)` を含めて配る

一括生成:

```sh
tools/distribution/package_release_assets.sh
```

GitHub Actions:

- `.github/workflows/release-assets.yml`
  - `workflow_dispatch` または `v*` タグ push で実行
  - `_build/release/*` を Artifact / GitHub Release に添付
  - `moon publish` は実行しない

生成物:

- `_build/release/*-moon-module-v<version>.zip`
- `_build/release/micado-wasm-with-dic-v<version>.tar.gz`

オプション:

- `WASM_RELEASE_PROFILES=tiny,mini,medium` で同梱プロファイルを制限
- `WASM_RELEASE_INCLUDE_RAW_DIC=1` で `.dic.bin`（非deflate）も同梱

## Wasm / npm 配布

配布ディレクトリは `npm/micado-wasm` です。

- JS エントリ: `index.mjs`
- dic.bin ローダ: `dic-bin.mjs`（I/Oのみ）
- 生成物: `dist/micado_wasm.wasm`, `dist/*.dic.bin`, `dist/*.dic.bin.deflate`
- `dic.bin` は `surface/mecab_feature/left_id/right_id/word_cost` を保持する現行フォーマットのみサポート（旧形式との互換は持たない）
- 形態素解析ロジック本体は MoonBit wasm 側に統一（`dic-bin.mjs` に解析実装は持たない）

生成コマンド:

```sh
tools/distribution/build_wasm_npm.sh
```

または `npm/micado-wasm` で:

```sh
npm run build:wasm
```
