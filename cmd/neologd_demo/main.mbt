///|
fn main {
  let tokenizer = @tok.Tokenizer::new().set_edition(@tok.EDITION_FULL)
  let samples = [
    "!Wagero!", "#AirPodsを買う", "東京スカイツリーに行く",
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
