///|
fn main {
  let text = "すもももももももものうち東京大学東京都大学院自然言語処理abc123"
  let count = 10U
  println("== Scanner benchmark ==")
  println(@bench0.benchmark_scanner(text, count~))
  println("== Tokenizer throughput benchmark ==")
  println(@bench4.benchmark_tokenizer_throughput(text, count~))
}
