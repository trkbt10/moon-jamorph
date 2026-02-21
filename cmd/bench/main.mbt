///|
fn main {
  let text = "すもももももももものうち吾輩は猫である。名前はまだ無い。abc123"
  let count = 10U
  println("== Scanner benchmark ==")
  println(@bench0.benchmark_scanner(text, count~))
  println("== Tokenizer throughput benchmark ==")
  println(@bench4.benchmark_tokenizer_throughput(text, count~))
}
