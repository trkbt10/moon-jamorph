/**
 * ライブラリとして @trkbt10/micado を利用するサンプル
 */

// メインエントリからインポート
import {
  createTokenizer,
  loadDictionary,
  DICTIONARY_PROFILES,
  AOZORA_EXAMPLES,
} from "../dist/index.js";

// 型定義のインポート
import type {
  Tokenizer,
  DetailedToken,
  DictionaryProfile,
  DictionaryStats,
} from "../dist/types.js";

// streamingユーティリティのインポート
import { createTokenStreamWriter } from "../dist/streaming.js";

async function main() {
  console.log("=== @trkbt10/micado ライブラリ利用サンプル ===\n");

  // 1. 利用可能な辞書プロファイル一覧
  console.log("利用可能な辞書プロファイル:", DICTIONARY_PROFILES);

  // 2. プロファイル指定でトークナイザー作成
  console.log("\n--- プロファイル指定でトークナイザー作成 ---");
  const tokenizer: Tokenizer = await createTokenizer({
    profile: "tiny",
    compressed: true,
  });

  console.log("辞書統計:", tokenizer.stats);
  console.log("バックエンド:", tokenizer.backend);

  // 3. テキストをトークン化
  const text = "すもももももももものうち";
  console.log(`\n入力: "${text}"`);

  const tokens: DetailedToken[] = tokenizer.tokenize(text);
  console.log("トークン数:", tokens.length);
  console.log("トークン:");
  for (const token of tokens) {
    console.log(`  ${token.surface} [${token.pos_detail}] (${token.start_pos}-${token.end_pos})`);
  }

  // 4. TSV形式で出力
  console.log("\n--- TSV形式出力 ---");
  const tsv = tokenizer.tokenizeTSV(text);
  console.log(tsv);

  // 5. 直接辞書をロードしてトークナイザー作成
  console.log("\n--- 直接辞書ロード ---");
  const dictPath = new URL("../dist/mini.dic.bin.deflate", import.meta.url);
  const dictBytes = await loadDictionary(dictPath);
  console.log("辞書サイズ:", dictBytes.byteLength, "bytes");

  const tokenizer2 = await createTokenizer(dictBytes);
  console.log("mini辞書エントリ数:", tokenizer2.stats.entryCount);

  // 6. サンプルテキスト（青空文庫）
  console.log("\n--- 青空文庫サンプル ---");
  const example = AOZORA_EXAMPLES[0];
  if (example) {
    console.log(`作品: ${example.label}`);
    console.log(`テキスト: ${example.text.slice(0, 50)}...`);
    const exampleTokens = tokenizer2.tokenize(example.text);
    console.log(`トークン数: ${exampleTokens.length}`);
  }

  // 7. ストリーミングWriter
  console.log("\n--- ストリーミングWriter ---");
  const writer = tokenizer.createWriter({
    format: "detailed",
    windowSize: 3,
  });
  console.log("Writer作成完了");

  console.log("\n=== サンプル完了 ===");
}

main().catch(console.error);
