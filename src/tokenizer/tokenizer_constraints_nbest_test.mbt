///|
fn options_with(constraint : @types.ParseConstraint) -> @types.ParseOptions {
  { constraint, }
}

///|
test "tokenize_with_options should match tokenize with default options" {
  let tok = Tokenizer::new()
  let text = "迅速な形態素解析"
  let plain = tok.tokenize(text)
  let with_options = tok.tokenize_with_options(
    text,
    @types.ParseOptions::default(),
  )
  inspect(
    with_options.map(t => t.surface),
    content=plain.map(t => t.surface).to_string(),
  )
}

///|
test "constraints should control boundaries on unknown-kanji input" {
  let tok = Tokenizer::new()
  let text = "龘龘"
  let split = tok.tokenize_with_options(
    text,
    options_with({ ..@types.ParseConstraint::none(), must_break_positions: [1] }),
  )
  inspect(split.map(t => t.surface), content="[\"龘\", \"龘\"]")
  let merged = tok.tokenize_with_options(
    text,
    options_with({
      ..@types.ParseConstraint::none(),
      forbid_break_positions: [1],
    }),
  )
  inspect(merged.map(t => t.surface), content="[\"龘龘\"]")
}

///|
test "must_cover_spans should force exact token coverage" {
  let tok = Tokenizer::new()
  let text = "龘龘"
  let covered = tok.tokenize_with_options(
    text,
    options_with({
      ..@types.ParseConstraint::none(),
      must_cover_spans: [{ start_pos: 0, end_pos: 2 }],
    }),
  )
  inspect(covered.map(t => t.surface), content="[\"龘龘\"]")
}

///|
test "allow_unknown=false should reject unknown-only paths" {
  let tok = Tokenizer::new()
  let rejected = tok.tokenize_with_options(
    "🫠",
    options_with({ ..@types.ParseConstraint::none(), allow_unknown: false }),
  )
  inspect(rejected.length(), content="0")
}

///|
test "conflicting constraints should return no result" {
  let tok = Tokenizer::new()
  let rejected = tok.tokenize_with_options(
    "龘龘",
    options_with({
      ..@types.ParseConstraint::none(),
      must_break_positions: [1],
      forbid_break_positions: [1],
    }),
  )
  inspect(rejected.length(), content="0")
}

///|
test "tokenize_nbest_with_options should return sorted costs" {
  let tok = Tokenizer::new()
  let nbest = tok.tokenize_nbest_with_options(
    "龘龘龘",
    3,
    @types.ParseOptions::default(),
  )
  assert_eq(nbest.length(), 3)
  inspect(nbest[0].morphemes.map(t => t.surface), content="[\"龘龘龘\"]")
  let mut sorted = true
  for i in 1..<nbest.length() {
    if nbest[i].total_cost < nbest[i - 1].total_cost {
      sorted = false
    }
  }
  assert_true(sorted)
}

///|
test "tokenize_nbest n=1 should match tokenize result" {
  let tok = Tokenizer::new()
  let plain = tok.tokenize("迅速な形態素解析")
  let nbest = tok.tokenize_nbest("迅速な形態素解析", 1)
  assert_eq(nbest.length(), 1)
  inspect(
    nbest[0].map(t => t.surface),
    content=plain.map(t => t.surface).to_string(),
  )
}

///|
test "tokenize_nbest should return empty for non-positive n" {
  let tok = Tokenizer::new()
  assert_eq(tok.tokenize_nbest("迅速", 0).length(), 0)
  assert_eq(tok.tokenize_nbest("迅速", -1).length(), 0)
  assert_eq(tok.tokenize_nbest("", 3).length(), 0)
  assert_eq(
    tok
    .tokenize_nbest_with_options("", 3, @types.ParseOptions::default())
    .length(),
    0,
  )
}

///|
test "tokenize_utf8_with_options should respect unknown constraint" {
  let tok = Tokenizer::new()
  let emoji = @utf8.encode("🫠"[:])
  let rejected = tok.tokenize_utf8_with_options(
    emoji[:],
    options_with({ ..@types.ParseConstraint::none(), allow_unknown: false }),
  )
  inspect(rejected.length(), content="0")
}

///|
test "tokenize_utf8_nbest n=1 should match tokenize_utf8 result" {
  let tok = Tokenizer::new()
  let bytes = @utf8.encode("迅速な形態素解析"[:])
  let plain = tok.tokenize_utf8(bytes[:])
  let nbest = tok.tokenize_utf8_nbest(bytes[:], 1)
  assert_eq(nbest.length(), 1)
  inspect(
    nbest[0].map(t => t.surface),
    content=plain.map(t => t.surface).to_string(),
  )
}

///|
test "utf8 constraints should use character-index positions" {
  let tok = Tokenizer::new()
  let bytes = @utf8.encode("🫠龘"[:])
  let constrained = tok.tokenize_utf8_with_options(
    bytes[:],
    options_with({
      ..@types.ParseConstraint::none(),
      must_break_positions: [1],
      must_cover_spans: [
        { start_pos: 0, end_pos: 1 },
        { start_pos: 1, end_pos: 2 },
      ],
    }),
  )
  inspect(
    constrained.map(t => "\{t.start_pos}:\{t.end_pos}"),
    content="[\"0:1\", \"1:2\"]",
  )
}
