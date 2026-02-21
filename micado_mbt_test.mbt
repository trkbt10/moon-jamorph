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

///|
test "top-level API: constraints and nbest wrappers are available" {
  let constrained = tokenize_with_options("龘龘", {
    constraint: { ..@types.ParseConstraint::none(), must_break_positions: [1] },
  })
  inspect(constrained.map(t => t.surface), content="[\"龘\", \"龘\"]")
  let nbest = tokenize_nbest("龘龘龘", 2)
  assert_eq(nbest.length(), 2)
  inspect(nbest[0].map(t => t.surface), content="[\"龘龘龘\"]")
}
