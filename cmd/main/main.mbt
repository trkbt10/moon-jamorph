///|
fn main {
  let tokens = @tok.Tokenizer::new().tokenize(
    "すもももももももものうち",
  )
  for token in tokens {
    println("\{token.surface}\t\{token.pos_detail}")
  }
}
