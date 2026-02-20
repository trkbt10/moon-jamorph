///|
fn main {
  let tokenizer = @tok.Tokenizer::new().set_edition(@tok.EDITION_STANDARD)
  let text = "迅速な形態素解析"
  let tokens = tokenizer.tokenize(text)
  println("input: \{text}")
  for token in tokens {
    println("\{token.surface}\t\{token.pos_detail}")
  }
}
