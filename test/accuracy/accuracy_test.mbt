///|
fn _keep_imports_alive_accuracy() -> Unit {
  let _ = @tok.EDITION_NANO
  let _ = @utf8.encode(""[:])

}

///|
test "accuracy: sumomo segmentation in nano" {
  let tokenizer = @tok.Tokenizer::new().set_edition(@tok.EDITION_NANO)
  let tokens = tokenizer.tokenize("すもももももももものうち")
  inspect(
    tokens.map(t => t.surface),
    content="[\"すもも\", \"も\", \"もも\", \"も\", \"もも\", \"の\", \"うち\"]",
  )
}

///|
test "accuracy: ipadic detail in standard" {
  let tokenizer = @tok.Tokenizer::new().set_edition(@tok.EDITION_STANDARD)
  let tokens = tokenizer.tokenize("迅速")
  inspect(
    tokens.map(t => t.pos_detail),
    content="[\"名詞,形容動詞語幹,*,*\"]",
  )
}

///|
test "accuracy: neologd detail in full over utf8 bytes" {
  let tokenizer = @tok.Tokenizer::new().set_edition(@tok.EDITION_FULL)
  let bytes = @utf8.encode("!Wagero!"[:])
  let tokens = tokenizer.tokenize_utf8(bytes[:])
  inspect(
    tokens.map(t => t.pos_detail),
    content="[\"名詞,固有名詞,人名,一般\"]",
  )
}

///|
test "accuracy: standard should tokenize mixed known unknown sentence" {
  let tokenizer = @tok.Tokenizer::new().set_edition(@tok.EDITION_STANDARD)
  let tokens = tokenizer.tokenize("迅速な形態素解析")
  inspect(
    tokens.map(t => t.surface),
    content="[\"迅速\", \"な\", \"形態素解析\"]",
  )
  inspect(
    tokens.map(t => t.pos_detail),
    content="[\"名詞,形容動詞語幹,*,*\", \"未知語,ひらがな,*,*\", \"名詞,一般,未知語,*\"]",
  )
}

///|
test "accuracy: full utf8 should keep neologd hashtag as one token" {
  let tokenizer = @tok.Tokenizer::new().set_edition(@tok.EDITION_FULL)
  let bytes = @utf8.encode("#AirPodsを買う"[:])
  let tokens = tokenizer.tokenize_utf8(bytes[:])
  inspect(
    tokens.map(t => t.surface),
    content="[\"#AirPods\", \"を\", \"買\", \"う\"]",
  )
  inspect(
    tokens.map(t => t.pos_detail),
    content="[\"名詞,固有名詞,一般,*\", \"未知語,ひらがな,*,*\", \"名詞,一般,未知語,*\", \"未知語,ひらがな,*,*\"]",
  )
}

///|
test "accuracy: full should keep known proper noun and unknown tail" {
  let tokenizer = @tok.Tokenizer::new().set_edition(@tok.EDITION_FULL)
  let tokens = tokenizer.tokenize("東京スカイツリーに行く")
  inspect(
    tokens.map(t => t.surface),
    content="[\"東京\", \"スカイツリー\", \"に\", \"行\", \"く\"]",
  )
  inspect(
    tokens.map(t => t.pos_detail),
    content="[\"名詞,固有名詞,地域,一般\", \"名詞,固有名詞,未知語,*\", \"未知語,ひらがな,*,*\", \"名詞,一般,未知語,*\", \"未知語,ひらがな,*,*\"]",
  )
}

///|
test "accuracy: hashtag followed by symbol should split at boundary" {
  let tokenizer = @tok.Tokenizer::new().set_edition(@tok.EDITION_FULL)
  let tokens = tokenizer.tokenize("#AirPods!")
  inspect(tokens.map(t => t.surface), content="[\"#AirPods\", \"!\"]")
}
