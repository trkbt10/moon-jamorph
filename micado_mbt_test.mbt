///|
test "top-level API: tokenize and token_count are consistent" {
  let input = "迅速な形態素解析"
  let tokens = tokenize(input)
  inspect(
    tokens.map(t => t.surface),
    content="[\"迅速\", \"な\", \"形態素解析\"]",
  )
  assert_eq(tokens.length(), token_count(input))
}

///|
test "top-level API: new_tokenizer supports builder-style use" {
  let tokenizer = new_tokenizer()
    .set_edition(EDITION_FULL)
    .set_mode(MODE_SEARCH)
  let tokens = tokenizer.tokenize("吾輩は猫である。")
  assert_true(tokens.length() > 0)
  inspect(tokens[0].surface, content="吾輩")
}
