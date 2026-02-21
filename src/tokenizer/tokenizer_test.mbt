///|
test "token_count should match tokenize length" {
  let tok = Tokenizer::new().set_edition(EDITION_FULL)
  let text = "吾輩は猫である。名前はまだ無い。"
  let tokens = tok.tokenize(text)
  let count = tok.token_count(text)
  inspect(count, content=tokens.length().to_string())
}

///|
test "token_count should be zero for empty input" {
  let tok = Tokenizer::new()
  inspect(tok.token_count(""), content="0")
}
