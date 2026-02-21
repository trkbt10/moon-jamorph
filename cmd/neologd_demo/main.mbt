///|
fn main {
  let tokenizer = @tok.Tokenizer::new().set_edition(@tok.EDITION_FULL)
  let samples = [
    "!Wagero!", "#AirPodsを買う", "吾輩は猫である。名前はまだ無い。",
  ]
  for text in samples {
    let tokens = tokenizer.tokenize(text)
    println("input: \{text}")
    for token in tokens {
      println("\{token.surface}\t\{token.pos_detail}")
    }
    println("---")
  }
}
